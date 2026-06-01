import 'dart:async';

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
import 'messenger_backend.dart';

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
    final data = <String, dynamic>{'roomId': roomId, 'text': text.trim()};
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('sendTextMessage', data);
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
    final storagePath = 'voice_drafts/${user.uid}/$draftId.m4a';
    await uploadAudioFile(
      ref: _storage.ref(storagePath),
      audioFilePath: audioFilePath,
      metadata: SettableMetadata(
        contentType: 'audio/mp4',
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
    final storagePath = 'voice_drafts/${user.uid}/calendar_$draftId.m4a';
    await uploadAudioFile(
      ref: _storage.ref(storagePath),
      audioFilePath: audioFilePath,
      metadata: SettableMetadata(
        contentType: 'audio/mp4',
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
  Future<void> sendInstantVoiceMessage({
    required String roomId,
    required String audioFilePath,
    required int durationMs,
    required SendMode sendMode,
    String language = 'ko-KR',
    String? transcriptOverride,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    final messageId = _uuid.v4();
    final storagePath = 'voice_drafts/${user.uid}/$messageId.m4a';
    await uploadAudioFile(
      ref: _storage.ref(storagePath),
      audioFilePath: audioFilePath,
      metadata: SettableMetadata(
        contentType: 'audio/mp4',
        customMetadata: {
          'ownerId': user.uid,
          'durationMs': '$durationMs',
          'language': language,
        },
      ),
    );

    final data = <String, dynamic>{
      'roomId': roomId,
      'messageId': messageId,
      'audioPath': storagePath,
      'durationMs': durationMs,
      'sendMode': sendMode.name,
      'language': language,
    };
    final manualTranscript = transcriptOverride?.trim();
    if (manualTranscript != null && manualTranscript.isNotEmpty) {
      data['transcriptOverride'] = manualTranscript;
    }
    if (replyToMessageId != null) {
      data['replyToMessageId'] = replyToMessageId;
    }
    await _call('sendInstantVoiceMessage', data);
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
    final url = await _storage.ref(audioPath).getDownloadURL();
    return Uri.parse(url);
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
    Map<String, dynamic> data,
  ) async {
    final result = await _functions
        .httpsCallable(name)
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

  String get _platformName => kIsWeb ? 'web' : defaultTargetPlatform.name;
}
