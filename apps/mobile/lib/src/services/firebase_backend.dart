import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/messenger_models.dart';
import 'audio_storage_upload.dart';
import 'handle_policy.dart';
import 'local_audio_bytes.dart';
import 'messenger_backend.dart';
import 'realtime_relay_health.dart';

String _voiceTranscriptValue(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return '';
  }
  const placeholders = {
    '\uC74C\uC131 \uBA54\uC2DC\uC9C0',
    'Voice message',
    '\uC74C\uC131 \uBCC0\uD658 \uC911...',
    '\uC74C\uC131 \uBCC0\uD658 \uB300\uAE30 \uC911...',
    '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328',
    '\uC74C\uC131 \uBCC0\uD658\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.',
    '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC \uC5C6\uC74C',
    '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC\uAC00 \uBE44\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.',
  };
  const mojibakeSignals = {
    '\uFFFD',
    '???',
    '\u7650',
    '\u7B4C',
    '\u56A5',
    '\u91CE',
    '\u63F6',
    '\u69AE',
    '\u63F4',
    '\u6FE1',
    '\u5A9B',
  };
  final hasCorruptedPlaceholder =
      RegExp(r'\?{3,}').hasMatch(text) && text.length > 12 ||
      mojibakeSignals.any(text.contains);
  return placeholders.contains(text) || hasCorruptedPlaceholder ? '' : text;
}

class _RealtimeProviderHealthCacheEntry {
  const _RealtimeProviderHealthCacheEntry({
    required this.available,
    required this.expiresAt,
  });

  final bool available;
  final DateTime expiresAt;
}

class FirebaseMessengerBackend implements MessengerBackend {
  FirebaseMessengerBackend({
    FirebaseFirestore? firestore,
    auth.FirebaseAuth? firebaseAuth,
    FirebaseStorage? storage,
    FirebaseMessaging? messaging,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = firebaseAuth ?? auth.FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             region: const String.fromEnvironment(
               'FIREBASE_FUNCTIONS_REGION',
               defaultValue: 'asia-northeast3',
             ),
           );

  final FirebaseFirestore _firestore;
  final auth.FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;
  final _uuid = const Uuid();
  final _realtimeProviderHealthCache =
      <String, _RealtimeProviderHealthCacheEntry>{};

  @override
  bool get isConfigured => true;

  @override
  Stream<AppUser?> authState() {
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      if (firebaseUser == null) {
        return Stream<AppUser?>.value(null);
      }
      return _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .snapshots()
          .map((snapshot) {
            final data = snapshot.data();
            if (data == null) {
              return AppUser(
                uid: firebaseUser.uid,
                displayName: firebaseUser.displayName ?? '',
                handle: '',
                defaultSendMode: SendMode.confirm,
              );
            }
            return AppUser.fromMap(firebaseUser.uid, data);
          });
    });
  }

  @override
  Future<AppUser> signInDemo() {
    throw UnsupportedError('Firebase mode does not support demo sign-in.');
  }

  @override
  Future<String> startPhoneVerification(String phoneNumber) async {
    final completer = Completer<String>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        final result = await _auth.signInWithCredential(credential);
        await _ensureUserDocument(result.user);
        if (!completer.isCompleted) {
          completer.complete('__auto_verified__');
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(error.message ?? error.code));
        }
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
    );
    return completer.future;
  }

  @override
  Future<AppUser> verifySmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (verificationId == '__auto_verified__') {
      return _ensureUserDocument(_auth.currentUser);
    }
    final credential = auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    return _ensureUserDocument(result.user);
  }

  @override
  Future<AppUser> saveProfile({
    required String displayName,
    required String handle,
  }) async {
    final user = _requireUser();
    ensureValidHandle(handle);
    final normalizedHandle = normalizeHandle(handle);

    final userRef = _firestore.collection('users').doc(user.uid);
    final handleRef = _firestore.collection('handles').doc(normalizedHandle);

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final handleSnapshot = await transaction.get(handleRef);
      final currentHandle = userSnapshot.data()?['handle'] as String?;

      if (handleSnapshot.exists && handleSnapshot.data()?['uid'] != user.uid) {
        throw StateError('이미 사용 중인 아이디입니다.');
      }

      if (currentHandle != null &&
          currentHandle.isNotEmpty &&
          currentHandle != normalizedHandle) {
        transaction.delete(_firestore.collection('handles').doc(currentHandle));
      }

      transaction.set(handleRef, {
        'uid': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(userRef, {
        'displayName': displayName.trim(),
        'handle': normalizedHandle,
        'defaultSendMode': SendMode.confirm.name,
        'calendarReminderEnabled':
            userSnapshot.data()?['calendarReminderEnabled'] ?? true,
        'calendarReminderLeadMinutes':
            userSnapshot.data()?['calendarReminderLeadMinutes'] ?? 30,
        'morningBriefingEnabled':
            userSnapshot.data()?['morningBriefingEnabled'] ?? false,
        'morningBriefingMinuteOfDay':
            userSnapshot.data()?['morningBriefingMinuteOfDay'] ?? 480,
        'calendarTimezone':
            userSnapshot.data()?['calendarTimezone'] ?? 'Asia/Seoul',
        'holidayCountryCode':
            userSnapshot.data()?['holidayCountryCode'] ?? 'KR',
        'photoUrl': user.photoURL,
        'phoneHash': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt':
            userSnapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    final snapshot = await userRef.get();
    return AppUser.fromMap(user.uid, snapshot.data() ?? {});
  }

  @override
  Future<void> updateDefaultSendMode(SendMode sendMode) async {
    final user = _requireUser();
    await _firestore.collection('users').doc(user.uid).set({
      'defaultSendMode': sendMode.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateCalendarNotificationSettings({
    required bool calendarReminderEnabled,
    required int calendarReminderLeadMinutes,
    required bool morningBriefingEnabled,
    required int morningBriefingMinuteOfDay,
    String timezone = 'Asia/Seoul',
    String holidayCountryCode = 'KR',
  }) async {
    await _call('updateCalendarNotificationSettings', {
      'calendarReminderEnabled': calendarReminderEnabled,
      'calendarReminderLeadMinutes': calendarReminderLeadMinutes,
      'morningBriefingEnabled': morningBriefingEnabled,
      'morningBriefingMinuteOfDay': morningBriefingMinuteOfDay,
      'calendarTimezone': timezone,
      'holidayCountryCode': holidayCountryCode,
    });
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    return _call('exportMyData', {});
  }

  @override
  Future<Map<String, dynamic>> getOperationalHealth() async {
    return _call('getOperationalHealth', {});
  }

  @override
  Future<void> deleteAccount() async {
    await _call('deleteMyAccount', {});
    await _auth.signOut();
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Stream<List<ChatRoom>> watchRooms(String uid) {
    return _firestore
        .collection('rooms')
        .where('participantIds', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .asyncMap((snapshot) async {
          final rooms = <ChatRoom>[];
          for (final doc in snapshot.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            final member = await doc.reference
                .collection('members')
                .doc(uid)
                .get();
            final memberData = member.data();
            if (memberData != null) {
              if (memberData['leftAt'] != null) {
                continue;
              }
              data.addAll(memberData);
            }
            rooms.add(ChatRoom.fromMap(doc.id, data));
          }
          rooms.sort((a, b) {
            if (a.pinned != b.pinned) {
              return a.pinned ? -1 : 1;
            }
            return b.updatedAt.compareTo(a.updatedAt);
          });
          return rooms;
        });
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(80)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  @override
  Stream<List<CalendarEvent>> watchCalendarEvents(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('calendarEvents')
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CalendarEvent.fromMap(doc.id, doc.data()))
              .where((event) => event.status == 'active')
              .toList();
        });
  }

  @override
  Stream<List<RoomMember>> watchRoomMembers(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .snapshots()
        .map((snapshot) {
          final members = snapshot.docs
              .map((doc) => RoomMember.fromMap(doc.id, doc.data()))
              .where((member) => member.active)
              .toList();
          members.sort((a, b) {
            if (a.role != b.role) {
              return a.role.index.compareTo(b.role.index);
            }
            return a.uid.compareTo(b.uid);
          });
          return members;
        });
  }

  @override
  Stream<List<RoomJoinRequest>> watchRoomJoinRequests(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('joinRequests')
        .where('status', isEqualTo: InviteJoinStatus.pending.name)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RoomJoinRequest.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  @override
  Future<List<AppUser>> listUserDirectory({String query = ''}) async {
    final current = _requireUser();
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      final friendsSnapshot = await _firestore
          .collection('users')
          .doc(current.uid)
          .collection('friends')
          .orderBy('displayName')
          .limit(80)
          .get();
      final friends = friendsSnapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .where((user) => user.hasProfile)
          .toList();
      if (friends.isNotEmpty) {
        friends.sort((a, b) => a.displayName.compareTo(b.displayName));
        return friends;
      }
    }
    final snapshot = await _firestore
        .collection('users')
        .orderBy('displayName')
        .limit(80)
        .get();
    final users = snapshot.docs
        .where((doc) => doc.id != current.uid)
        .map((doc) => AppUser.fromMap(doc.id, doc.data()))
        .where((user) => user.hasProfile)
        .where((user) {
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return user.displayName.toLowerCase().contains(normalizedQuery) ||
              user.handle.toLowerCase().contains(normalizedQuery);
        })
        .toList();
    users.sort((a, b) => a.displayName.compareTo(b.displayName));
    return users;
  }

  @override
  Future<AppUser> addFriendByHandle({required String handle}) async {
    final normalizedHandle = normalizeHandle(handle);
    ensureValidHandle(normalizedHandle);
    final result = await _call('addFriendByHandle', {
      'handle': normalizedHandle,
    });
    final friend = result['friend'];
    if (friend is Map) {
      return AppUser.fromMap(
        (friend['uid'] as String?) ?? '',
        Map<String, dynamic>.from(friend),
      );
    }
    final users = await listUserDirectory(query: normalizedHandle);
    return users.firstWhere((user) => user.handle == normalizedHandle);
  }

  @override
  Future<ChatRoom> createRoom({
    required List<String> participantHandles,
    required RoomType type,
    String? title,
  }) async {
    final normalizedHandles = normalizeAndValidateHandles(participantHandles);
    final result = await _call('createRoom', {
      'participantHandles': normalizedHandles,
      'type': type.name,
      'title': title,
    });
    final roomId = result['roomId'] as String;
    final snapshot = await _firestore.collection('rooms').doc(roomId).get();
    return ChatRoom.fromMap(roomId, snapshot.data() ?? {});
  }

  @override
  Future<RoomInvite> createRoomInvite({
    required String roomId,
    bool approvalRequired = false,
  }) async {
    final result = await _call('createRoomInvite', {
      'roomId': roomId,
      'approvalRequired': approvalRequired,
    });
    return RoomInvite.fromMap((result['inviteId'] as String?) ?? '', result);
  }

  @override
  Future<void> revokeRoomInvite({
    required String roomId,
    required String inviteId,
  }) async {
    await _call('revokeRoomInvite', {'roomId': roomId, 'inviteId': inviteId});
  }

  @override
  Future<void> setInviteApprovalRequired({
    required String roomId,
    required bool approvalRequired,
  }) async {
    await _call('setInviteApprovalRequired', {
      'roomId': roomId,
      'approvalRequired': approvalRequired,
    });
  }

  @override
  Future<void> setRoomAudioRetention({
    required String roomId,
    required int days,
    required String preset,
  }) async {
    await _call('setRoomAudioRetention', {
      'roomId': roomId,
      'days': days,
      'preset': preset,
    });
  }

  @override
  Future<InviteJoinResult> joinRoomByInvite({required String token}) async {
    final result = await _call('joinRoomByInvite', {
      'token': _inviteTokenFromInput(token),
    });
    return InviteJoinResult.fromMap(result);
  }

  @override
  Future<void> approveRoomJoinRequest({
    required String roomId,
    required String memberUid,
  }) async {
    await _call('approveRoomJoinRequest', {
      'roomId': roomId,
      'memberUid': memberUid,
    });
  }

  @override
  Future<void> rejectRoomJoinRequest({
    required String roomId,
    required String memberUid,
  }) async {
    await _call('rejectRoomJoinRequest', {
      'roomId': roomId,
      'memberUid': memberUid,
    });
  }

  @override
  Future<void> updateRoomMemberRole({
    required String roomId,
    required String memberUid,
    required RoomMemberRole role,
  }) async {
    await _call('updateRoomMemberRole', {
      'roomId': roomId,
      'memberUid': memberUid,
      'role': role.name,
    });
  }

  @override
  Future<void> removeRoomMember({
    required String roomId,
    required String memberUid,
  }) async {
    await _call('removeRoomMember', {'roomId': roomId, 'memberUid': memberUid});
  }

  @override
  Future<void> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToMessageId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 4000) {
      throw StateError('Text message length is invalid.');
    }
    try {
      await _sendTextMessageDirect(
        roomId: roomId,
        text: trimmed,
        replyToMessageId: replyToMessageId,
      );
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' &&
          error.code != 'failed-precondition') {
        rethrow;
      }
      final data = <String, dynamic>{'roomId': roomId, 'text': trimmed};
      if (replyToMessageId != null) {
        data['replyToMessageId'] = replyToMessageId;
      }
      await _call('sendTextMessage', data);
    }
  }

  @override
  Future<void> scheduleTextMessage({
    required String roomId,
    required String text,
    required DateTime scheduledAt,
    String? replyToMessageId,
  }) async {
    final data = <String, dynamic>{
      'roomId': roomId,
      'text': text.trim(),
      'scheduledAt': scheduledAt.toIso8601String(),
    };
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('scheduleTextMessage', data);
  }

  @override
  Future<void> sendScheduledMessageNow({
    required String roomId,
    required String messageId,
  }) async {
    await _call('sendScheduledMessageNow', {
      'roomId': roomId,
      'messageId': messageId,
    });
  }

  @override
  Future<void> sendAttachmentMessage({
    required String roomId,
    required MessageKind kind,
    required MessageAttachment attachment,
    AttachmentUploadPayload? upload,
    String caption = '',
    String? replyToMessageId,
  }) async {
    final uploadedAttachment = await _uploadAttachmentIfNeeded(
      roomId: roomId,
      kind: kind,
      attachment: attachment,
      upload: upload,
    );
    final data = <String, dynamic>{
      'roomId': roomId,
      'kind': kind.name,
      'attachment': uploadedAttachment.toMap(),
      'caption': caption.trim(),
    };
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('sendAttachmentMessage', data);
  }

  Future<void> _sendTextMessageDirect({
    required String roomId,
    required String text,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc();
    final replyTo = await _replyToMap(roomRef, replyToMessageId);
    await messageRef.set({
      'senderId': user.uid,
      'kind': MessageKind.text.name,
      'text': text,
      'transcript': '',
      'audioPath': null,
      'durationMs': 0,
      'sttStatus': SttStatus.none.name,
      'sendMode': SendMode.confirm.name,
      'replyTo': replyTo,
      'deliveryStatus': MessageDeliveryStatus.sent.name,
      'clientCreated': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> _replyToMap(
    DocumentReference<Map<String, dynamic>> roomRef,
    String? replyToMessageId,
  ) async {
    final id = replyToMessageId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    final snapshot = await roomRef.collection('messages').doc(id).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['deletedAt'] != null) {
      return null;
    }
    final message = ChatMessage.fromMap(snapshot.id, data);
    final preview = message.displayText.trim();
    return {
      'messageId': snapshot.id,
      'senderId': message.senderId,
      'preview': preview.length > 120 ? preview.substring(0, 120) : preview,
    };
  }

  @override
  Future<void> createCalendarProposal({
    required String roomId,
    required String title,
    required String details,
    required List<CalendarProposalCandidate> candidates,
    String timezone = 'Asia/Seoul',
    String source = 'manual',
    String transcript = '',
    String? replyToMessageId,
  }) async {
    final data = <String, dynamic>{
      'roomId': roomId,
      'title': title.trim(),
      'details': details.trim(),
      'timezone': timezone,
      'source': source,
      'transcript': transcript.trim(),
      'candidates': candidates.map((candidate) => candidate.toMap()).toList(),
    };
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('createCalendarProposal', data);
  }

  @override
  Future<void> voteCalendarProposal({
    required String roomId,
    required String proposalId,
    required List<String> candidateIds,
  }) async {
    await _call('voteCalendarProposal', {
      'roomId': roomId,
      'proposalId': proposalId,
      'candidateIds': candidateIds,
    });
  }

  @override
  Future<void> finalizeCalendarProposal({
    required String roomId,
    required String proposalId,
    required String candidateId,
  }) async {
    await _call('finalizeCalendarProposal', {
      'roomId': roomId,
      'proposalId': proposalId,
      'candidateId': candidateId,
    });
  }

  @override
  Future<void> addFinalizedProposalToMyCalendar({
    required String roomId,
    required String proposalId,
  }) async {
    await _call('addFinalizedProposalToMyCalendar', {
      'roomId': roomId,
      'proposalId': proposalId,
    });
  }

  @override
  Future<void> cancelCalendarProposal({
    required String roomId,
    required String proposalId,
  }) async {
    await _call('cancelCalendarProposal', {
      'roomId': roomId,
      'proposalId': proposalId,
    });
  }

  Future<MessageAttachment> _uploadAttachmentIfNeeded({
    required String roomId,
    required MessageKind kind,
    required MessageAttachment attachment,
    required AttachmentUploadPayload? upload,
  }) async {
    if (upload == null ||
        (kind != MessageKind.image && kind != MessageKind.file)) {
      return attachment;
    }
    final user = _requireUser();
    final attachmentId = _uuid.v4();
    final safeName = _safeStorageFileName(upload.fileName);
    final storagePath =
        'attachments/$roomId/${user.uid}/$attachmentId-$safeName';
    final ref = _storage.ref(storagePath);
    await ref.putData(
      upload.bytes,
      SettableMetadata(
        contentType: upload.mimeType,
        customMetadata: {
          'roomId': roomId,
          'ownerId': user.uid,
          'kind': kind.name,
          'fileName': upload.fileName,
        },
      ),
    );
    final url = await ref.getDownloadURL();
    return attachment.copyWith(
      title: upload.fileName,
      url: url,
      storagePath: storagePath,
      mimeType: upload.mimeType,
      sizeBytes: upload.sizeBytes,
    );
  }

  @override
  Future<TranscriptionDraft> createTranscriptionDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  }) async {
    final user = _requireUser();
    final draftId = _uuid.v4();
    final extension = _audioExtensionForPath(audioFilePath);
    final storagePath = 'voice_drafts/${user.uid}/$draftId$extension';
    await uploadAudioFile(
      ref: _storage.ref(storagePath),
      audioFilePath: audioFilePath,
      metadata: SettableMetadata(
        contentType: _audioContentTypeForExtension(extension),
        customMetadata: {
          'ownerId': user.uid,
          'durationMs': '$durationMs',
          'language': language,
        },
      ),
    );

    final data = <String, dynamic>{
      'draftId': draftId,
      'audioPath': storagePath,
      'durationMs': durationMs,
      'language': language,
    };
    final manualTranscript = transcriptOverride?.trim();
    if (manualTranscript != null && manualTranscript.isNotEmpty) {
      data['transcriptOverride'] = manualTranscript;
    }
    final result = await _call('createTranscriptionDraft', data);
    return TranscriptionDraft.fromMap(draftId, result);
  }

  @override
  Future<CalendarIntentDraft> createCalendarIntentDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  }) async {
    final user = _requireUser();
    final draftId = _uuid.v4();
    final extension = _audioExtensionForPath(audioFilePath);
    final storagePath = 'voice_drafts/${user.uid}/calendar_$draftId$extension';
    await uploadAudioFile(
      ref: _storage.ref(storagePath),
      audioFilePath: audioFilePath,
      metadata: SettableMetadata(
        contentType: _audioContentTypeForExtension(extension),
        customMetadata: {
          'ownerId': user.uid,
          'durationMs': '$durationMs',
          'language': language,
          'purpose': 'calendar',
        },
      ),
    );

    final data = <String, dynamic>{
      'draftId': draftId,
      'audioPath': storagePath,
      'durationMs': durationMs,
      'language': language,
    };
    final manualTranscript = transcriptOverride?.trim();
    if (manualTranscript != null && manualTranscript.isNotEmpty) {
      data['transcriptOverride'] = manualTranscript;
    }
    final result = await _call('createCalendarIntentDraft', data);
    return CalendarIntentDraft.fromMap(result);
  }

  @override
  Future<CalendarEvent> createCalendarEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String timezone = 'Asia/Seoul',
    String source = 'manual',
    String details = '',
    String transcript = '',
  }) async {
    final result = await _call('createCalendarEvent', {
      'title': title.trim(),
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
      'timezone': timezone,
      'source': source,
      'details': details.trim(),
      'transcript': transcript.trim(),
    });
    return _calendarEventFromCallable(result);
  }

  @override
  Future<CalendarEvent> updateCalendarEvent({
    required String eventId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String timezone = 'Asia/Seoul',
    String details = '',
  }) async {
    final result = await _call('updateCalendarEvent', {
      'eventId': eventId,
      'title': title.trim(),
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
      'timezone': timezone,
      'details': details.trim(),
    });
    return _calendarEventFromCallable(result);
  }

  @override
  Future<void> deleteCalendarEvent({required String eventId}) async {
    await _call('deleteCalendarEvent', {'eventId': eventId});
  }

  @override
  Future<void> sendVoiceMessage({
    required String roomId,
    required String draftId,
    required String finalText,
    required SendMode sendMode,
    String? replyToMessageId,
  }) async {
    final data = <String, dynamic>{
      'roomId': roomId,
      'draftId': draftId,
      'finalText': finalText.trim(),
      'sendMode': sendMode.name,
    };
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('sendVoiceMessage', data);
  }

  @override
  Future<String> sendInstantVoiceMessage({
    required String roomId,
    required String audioFilePath,
    required int durationMs,
    required SendMode sendMode,
    String language = 'ko-KR',
    String? transcriptOverride,
    String? replyToMessageId,
    String? clientMessageId,
    bool pendingAlreadyCreated = false,
    bool forceServerSttCorrection = false,
    bool skipInlineStt = false,
  }) async {
    final user = _requireUser();
    final messageId = clientMessageId?.trim().isNotEmpty == true
        ? clientMessageId!.trim()
        : _uuid.v4();
    final extension = _audioExtensionForPath(audioFilePath);
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc(messageId);
    final manualTranscript = _voiceTranscriptValue(transcriptOverride);
    if (pendingAlreadyCreated) {
      unawaited(
        _finalizePendingVoiceMessage(
          ownerUid: user.uid,
          roomId: roomId,
          messageId: messageId,
          audioFilePath: audioFilePath,
          extension: extension,
          durationMs: durationMs,
          language: language,
          transcriptOverride: manualTranscript,
          forceServerSttCorrection: forceServerSttCorrection,
          skipInlineStt: skipInlineStt,
        ),
      );
    } else {
      unawaited(
        _createAndFinalizePendingVoiceMessage(
          ownerUid: user.uid,
          roomId: roomId,
          roomRef: roomRef,
          messageRef: messageRef,
          messageId: messageId,
          audioFilePath: audioFilePath,
          extension: extension,
          durationMs: durationMs,
          sendMode: sendMode,
          language: language,
          transcriptOverride: manualTranscript,
          replyToMessageId: replyToMessageId,
          forceServerSttCorrection: forceServerSttCorrection,
          skipInlineStt: skipInlineStt,
        ),
      );
    }
    return messageId;
  }

  @override
  Future<void> createPendingVoiceMessage({
    required String roomId,
    required String messageId,
    required int durationMs,
    required SendMode sendMode,
    String language = 'ko-KR',
    String? transcriptOverride,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc(messageId);
    await _createPendingVoiceMessage(
      ownerUid: user.uid,
      roomId: roomId,
      roomRef: roomRef,
      messageRef: messageRef,
      messageId: messageId,
      durationMs: durationMs,
      sendMode: sendMode,
      language: language,
      transcriptOverride: _voiceTranscriptValue(transcriptOverride),
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<DeepgramStreamingToken?> createDeepgramStreamingToken({
    String language = 'ko-KR',
    String? provider,
  }) async {
    final normalizedProvider = _normalizeRealtimeProvider(provider);
    final relayUrl = _deepgramRelayUrl(language, provider: normalizedProvider);
    final tokenProvider = _effectiveRealtimeProvider(normalizedProvider);
    if (relayUrl != null) {
      try {
        if (tokenProvider == 'openai' &&
            !await _isRealtimeRelayProviderAvailable('openai')) {
          debugPrint('Realtime relay provider unavailable by health: openai');
          return null;
        }
        final idToken = await _requireUser().getIdToken();
        if (idToken == null || idToken.trim().isEmpty) {
          return null;
        }
        return DeepgramStreamingToken(
          accessToken: idToken,
          url: relayUrl,
          expiresIn: 55 * 60,
          language: language,
          model: tokenProvider == 'openai' ? 'gpt-realtime-whisper' : 'nova-3',
          sampleRate: 16000,
          channels: 1,
          encoding: 'linear16',
        );
      } catch (error) {
        debugPrint('Deepgram relay token unavailable: $error');
        return null;
      }
    }
    try {
      final result = await _call('createDeepgramStreamingToken', {
        'language': language,
      });
      final accessToken = result['accessToken'] as String?;
      final url = result['url'] as String?;
      if (accessToken == null ||
          accessToken.trim().isEmpty ||
          url == null ||
          url.trim().isEmpty) {
        return null;
      }
      return DeepgramStreamingToken(
        accessToken: accessToken,
        url: url,
        expiresIn: (result['expiresIn'] as num?)?.toInt() ?? 30,
        language: (result['language'] as String?) ?? language,
        model: (result['model'] as String?) ?? 'nova-3',
        sampleRate: (result['sampleRate'] as num?)?.toInt() ?? 16000,
        channels: (result['channels'] as num?)?.toInt() ?? 1,
        encoding: (result['encoding'] as String?) ?? 'linear16',
      );
    } catch (error) {
      debugPrint('Deepgram streaming token unavailable: $error');
      return null;
    }
  }

  @override
  Future<VoiceInlineSttResult?> transcribeClientVoiceMessageInline({
    required String roomId,
    required String messageId,
    required Uint8List audioBytes,
    required String contentType,
    required int durationMs,
    String language = 'ko-KR',
  }) {
    return _transcribePendingVoiceMessageInlineBytes(
      roomId: roomId,
      messageId: messageId,
      audioBytes: audioBytes,
      contentType: contentType,
      durationMs: durationMs,
      language: language,
    );
  }

  @override
  Future<VoiceInlineSttResult?> transcribeVoiceAudioDraft({
    required String roomId,
    required Uint8List audioBytes,
    required String contentType,
    required int durationMs,
    String language = 'ko-KR',
  }) async {
    if (audioBytes.isEmpty) {
      return null;
    }
    final startedAt = DateTime.now();
    final result = await _call('transcribeVoiceAudioDraft', {
      'roomId': roomId,
      'audioBase64': base64Encode(audioBytes),
      'contentType': contentType,
      'durationMs': durationMs,
      'language': language,
    }, timeout: const Duration(seconds: 180));
    final transcript = _voiceTranscriptValue(result['transcript'] as String?);
    final transcriptLength = result['transcriptLength'] is num
        ? (result['transcriptLength'] as num).toInt()
        : transcript.length;
    debugPrint(
      'voice_speculative_stt_completed '
      'roomId=$roomId '
      'bytes=${audioBytes.length} '
      'clientMs=${DateTime.now().difference(startedAt).inMilliseconds} '
      'serverTotalMs=${result['totalMs'] ?? 'unknown'} '
      'serverSttMs=${result['sttMs'] ?? 'unknown'} '
      'transcriptLength=$transcriptLength '
      'cacheHit=${result['cacheHit'] ?? 'unknown'}',
    );
    if (transcriptLength <= 0 && transcript.isEmpty) {
      return null;
    }
    return VoiceInlineSttResult(
      messageId: '${result['messageId'] ?? 'draft'}',
      sttStatus: '${result['sttStatus'] ?? 'completed'}',
      transcript: transcript,
      transcriptLength: transcriptLength,
      totalMs: result['totalMs'] is num
          ? (result['totalMs'] as num).toInt()
          : DateTime.now().difference(startedAt).inMilliseconds,
      sttMs: result['sttMs'] is num ? (result['sttMs'] as num).toInt() : -1,
      cacheHit: result['cacheHit'] == true,
    );
  }

  String? _normalizeRealtimeProvider(String? provider) {
    final normalized = (provider ?? '').trim().toLowerCase();
    if (normalized == 'openai' || normalized == 'deepgram') {
      return normalized;
    }
    return null;
  }

  String _effectiveRealtimeProvider(String? provider) {
    const configuredProvider = String.fromEnvironment(
      'VERBAL_REALTIME_STT_PROVIDER',
      defaultValue: 'auto',
    );
    final configured = configuredProvider.trim().toLowerCase();
    return provider == 'openai'
        ? 'openai'
        : provider == 'deepgram'
        ? 'deepgram'
        : configured == 'openai'
        ? 'openai'
        : 'deepgram';
  }

  Future<bool> _isRealtimeRelayProviderAvailable(String provider) async {
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider != 'openai') {
      return true;
    }
    final healthUrl = _realtimeRelayHealthUrl();
    if (healthUrl == null) {
      return true;
    }
    final cacheKey = '$healthUrl::$normalizedProvider';
    final now = DateTime.now();
    final cached = _realtimeProviderHealthCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.available;
    }
    final available = await realtimeRelayProviderAvailable(
      relayRootUrl: healthUrl,
      provider: normalizedProvider,
      timeout: const Duration(milliseconds: 700),
    );
    if (available == null) {
      return true;
    }
    _realtimeProviderHealthCache[cacheKey] = _RealtimeProviderHealthCacheEntry(
      available: available,
      expiresAt: now.add(
        available ? const Duration(seconds: 20) : const Duration(minutes: 2),
      ),
    );
    return available;
  }

  String? _realtimeRelayHealthUrl() {
    const raw = String.fromEnvironment(
      'VERBAL_DEEPGRAM_RELAY_URL',
      defaultValue: 'https://verbal-deepgram-relay-uhnknahebq-du.a.run.app',
    );
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) {
      return null;
    }
    final scheme = switch (parsed.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      'https' || 'http' => parsed.scheme,
      _ => 'https',
    };
    return parsed.replace(scheme: scheme, path: '/', query: '').toString();
  }

  String? _deepgramRelayUrl(String language, {required String? provider}) {
    const raw = String.fromEnvironment(
      'VERBAL_DEEPGRAM_RELAY_URL',
      defaultValue: 'https://verbal-deepgram-relay-uhnknahebq-du.a.run.app',
    );
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) {
      return null;
    }
    final scheme = switch (parsed.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' || 'ws' => parsed.scheme,
      _ => 'wss',
    };
    final effectiveProvider = _effectiveRealtimeProvider(provider);
    final path = parsed.path.trim().isEmpty
        ? (effectiveProvider == 'openai' ? '/openai-stt' : '/stt')
        : parsed.path;
    final openAiMode =
        effectiveProvider == 'openai' || path.toLowerCase().contains('openai');
    final query = Map<String, String>.from(parsed.queryParameters);
    const streamingModel = String.fromEnvironment(
      'VERBAL_DEEPGRAM_STREAMING_MODEL',
      defaultValue: 'nova-3',
    );
    const openAiStreamingModel = String.fromEnvironment(
      'VERBAL_OPENAI_STREAMING_MODEL',
      defaultValue: 'gpt-realtime-whisper',
    );
    const endpointingMs = String.fromEnvironment(
      'VERBAL_DEEPGRAM_ENDPOINTING_MS',
      defaultValue: '50',
    );
    const noDelay = String.fromEnvironment(
      'VERBAL_DEEPGRAM_NO_DELAY',
      defaultValue: 'true',
    );
    const smartFormat = String.fromEnvironment(
      'VERBAL_DEEPGRAM_STREAMING_SMART_FORMAT',
      defaultValue: 'false',
    );
    const punctuate = String.fromEnvironment(
      'VERBAL_DEEPGRAM_STREAMING_PUNCTUATE',
      defaultValue: 'false',
    );
    const numerals = String.fromEnvironment(
      'VERBAL_DEEPGRAM_STREAMING_NUMERALS',
      defaultValue: 'false',
    );
    query.putIfAbsent('language', () => language);
    query.putIfAbsent('model', () {
      return openAiMode ? openAiStreamingModel : streamingModel;
    });
    if (openAiMode) {
      query.putIfAbsent('provider', () => 'openai');
      query.putIfAbsent('delay', () => 'minimal');
      query.putIfAbsent('commit_ms', () => '250');
    } else {
      query.putIfAbsent('endpointing', () => endpointingMs);
      if (noDelay.trim().isNotEmpty) {
        query.putIfAbsent('no_delay', () => noDelay);
      }
      query.putIfAbsent('smart_format', () => smartFormat);
      query.putIfAbsent('punctuate', () => punctuate);
      query.putIfAbsent('numerals', () => numerals);
    }
    return parsed
        .replace(scheme: scheme, path: path, queryParameters: query)
        .toString();
  }

  Future<void> _createAndFinalizePendingVoiceMessage({
    required String ownerUid,
    required String roomId,
    required DocumentReference<Map<String, dynamic>> roomRef,
    required DocumentReference<Map<String, dynamic>> messageRef,
    required String messageId,
    required String audioFilePath,
    required String extension,
    required int durationMs,
    required SendMode sendMode,
    required String language,
    String? transcriptOverride,
    String? replyToMessageId,
    bool forceServerSttCorrection = false,
    bool skipInlineStt = false,
  }) async {
    try {
      await _createPendingVoiceMessage(
        ownerUid: ownerUid,
        roomId: roomId,
        roomRef: roomRef,
        messageRef: messageRef,
        messageId: messageId,
        durationMs: durationMs,
        sendMode: sendMode,
        language: language,
        transcriptOverride: transcriptOverride,
        replyToMessageId: replyToMessageId,
      );

      await _finalizePendingVoiceMessage(
        ownerUid: ownerUid,
        roomId: roomId,
        messageId: messageId,
        audioFilePath: audioFilePath,
        extension: extension,
        durationMs: durationMs,
        language: language,
        transcriptOverride: _voiceTranscriptValue(transcriptOverride),
        forceServerSttCorrection: forceServerSttCorrection,
        skipInlineStt: skipInlineStt,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to create pending voice message: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _createPendingVoiceMessage({
    required String ownerUid,
    required String roomId,
    required DocumentReference<Map<String, dynamic>> roomRef,
    required DocumentReference<Map<String, dynamic>> messageRef,
    required String messageId,
    required int durationMs,
    required SendMode sendMode,
    required String language,
    String? transcriptOverride,
    String? replyToMessageId,
  }) async {
    final replyTo = await _replyToMap(roomRef, replyToMessageId);
    final pendingText = _voiceTranscriptValue(transcriptOverride);
    final pendingWriteStartedAt = DateTime.now();
    await messageRef.set({
      'senderId': ownerUid,
      'kind': MessageKind.voice.name,
      'text': pendingText,
      'transcript': pendingText,
      'audioPath': null,
      'durationMs': durationMs,
      'sttStatus': pendingText.isNotEmpty
          ? SttStatus.completed.name
          : SttStatus.processing.name,
      'sendMode': sendMode.name,
      'language': language,
      'replyTo': replyTo,
      'deliveryStatus': MessageDeliveryStatus.sending.name,
      'clientCreated': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint(
      'voice_send_pending_created messageId=$messageId '
      'roomId=$roomId '
      'recordStopMs=$durationMs '
      'pendingWriteMs=${DateTime.now().difference(pendingWriteStartedAt).inMilliseconds} '
      'transcriptAtCreate=${pendingText.isNotEmpty}',
    );
  }

  Future<void> _finalizePendingVoiceMessage({
    required String ownerUid,
    required String roomId,
    required String messageId,
    required String audioFilePath,
    required String extension,
    required int durationMs,
    required String language,
    String? transcriptOverride,
    bool forceServerSttCorrection = false,
    bool skipInlineStt = false,
  }) async {
    final storagePath = 'voice_drafts/$ownerUid/$messageId$extension';
    final finalizeStartedAt = DateTime.now();
    try {
      final manualTranscript = transcriptOverride?.trim();
      final hasManualTranscript =
          manualTranscript != null && manualTranscript.isNotEmpty;
      final shouldRunInlineStt =
          !skipInlineStt && (!hasManualTranscript || forceServerSttCorrection);
      const shouldDeferStorageStt = true;
      Future<VoiceInlineSttResult?>? inlineSttFuture;
      if (shouldRunInlineStt) {
        inlineSttFuture = _transcribePendingVoiceMessageInline(
          roomId: roomId,
          messageId: messageId,
          audioFilePath: audioFilePath,
          extension: extension,
          durationMs: durationMs,
          language: language,
        );
        unawaited(inlineSttFuture);
      }
      final uploadStartedAt = DateTime.now();
      await uploadAudioFile(
        ref: _storage.ref(storagePath),
        audioFilePath: audioFilePath,
        metadata: SettableMetadata(
          contentType: _audioContentTypeForExtension(extension),
          customMetadata: {
            'ownerId': ownerUid,
            'durationMs': '$durationMs',
            'language': language,
          },
        ),
      );
      final uploadMs = DateTime.now()
          .difference(uploadStartedAt)
          .inMilliseconds;
      final data = <String, dynamic>{
        'roomId': roomId,
        'messageId': messageId,
        'audioPath': storagePath,
        'durationMs': durationMs,
        'language': language,
        'clientUploadMs': uploadMs,
        // Finalize should only make the audio playable and deliverable.
        // Inline STT and the server update trigger attach transcript text
        // without blocking the send path.
        'deferStt': shouldDeferStorageStt,
      };
      if (manualTranscript != null && manualTranscript.isNotEmpty) {
        data['transcriptOverride'] = manualTranscript;
      }
      if (forceServerSttCorrection) {
        data['forceServerSttCorrection'] = true;
      }
      final finalizeCallStartedAt = DateTime.now();
      final result = await _call('finalizeClientVoiceMessage', data);
      final finalizeCallMs = DateTime.now()
          .difference(finalizeCallStartedAt)
          .inMilliseconds;
      debugPrint(
        'voice_send_finalize_completed messageId=$messageId '
        'uploadMs=$uploadMs '
        'finalizeCallMs=$finalizeCallMs '
        'totalFinalizeMs=${DateTime.now().difference(finalizeStartedAt).inMilliseconds} '
        'sttStatus=${result['sttStatus'] ?? 'unknown'} '
        'transcriptOverride=$hasManualTranscript '
        'inlineStt=$shouldRunInlineStt '
        'deferStt=$shouldDeferStorageStt '
        'skipInlineStt=$skipInlineStt '
        'forceServerSttCorrection=$forceServerSttCorrection',
      );
      final finalizedSttStatus = '${result['sttStatus'] ?? ''}';
      if (!hasManualTranscript && finalizedSttStatus != 'completed') {
        unawaited(
          _ensurePendingVoiceTranscriptAfterFinalize(
            roomId: roomId,
            messageId: messageId,
            inlineSttFuture: inlineSttFuture,
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to finalize pending voice message: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_shouldLeaveVoiceFinalizePending(error)) {
        debugPrint(
          'voice_send_finalize_deferred messageId=$messageId reason=$error',
        );
        return;
      }
      await _markPendingVoiceMessageFailed(
        roomId: roomId,
        messageId: messageId,
        reason: error.toString(),
      );
    }
  }

  Future<VoiceInlineSttResult?> _transcribePendingVoiceMessageInline({
    required String roomId,
    required String messageId,
    required String audioFilePath,
    required String extension,
    required int durationMs,
    required String language,
  }) async {
    const maxInlineBytes = int.fromEnvironment(
      'VERBAL_INLINE_STT_MAX_BYTES',
      defaultValue: 2 * 1024 * 1024,
    );
    final inlineStartedAt = DateTime.now();
    final Uint8List? bytes;
    try {
      bytes = await readLocalAudioBytesForInlineStt(
        audioFilePath,
        maxBytes: maxInlineBytes,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Inline voice STT audio read failed messageId=$messageId: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return _transcribePendingVoiceMessageInlineBytes(
      roomId: roomId,
      messageId: messageId,
      audioBytes: bytes,
      contentType: _audioContentTypeForExtension(extension),
      durationMs: durationMs,
      language: language,
      inlineStartedAt: inlineStartedAt,
    );
  }

  Future<VoiceInlineSttResult?> _transcribePendingVoiceMessageInlineBytes({
    required String roomId,
    required String messageId,
    required Uint8List audioBytes,
    required String contentType,
    required int durationMs,
    required String language,
    DateTime? inlineStartedAt,
  }) async {
    final startedAt = inlineStartedAt ?? DateTime.now();
    if (audioBytes.isEmpty) {
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final attemptStartedAt = DateTime.now();
        final result = await _call(
          'transcribeClientVoiceMessageInline',
          {
            'roomId': roomId,
            'messageId': messageId,
            'audioBase64': base64Encode(audioBytes),
            'contentType': contentType,
            'durationMs': durationMs,
            'language': language,
          },
          timeout: const Duration(seconds: 180),
        );
        final transcriptLength = result['transcriptLength'] is num
            ? (result['transcriptLength'] as num).toInt()
            : 0;
        debugPrint(
          'voice_send_inline_stt_completed messageId=$messageId '
          'attempt=$attempt '
          'bytes=${audioBytes.length} '
          'attemptMs=${DateTime.now().difference(attemptStartedAt).inMilliseconds} '
          'totalMs=${DateTime.now().difference(startedAt).inMilliseconds} '
          'serverTotalMs=${result['totalMs'] ?? 'unknown'} '
          'serverSttMs=${result['sttMs'] ?? 'unknown'} '
          'transcriptLength=$transcriptLength '
          'cacheHit=${result['cacheHit'] ?? 'unknown'}',
        );
        final transcript = _voiceTranscriptValue(
          result['transcript'] as String?,
        );
        final sttStatus = '${result['sttStatus'] ?? ''}';
        if (transcriptLength > 0 || sttStatus == 'completed') {
          return VoiceInlineSttResult(
            messageId: '${result['messageId'] ?? messageId}',
            sttStatus: sttStatus,
            transcript: transcript,
            transcriptLength: transcriptLength,
            totalMs: result['totalMs'] is num
                ? (result['totalMs'] as num).toInt()
                : DateTime.now().difference(startedAt).inMilliseconds,
            sttMs: result['sttMs'] is num
                ? (result['sttMs'] as num).toInt()
                : -1,
            cacheHit: result['cacheHit'] == true,
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Inline voice STT failed messageId=$messageId attempt=$attempt: $error',
        );
        if (attempt == 1) {
          debugPrintStack(stackTrace: stackTrace);
          return null;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 900 + attempt * 600));
    }
    return null;
  }

  Future<void> _ensurePendingVoiceTranscriptAfterFinalize({
    required String roomId,
    required String messageId,
    Future<VoiceInlineSttResult?>? inlineSttFuture,
  }) async {
    unawaited(
      inlineSttFuture?.catchError((Object error) {
        debugPrint(
          'voice_send_inline_stt_observe_failed messageId=$messageId error=$error',
        );
        return null;
      }),
    );
    try {
      final startedAt = DateTime.now();
      final result = await _call(
        'recoverClientVoiceMessageTranscript',
        {'roomId': roomId, 'messageId': messageId},
        timeout: const Duration(seconds: 180),
      );
      debugPrint(
        'voice_send_storage_stt_recovery_completed messageId=$messageId '
        'totalMs=${DateTime.now().difference(startedAt).inMilliseconds} '
        'sttStatus=${result['sttStatus'] ?? 'unknown'} '
        'transcriptLength=${result['transcriptLength'] ?? 'unknown'}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'voice_send_storage_stt_recovery_failed messageId=$messageId error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _shouldLeaveVoiceFinalizePending(Object error) {
    if (error is! FirebaseFunctionsException) {
      return false;
    }
    final code = error.code.toLowerCase();
    return code == 'deadline-exceeded' ||
        code == 'unavailable' ||
        code == 'aborted' ||
        code == 'internal';
  }

  Future<void> _markPendingVoiceMessageFailed({
    required String roomId,
    required String messageId,
    required String reason,
  }) async {
    try {
      await _call('markClientVoiceMessageFailed', {
        'roomId': roomId,
        'messageId': messageId,
        'reason': reason,
      });
    } catch (error) {
      debugPrint('Failed to mark pending voice message failed: $error');
    }
  }

  @override
  Future<void> updateClientVoiceTranscript({
    required String roomId,
    required String messageId,
    required String transcript,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) {
      return;
    }
    await _call('updateClientVoiceTranscript', {
      'roomId': roomId,
      'messageId': messageId,
      'transcript': text,
    });
  }

  @override
  Future<void> recoverClientVoiceMessageTranscript({
    required String roomId,
    required String messageId,
  }) async {
    await _call('recoverClientVoiceMessageTranscript', {
      'roomId': roomId,
      'messageId': messageId,
    }, timeout: const Duration(seconds: 180));
  }

  @override
  Future<void> editMessage({
    required String roomId,
    required String messageId,
    required String text,
  }) async {
    await _call('editMessage', {
      'roomId': roomId,
      'messageId': messageId,
      'text': text.trim(),
    });
  }

  @override
  Future<void> deleteMessage({
    required String roomId,
    required String messageId,
  }) async {
    await _call('deleteMessage', {'roomId': roomId, 'messageId': messageId});
  }

  @override
  Future<void> reportMessage({
    required String roomId,
    required String messageId,
    required String reason,
  }) async {
    await _call('reportMessage', {
      'roomId': roomId,
      'messageId': messageId,
      'reason': reason,
    });
  }

  @override
  Future<void> reportRoom({
    required String roomId,
    required String reason,
  }) async {
    await _call('reportRoom', {'roomId': roomId, 'reason': reason});
  }

  @override
  Future<void> blockUser({required String blockedUid, String? reason}) async {
    final data = <String, dynamic>{'blockedUid': blockedUid};
    if (reason != null && reason.trim().isNotEmpty) {
      data['reason'] = reason.trim();
    }
    await _call('blockUser', data);
  }

  @override
  Future<void> leaveRoom({required String roomId}) async {
    await _call('leaveRoom', {'roomId': roomId});
  }

  @override
  Future<void> addReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    await _call('addReaction', {
      'roomId': roomId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  @override
  Future<void> removeReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    await _call('removeReaction', {
      'roomId': roomId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  @override
  Future<MessageTranslation> translateMessage({
    required String roomId,
    required String messageId,
    String targetLanguage = 'en',
  }) async {
    final result = await _call('translateMessage', {
      'roomId': roomId,
      'messageId': messageId,
      'targetLanguage': targetLanguage,
    });
    return MessageTranslation.fromMap(
      (result['targetLanguage'] as String?) ?? targetLanguage,
      result,
    );
  }

  @override
  Future<void> pinMessage({
    required String roomId,
    required String messageId,
  }) async {
    await _call('pinMessage', {'roomId': roomId, 'messageId': messageId});
  }

  @override
  Future<void> unpinMessage({
    required String roomId,
    required String messageId,
  }) async {
    await _call('unpinMessage', {'roomId': roomId, 'messageId': messageId});
  }

  @override
  Future<void> markRoomRead({
    required String roomId,
    String? lastMessageId,
  }) async {
    final data = <String, dynamic>{'roomId': roomId};
    if (lastMessageId != null) {
      data['lastMessageId'] = lastMessageId;
    }
    await _call('markRoomRead', data);
  }

  @override
  Future<void> setRoomPinned({
    required String roomId,
    required bool pinned,
  }) async {
    await _call('setRoomPinned', {'roomId': roomId, 'pinned': pinned});
  }

  @override
  Future<void> setRoomArchived({
    required String roomId,
    required bool archived,
  }) async {
    await _call('setRoomArchived', {'roomId': roomId, 'archived': archived});
  }

  @override
  Future<void> setRoomMuted({
    required String roomId,
    required bool muted,
  }) async {
    await _call('setRoomMuted', {'roomId': roomId, 'muted': muted});
  }

  @override
  Future<Uri?> audioUri(String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) {
      return null;
    }
    if (audioPath.startsWith('/') || audioPath.startsWith('file:')) {
      return Uri.tryParse(audioPath);
    }
    if (audioPath.startsWith('voice_drafts/')) {
      throw StateError('voice_audio_pending_draft');
    }
    try {
      final url = await _storage.ref(audioPath).getDownloadURL();
      return Uri.parse(url);
    } catch (error) {
      throw StateError('voice_audio_access_denied: $error');
    }
  }

  @override
  Future<void> registerMessagingToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await _messaging.getToken();
    if (token == null) {
      return;
    }
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token.hashCode.toUnsigned(32).toString())
        .set({
          'token': token,
          'platform': _platformName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data, {
    Duration? timeout,
  }) async {
    final result = await _functions
        .httpsCallable(
          name,
          options: timeout == null
              ? null
              : HttpsCallableOptions(timeout: timeout),
        )
        .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  CalendarEvent _calendarEventFromCallable(Map<String, dynamic> result) {
    final rawEvent = result['event'];
    final eventData = rawEvent is Map
        ? Map<String, dynamic>.from(rawEvent)
        : Map<String, dynamic>.from(result);
    final eventId =
        (eventData['id'] as String?) ?? (result['eventId'] as String?) ?? '';
    return CalendarEvent.fromMap(eventId, eventData);
  }

  auth.User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }
    return user;
  }

  Future<AppUser> _ensureUserDocument(auth.User? user) async {
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }
    final userRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await userRef.get();
    if (!snapshot.exists) {
      await userRef.set({
        'displayName': user.displayName ?? '',
        'handle': '',
        'defaultSendMode': SendMode.confirm.name,
        'calendarReminderEnabled': true,
        'calendarReminderLeadMinutes': 30,
        'morningBriefingEnabled': false,
        'morningBriefingMinuteOfDay': 480,
        'calendarTimezone': 'Asia/Seoul',
        'holidayCountryCode': 'KR',
        'photoUrl': user.photoURL,
        'phoneHash': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return AppUser(
        uid: user.uid,
        displayName: user.displayName ?? '',
        handle: '',
        defaultSendMode: SendMode.confirm,
        calendarReminderEnabled: true,
        calendarReminderLeadMinutes: 30,
        morningBriefingEnabled: false,
        morningBriefingMinuteOfDay: 480,
        calendarTimezone: 'Asia/Seoul',
        holidayCountryCode: 'KR',
        photoUrl: user.photoURL,
      );
    }
    return AppUser.fromMap(user.uid, snapshot.data() ?? {});
  }

  String _safeStorageFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (sanitized.isEmpty) {
      return 'attachment.bin';
    }
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }

  String _inviteTokenFromInput(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final inviteIndex = uri.pathSegments.indexOf('invite');
      if (inviteIndex != -1 && inviteIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[inviteIndex + 1];
      }
      return uri.pathSegments.last;
    }
    return trimmed.split('/').where((segment) => segment.isNotEmpty).last;
  }

  String _audioExtensionForPath(String path) {
    final normalized = path.toLowerCase();
    for (final extension in const ['.webm', '.wav', '.mp3', '.m4a']) {
      if (normalized.endsWith(extension)) {
        return extension;
      }
    }
    return '.m4a';
  }

  String _audioContentTypeForExtension(String extension) {
    switch (extension) {
      case '.webm':
        return 'audio/webm';
      case '.wav':
        return 'audio/wav';
      case '.mp3':
        return 'audio/mpeg';
      default:
        return 'audio/mp4';
    }
  }

  String get _platformName => kIsWeb ? 'web' : defaultTargetPlatform.name;
}
