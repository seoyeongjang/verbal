import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../models/messenger_models.dart';

abstract class MessengerBackend {
  bool get isConfigured;

  Stream<AppUser?> authState();

  Future<AppUser> signInDemo();

  Future<String> startPhoneVerification(String phoneNumber);

  Future<AppUser> verifySmsCode({
    required String verificationId,
    required String smsCode,
  });

  Future<AppUser> saveProfile({
    required String displayName,
    required String handle,
  });

  Future<void> updateDefaultSendMode(SendMode sendMode);

  Future<void> updateCalendarNotificationSettings({
    required bool calendarReminderEnabled,
    required int calendarReminderLeadMinutes,
    required bool morningBriefingEnabled,
    required int morningBriefingMinuteOfDay,
    String timezone = 'Asia/Seoul',
    String holidayCountryCode = 'KR',
  });

  Future<Map<String, dynamic>> exportMyData();

  Future<Map<String, dynamic>> getOperationalHealth();

  Future<void> deleteAccount();

  Future<void> signOut();

  Stream<List<ChatRoom>> watchRooms(String uid);

  Stream<List<ChatMessage>> watchMessages(String roomId);

  Stream<List<CalendarEvent>> watchCalendarEvents(String uid);

  Stream<List<RoomMember>> watchRoomMembers(String roomId);

  Stream<List<RoomJoinRequest>> watchRoomJoinRequests(String roomId);

  Future<ChatRoom> createRoom({
    required List<String> participantHandles,
    required RoomType type,
    String? title,
  });

  Future<RoomInvite> createRoomInvite({
    required String roomId,
    bool approvalRequired = false,
  });

  Future<void> revokeRoomInvite({
    required String roomId,
    required String inviteId,
  });

  Future<void> setInviteApprovalRequired({
    required String roomId,
    required bool approvalRequired,
  });

  Future<void> setRoomAudioRetention({
    required String roomId,
    required int days,
    required String preset,
  });

  Future<InviteJoinResult> joinRoomByInvite({required String token});

  Future<void> approveRoomJoinRequest({
    required String roomId,
    required String memberUid,
  });

  Future<void> rejectRoomJoinRequest({
    required String roomId,
    required String memberUid,
  });

  Future<void> updateRoomMemberRole({
    required String roomId,
    required String memberUid,
    required RoomMemberRole role,
  });

  Future<void> removeRoomMember({
    required String roomId,
    required String memberUid,
  });

  Future<void> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToMessageId,
  });

  Future<void> scheduleTextMessage({
    required String roomId,
    required String text,
    required DateTime scheduledAt,
    String? replyToMessageId,
  });

  Future<void> sendScheduledMessageNow({
    required String roomId,
    required String messageId,
  });

  Future<void> sendAttachmentMessage({
    required String roomId,
    required MessageKind kind,
    required MessageAttachment attachment,
    AttachmentUploadPayload? upload,
    String caption = '',
    String? replyToMessageId,
  });

  Future<void> createCalendarProposal({
    required String roomId,
    required String title,
    required String details,
    required List<CalendarProposalCandidate> candidates,
    String timezone = 'Asia/Seoul',
    String source = 'manual',
    String transcript = '',
    String? replyToMessageId,
  });

  Future<void> voteCalendarProposal({
    required String roomId,
    required String proposalId,
    required List<String> candidateIds,
  });

  Future<void> finalizeCalendarProposal({
    required String roomId,
    required String proposalId,
    required String candidateId,
  });

  Future<void> addFinalizedProposalToMyCalendar({
    required String roomId,
    required String proposalId,
  });

  Future<void> cancelCalendarProposal({
    required String roomId,
    required String proposalId,
  });

  Future<TranscriptionDraft> createTranscriptionDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  });

  Future<CalendarIntentDraft> createCalendarIntentDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  });

  Future<CalendarEvent> createCalendarEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String timezone = 'Asia/Seoul',
    String source = 'manual',
    String details = '',
    String transcript = '',
  });

  Future<CalendarEvent> updateCalendarEvent({
    required String eventId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String timezone = 'Asia/Seoul',
    String details = '',
  });

  Future<void> deleteCalendarEvent({required String eventId});

  Future<void> sendVoiceMessage({
    required String roomId,
    required String draftId,
    required String finalText,
    required SendMode sendMode,
    String? replyToMessageId,
  });

  Future<void> sendInstantVoiceMessage({
    required String roomId,
    required String audioFilePath,
    required int durationMs,
    required SendMode sendMode,
    String language = 'ko-KR',
    String? transcriptOverride,
    String? replyToMessageId,
  });

  Future<void> editMessage({
    required String roomId,
    required String messageId,
    required String text,
  });

  Future<void> deleteMessage({
    required String roomId,
    required String messageId,
  });

  Future<void> reportMessage({
    required String roomId,
    required String messageId,
    required String reason,
  });

  Future<void> reportRoom({required String roomId, required String reason});

  Future<void> blockUser({required String blockedUid, String? reason});

  Future<void> leaveRoom({required String roomId});

  Future<void> addReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  });

  Future<void> removeReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  });

  Future<MessageTranslation> translateMessage({
    required String roomId,
    required String messageId,
    String targetLanguage = 'en',
  });

  Future<void> pinMessage({required String roomId, required String messageId});

  Future<void> unpinMessage({
    required String roomId,
    required String messageId,
  });

  Future<void> markRoomRead({required String roomId, String? lastMessageId});

  Future<void> setRoomPinned({required String roomId, required bool pinned});

  Future<void> setRoomArchived({
    required String roomId,
    required bool archived,
  });

  Future<void> setRoomMuted({required String roomId, required bool muted});

  Future<Uri?> audioUri(String? audioPath);

  Future<void> registerMessagingToken();
}

class AttachmentUploadPayload {
  const AttachmentUploadPayload({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final Uint8List bytes;
}

class BackendScope extends InheritedWidget {
  const BackendScope({required this.backend, required super.child, super.key});

  final MessengerBackend backend;

  static MessengerBackend of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BackendScope>();
    assert(scope != null, 'BackendScope is missing above this context.');
    return scope!.backend;
  }

  @override
  bool updateShouldNotify(BackendScope oldWidget) =>
      backend != oldWidget.backend;
}
