import 'package:cloud_firestore/cloud_firestore.dart';

enum SendMode {
  confirm,
  instant;

  static SendMode fromWire(String? value) {
    return values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => SendMode.confirm,
    );
  }

  String get label => switch (this) {
    SendMode.confirm => '확인 후 전송',
    SendMode.instant => '즉시 전송',
  };
}

enum RoomType {
  direct,
  group,
  open;

  static RoomType fromWire(String? value) {
    return values.firstWhere(
      (type) => type.name == value,
      orElse: () => RoomType.direct,
    );
  }
}

enum MessageKind {
  text,
  voice,
  image,
  file,
  location,
  calendarProposal;

  static MessageKind fromWire(String? value) {
    return values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => MessageKind.text,
    );
  }
}

enum MessageDeliveryStatus {
  sending,
  scheduled,
  sent,
  failed;

  static MessageDeliveryStatus fromWire(String? value) {
    return values.firstWhere(
      (status) => status.name == value,
      orElse: () => MessageDeliveryStatus.sent,
    );
  }

  String get label => switch (this) {
    MessageDeliveryStatus.sending => '전송 중',
    MessageDeliveryStatus.scheduled => '예약됨',
    MessageDeliveryStatus.sent => '전송됨',
    MessageDeliveryStatus.failed => '실패',
  };
}

enum AttachmentType {
  image,
  file,
  location;

  static AttachmentType fromWire(String? value) {
    return values.firstWhere(
      (type) => type.name == value,
      orElse: () => AttachmentType.file,
    );
  }
}

enum RoomMemberRole {
  owner,
  admin,
  member;

  static RoomMemberRole fromWire(String? value) {
    return values.firstWhere(
      (role) => role.name == value,
      orElse: () => RoomMemberRole.member,
    );
  }

  String get label => switch (this) {
    RoomMemberRole.owner => '소유자',
    RoomMemberRole.admin => '관리자',
    RoomMemberRole.member => '멤버',
  };

  bool get canManageRoom => this == owner || this == admin;
}

enum InviteJoinStatus {
  joined,
  pending,
  approved,
  rejected;

  static InviteJoinStatus fromWire(String? value) {
    return values.firstWhere(
      (status) => status.name == value,
      orElse: () => InviteJoinStatus.joined,
    );
  }
}

enum SttStatus {
  none,
  pending,
  processing,
  completed,
  failed;

  static SttStatus fromWire(String? value) {
    return values.firstWhere(
      (status) => status.name == value,
      orElse: () => SttStatus.none,
    );
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.handle,
    required this.defaultSendMode,
    this.calendarReminderEnabled = true,
    this.calendarReminderLeadMinutes = 30,
    this.morningBriefingEnabled = false,
    this.morningBriefingMinuteOfDay = 480,
    this.calendarTimezone = 'Asia/Seoul',
    this.holidayCountryCode = 'KR',
    this.photoUrl,
    this.phoneHash,
  });

  final String uid;
  final String displayName;
  final String handle;
  final SendMode defaultSendMode;
  final bool calendarReminderEnabled;
  final int calendarReminderLeadMinutes;
  final bool morningBriefingEnabled;
  final int morningBriefingMinuteOfDay;
  final String calendarTimezone;
  final String holidayCountryCode;
  final String? photoUrl;
  final String? phoneHash;

  bool get hasProfile =>
      displayName.trim().isNotEmpty && handle.trim().isNotEmpty;

  AppUser copyWith({
    String? displayName,
    String? handle,
    SendMode? defaultSendMode,
    bool? calendarReminderEnabled,
    int? calendarReminderLeadMinutes,
    bool? morningBriefingEnabled,
    int? morningBriefingMinuteOfDay,
    String? calendarTimezone,
    String? holidayCountryCode,
    String? photoUrl,
    String? phoneHash,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      defaultSendMode: defaultSendMode ?? this.defaultSendMode,
      calendarReminderEnabled:
          calendarReminderEnabled ?? this.calendarReminderEnabled,
      calendarReminderLeadMinutes:
          calendarReminderLeadMinutes ?? this.calendarReminderLeadMinutes,
      morningBriefingEnabled:
          morningBriefingEnabled ?? this.morningBriefingEnabled,
      morningBriefingMinuteOfDay:
          morningBriefingMinuteOfDay ?? this.morningBriefingMinuteOfDay,
      calendarTimezone: calendarTimezone ?? this.calendarTimezone,
      holidayCountryCode: holidayCountryCode ?? this.holidayCountryCode,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneHash: phoneHash ?? this.phoneHash,
    );
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      displayName: (data['displayName'] as String?) ?? '',
      handle: (data['handle'] as String?) ?? '',
      defaultSendMode: SendMode.fromWire(data['defaultSendMode'] as String?),
      calendarReminderEnabled: data['calendarReminderEnabled'] != false,
      calendarReminderLeadMinutes:
          (data['calendarReminderLeadMinutes'] as num?)?.round() ?? 30,
      morningBriefingEnabled: data['morningBriefingEnabled'] == true,
      morningBriefingMinuteOfDay:
          (data['morningBriefingMinuteOfDay'] as num?)?.round() ?? 480,
      calendarTimezone:
          (data['calendarTimezone'] as String?)?.trim().isNotEmpty == true
          ? (data['calendarTimezone'] as String).trim()
          : 'Asia/Seoul',
      holidayCountryCode:
          (data['holidayCountryCode'] as String?)?.trim().isNotEmpty == true
          ? (data['holidayCountryCode'] as String).trim()
          : 'KR',
      photoUrl: data['photoUrl'] as String?,
      phoneHash: data['phoneHash'] as String?,
    );
  }
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.type,
    required this.participantIds,
    required this.title,
    required this.updatedAt,
    this.ownerId,
    this.memberRole = 'member',
    this.lastMessage,
    this.pinned = false,
    this.archived = false,
    this.muted = false,
    this.unreadCount = 0,
    this.lastReadAt,
    this.leftAt,
    this.inviteApprovalRequired = false,
    this.audioRetentionDays = 1,
    this.audioRetentionPreset = 'oneDay',
  });

  final String id;
  final RoomType type;
  final List<String> participantIds;
  final String title;
  final DateTime updatedAt;
  final String? ownerId;
  final String memberRole;
  final LastMessage? lastMessage;
  final bool pinned;
  final bool archived;
  final bool muted;
  final int unreadCount;
  final DateTime? lastReadAt;
  final DateTime? leftAt;
  final bool inviteApprovalRequired;
  final int audioRetentionDays;
  final String audioRetentionPreset;

  String get audioRetentionLabel {
    if (audioRetentionDays == 1) {
      return '1일';
    }
    if (audioRetentionDays == 7) {
      return '7일';
    }
    return '$audioRetentionDays일';
  }

  ChatRoom copyWith({
    List<String>? participantIds,
    String? title,
    DateTime? updatedAt,
    String? ownerId,
    String? memberRole,
    LastMessage? lastMessage,
    bool clearLastMessage = false,
    bool? pinned,
    bool? archived,
    bool? muted,
    int? unreadCount,
    DateTime? lastReadAt,
    DateTime? leftAt,
    bool? inviteApprovalRequired,
    int? audioRetentionDays,
    String? audioRetentionPreset,
  }) {
    return ChatRoom(
      id: id,
      type: type,
      participantIds: participantIds ?? this.participantIds,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
      memberRole: memberRole ?? this.memberRole,
      lastMessage: clearLastMessage ? null : lastMessage ?? this.lastMessage,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      muted: muted ?? this.muted,
      unreadCount: unreadCount ?? this.unreadCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      leftAt: leftAt ?? this.leftAt,
      inviteApprovalRequired:
          inviteApprovalRequired ?? this.inviteApprovalRequired,
      audioRetentionDays: audioRetentionDays ?? this.audioRetentionDays,
      audioRetentionPreset: audioRetentionPreset ?? this.audioRetentionPreset,
    );
  }

  factory ChatRoom.fromMap(String id, Map<String, dynamic> data) {
    return ChatRoom(
      id: id,
      type: RoomType.fromWire(data['type'] as String?),
      participantIds: List<String>.from(
        data['participantIds'] as List? ?? const [],
      ),
      title: (data['title'] as String?) ?? '새 대화',
      updatedAt:
          _dateFromAny(data['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      ownerId: data['ownerId'] as String?,
      memberRole: (data['role'] as String?) ?? 'member',
      lastMessage: data['lastMessage'] is Map
          ? LastMessage.fromMap(
              Map<String, dynamic>.from(data['lastMessage'] as Map),
            )
          : null,
      pinned: data['pinned'] == true,
      archived: data['archived'] == true,
      muted: data['muted'] == true,
      unreadCount: (data['unreadCount'] as num?)?.round() ?? 0,
      lastReadAt: _dateFromAny(data['lastReadAt']),
      leftAt: _dateFromAny(data['leftAt']),
      inviteApprovalRequired: data['inviteApprovalRequired'] == true,
      audioRetentionDays: _boundedInt(data['audioRetentionDays'], 1, 1, 30),
      audioRetentionPreset:
          (data['audioRetentionPreset'] as String?) ?? 'oneDay',
    );
  }
}

class RoomMember {
  const RoomMember({
    required this.uid,
    required this.role,
    required this.joinedAt,
    this.displayName,
    this.handle,
    this.leftAt,
  });

  final String uid;
  final RoomMemberRole role;
  final DateTime joinedAt;
  final String? displayName;
  final String? handle;
  final DateTime? leftAt;

  bool get active => leftAt == null;

  factory RoomMember.fromMap(String uid, Map<String, dynamic> data) {
    return RoomMember(
      uid: uid,
      role: RoomMemberRole.fromWire(data['role'] as String?),
      joinedAt:
          _dateFromAny(data['joinedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      displayName: data['displayName'] as String?,
      handle: data['handle'] as String?,
      leftAt: _dateFromAny(data['leftAt']),
    );
  }
}

class RoomInvite {
  const RoomInvite({
    required this.id,
    required this.roomId,
    required this.token,
    required this.url,
    required this.createdBy,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.approvalRequired = false,
  });

  final String id;
  final String roomId;
  final String token;
  final String url;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final bool approvalRequired;

  bool get isActive =>
      revokedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory RoomInvite.fromMap(String id, Map<String, dynamic> data) {
    return RoomInvite(
      id: id,
      roomId: (data['roomId'] as String?) ?? '',
      token: (data['token'] as String?) ?? id,
      url: (data['url'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: _dateFromAny(data['expiresAt']),
      revokedAt: _dateFromAny(data['revokedAt']),
      approvalRequired: data['approvalRequired'] == true,
    );
  }
}

class InviteJoinResult {
  const InviteJoinResult({
    required this.status,
    required this.roomId,
    this.room,
    this.requestId,
  });

  final InviteJoinStatus status;
  final String roomId;
  final ChatRoom? room;
  final String? requestId;

  bool get joined => status == InviteJoinStatus.joined;

  bool get pending => status == InviteJoinStatus.pending;

  factory InviteJoinResult.fromMap(Map<String, dynamic> data) {
    final roomData = data['room'];
    return InviteJoinResult(
      status: InviteJoinStatus.fromWire(data['status'] as String?),
      roomId: (data['roomId'] as String?) ?? '',
      requestId: data['requestId'] as String?,
      room: roomData is Map
          ? ChatRoom.fromMap(
              (data['roomId'] as String?) ?? '',
              Map<String, dynamic>.from(roomData),
            )
          : null,
    );
  }
}

class RoomJoinRequest {
  const RoomJoinRequest({
    required this.uid,
    required this.roomId,
    required this.inviteId,
    required this.status,
    required this.createdAt,
    this.displayName,
    this.handle,
  });

  final String uid;
  final String roomId;
  final String inviteId;
  final InviteJoinStatus status;
  final DateTime createdAt;
  final String? displayName;
  final String? handle;

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final userHandle = handle?.trim();
    if (userHandle != null && userHandle.isNotEmpty) {
      return '@$userHandle';
    }
    return uid;
  }

  factory RoomJoinRequest.fromMap(String uid, Map<String, dynamic> data) {
    return RoomJoinRequest(
      uid: uid,
      roomId: (data['roomId'] as String?) ?? '',
      inviteId: (data['inviteId'] as String?) ?? '',
      status: InviteJoinStatus.fromWire(data['status'] as String?),
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      displayName: data['displayName'] as String?,
      handle: data['handle'] as String?,
    );
  }
}

class LastMessage {
  const LastMessage({
    required this.kind,
    required this.preview,
    required this.senderId,
    required this.createdAt,
  });

  final MessageKind kind;
  final String preview;
  final String senderId;
  final DateTime createdAt;

  factory LastMessage.fromMap(Map<String, dynamic> data) {
    return LastMessage(
      kind: MessageKind.fromWire(data['kind'] as String?),
      preview: (data['preview'] as String?) ?? '',
      senderId: (data['senderId'] as String?) ?? '',
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.kind,
    required this.text,
    required this.transcript,
    required this.audioPath,
    required this.durationMs,
    required this.sttStatus,
    required this.sendMode,
    required this.createdAt,
    this.replyTo,
    this.attachment,
    this.calendarProposal,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.scheduledAt,
    this.translations = const {},
    this.reactions = const {},
    this.pinnedAt,
    this.pinnedBy,
    this.editedAt,
    this.deletedAt,
    this.deletedBy,
    this.audioHash,
    this.audioExpiresAt,
    this.audioDeletedAt,
    this.audioRetentionDays,
    this.audioRetentionStatus = 'none',
    this.sttCacheHit = false,
  });

  final String id;
  final String senderId;
  final MessageKind kind;
  final String text;
  final String transcript;
  final String? audioPath;
  final String? audioHash;
  final DateTime? audioExpiresAt;
  final DateTime? audioDeletedAt;
  final int? audioRetentionDays;
  final String audioRetentionStatus;
  final int durationMs;
  final SttStatus sttStatus;
  final bool sttCacheHit;
  final SendMode sendMode;
  final DateTime createdAt;
  final MessageReply? replyTo;
  final MessageAttachment? attachment;
  final CalendarProposal? calendarProposal;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime? scheduledAt;
  final Map<String, MessageTranslation> translations;
  final Map<String, List<String>> reactions;
  final DateTime? pinnedAt;
  final String? pinnedBy;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? deletedBy;

  bool get isDeleted => deletedAt != null;

  bool get isEdited => editedAt != null && !isDeleted;

  bool get isPinned => pinnedAt != null && !isDeleted;

  bool get hasPlayableAudio =>
      audioPath != null && audioPath!.isNotEmpty && audioDeletedAt == null;

  bool get audioExpired =>
      audioDeletedAt != null || audioRetentionStatus == 'deleted';

  bool get isScheduled =>
      !isDeleted && deliveryStatus == MessageDeliveryStatus.scheduled;

  int get reactionCount =>
      reactions.values.fold<int>(0, (total, users) => total + users.length);

  static bool _isGenericVoicePlaceholder(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ||
        normalized == '\uC74C\uC131 \uBA54\uC2DC\uC9C0' ||
        normalized == '\uC0C8 \uC74C\uC131 \uBA54\uC2DC\uC9C0' ||
        normalized == 'Voice message' ||
        normalized == '\uC74C\uC131 \uBCC0\uD658 \uC911...' ||
        normalized == '\uC74C\uC131 \uBCC0\uD658 \uB300\uAE30 \uC911...' ||
        normalized == '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC \uC5C6\uC74C' ||
        normalized ==
            '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC\uAC00 \uBE44\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.';
  }

  static bool _isFailedVoicePlaceholder(String value) {
    final normalized = value.trim();
    return normalized ==
            '\uC74C\uC131 \uBCC0\uD658\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.' ||
        normalized == '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328' ||
        normalized == '\uBCC0\uD658 \uC2E4\uD328';
  }

  static bool _looksLikeCorruptedVoicePlaceholder(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return true;
    }
    const mojibakeSignals = [
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
    ];
    final hasLongQuestionRun =
        RegExp(r'\?{3,}').hasMatch(normalized) && normalized.length > 12;
    return hasLongQuestionRun || mojibakeSignals.any(normalized.contains);
  }

  static String _cleanVoiceTranscriptText(String value) {
    final lines = value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_isGenericVoicePlaceholder(line))
        .where((line) => !_isFailedVoicePlaceholder(line))
        .where((line) => !_looksLikeCorruptedVoicePlaceholder(line))
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  String get voiceTranscriptText {
    if (kind != MessageKind.voice || isDeleted) {
      return '';
    }
    final trimmedText = _cleanVoiceTranscriptText(text);
    if (trimmedText.isNotEmpty &&
        !_isFailedVoicePlaceholder(trimmedText) &&
        !_isGenericVoicePlaceholder(trimmedText)) {
      return trimmedText;
    }
    final trimmedTranscript = _cleanVoiceTranscriptText(transcript);
    if (trimmedTranscript.isNotEmpty &&
        !_isFailedVoicePlaceholder(trimmedTranscript) &&
        !_isGenericVoicePlaceholder(trimmedTranscript)) {
      return trimmedTranscript;
    }
    return '';
  }

  String get displayText {
    if (isDeleted) {
      return '\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4.';
    }
    final trimmedText = text.trim();
    final trimmedTranscript = transcript.trim();
    if (kind == MessageKind.voice) {
      final voiceText = voiceTranscriptText;
      if (voiceText.isNotEmpty) {
        return voiceText;
      }
      if (deliveryStatus == MessageDeliveryStatus.sending ||
          sttStatus == SttStatus.processing ||
          sttStatus == SttStatus.pending) {
        return '\uC74C\uC131 \uBCC0\uD658 \uC911...';
      }
      if (sttStatus == SttStatus.failed) {
        return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
      }
      return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
    }
    if (trimmedText.isNotEmpty) {
      return trimmedText;
    }
    if (trimmedTranscript.isNotEmpty) {
      return trimmedTranscript;
    }
    if (attachment != null) {
      return attachment!.preview;
    }
    if (calendarProposal != null) {
      return calendarProposal!.title;
    }
    if (sttStatus == SttStatus.processing || sttStatus == SttStatus.pending) {
      return '\uBCC0\uD658 \uC911';
    }
    if (sttStatus == SttStatus.failed) {
      return '\uBCC0\uD658 \uC2E4\uD328';
    }
    return '';
  }

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    final kind = MessageKind.fromWire(data['kind'] as String?);
    final rawText = (data['text'] as String?) ?? '';
    final rawTranscript = (data['transcript'] as String?) ?? '';
    final text = kind == MessageKind.voice
        ? _cleanVoiceTranscriptText(rawText)
        : rawText;
    final transcript = kind == MessageKind.voice
        ? _cleanVoiceTranscriptText(rawTranscript)
        : rawTranscript;
    final rawSttStatus = SttStatus.fromWire(data['sttStatus'] as String?);
    final audioPath = data['audioPath'] as String?;
    final hasVoiceText = text.trim().isNotEmpty || transcript.trim().isNotEmpty;
    final sttStatus =
        kind == MessageKind.voice &&
            !hasVoiceText &&
            audioPath != null &&
            audioPath.isNotEmpty &&
            rawSttStatus != SttStatus.failed
        ? SttStatus.processing
        : rawSttStatus;
    return ChatMessage(
      id: id,
      senderId: (data['senderId'] as String?) ?? '',
      kind: kind,
      text: text,
      transcript: transcript,
      audioPath: audioPath,
      audioHash: data['audioHash'] as String?,
      audioExpiresAt: _dateFromAny(data['audioExpiresAt']),
      audioDeletedAt: _dateFromAny(data['audioDeletedAt']),
      audioRetentionDays: (data['audioRetentionDays'] as num?)?.round(),
      audioRetentionStatus: (data['audioRetentionStatus'] as String?) ?? 'none',
      durationMs: (data['durationMs'] as num?)?.round() ?? 0,
      sttStatus: sttStatus,
      sttCacheHit: data['sttCacheHit'] == true,
      sendMode: SendMode.fromWire(data['sendMode'] as String?),
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      replyTo: data['replyTo'] is Map
          ? MessageReply.fromMap(
              Map<String, dynamic>.from(data['replyTo'] as Map),
            )
          : null,
      attachment: data['attachment'] is Map
          ? MessageAttachment.fromMap(
              Map<String, dynamic>.from(data['attachment'] as Map),
            )
          : null,
      calendarProposal: data['calendarProposal'] is Map
          ? CalendarProposal.fromMap(
              Map<String, dynamic>.from(data['calendarProposal'] as Map),
            )
          : null,
      deliveryStatus: MessageDeliveryStatus.fromWire(
        data['deliveryStatus'] as String?,
      ),
      scheduledAt: _dateFromAny(data['scheduledAt']),
      translations: _translationsFromAny(data['translations']),
      reactions: _reactionsFromAny(data['reactions']),
      pinnedAt: _dateFromAny(data['pinnedAt']),
      pinnedBy: data['pinnedBy'] as String?,
      editedAt: _dateFromAny(data['editedAt']),
      deletedAt: _dateFromAny(data['deletedAt']),
      deletedBy: data['deletedBy'] as String?,
    );
  }

  ChatMessage copyWith({
    String? text,
    String? transcript,
    String? audioPath,
    String? audioHash,
    DateTime? audioExpiresAt,
    DateTime? audioDeletedAt,
    int? audioRetentionDays,
    String? audioRetentionStatus,
    int? durationMs,
    SttStatus? sttStatus,
    bool? sttCacheHit,
    MessageReply? replyTo,
    MessageAttachment? attachment,
    CalendarProposal? calendarProposal,
    MessageDeliveryStatus? deliveryStatus,
    DateTime? scheduledAt,
    Map<String, MessageTranslation>? translations,
    Map<String, List<String>>? reactions,
    DateTime? pinnedAt,
    String? pinnedBy,
    bool clearPin = false,
    DateTime? editedAt,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      kind: kind,
      text: text ?? this.text,
      transcript: transcript ?? this.transcript,
      audioPath: audioPath ?? this.audioPath,
      audioHash: audioHash ?? this.audioHash,
      audioExpiresAt: audioExpiresAt ?? this.audioExpiresAt,
      audioDeletedAt: audioDeletedAt ?? this.audioDeletedAt,
      audioRetentionDays: audioRetentionDays ?? this.audioRetentionDays,
      audioRetentionStatus: audioRetentionStatus ?? this.audioRetentionStatus,
      durationMs: durationMs ?? this.durationMs,
      sttStatus: sttStatus ?? this.sttStatus,
      sttCacheHit: sttCacheHit ?? this.sttCacheHit,
      sendMode: sendMode,
      createdAt: createdAt,
      replyTo: replyTo ?? this.replyTo,
      attachment: attachment ?? this.attachment,
      calendarProposal: calendarProposal ?? this.calendarProposal,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      translations: translations ?? this.translations,
      reactions: reactions ?? this.reactions,
      pinnedAt: clearPin ? null : pinnedAt ?? this.pinnedAt,
      pinnedBy: clearPin ? null : pinnedBy ?? this.pinnedBy,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
    );
  }
}

class MessageAttachment {
  const MessageAttachment({
    required this.type,
    required this.title,
    this.url,
    this.storagePath,
    this.mimeType,
    this.sizeBytes,
    this.latitude,
    this.longitude,
    this.address,
  });

  final AttachmentType type;
  final String title;
  final String? url;
  final String? storagePath;
  final String? mimeType;
  final int? sizeBytes;
  final double? latitude;
  final double? longitude;
  final String? address;

  String get preview => switch (type) {
    AttachmentType.image => title.isEmpty ? '사진' : title,
    AttachmentType.file => title.isEmpty ? '파일' : title,
    AttachmentType.location =>
      address?.trim().isNotEmpty == true
          ? address!.trim()
          : title.isEmpty
          ? '위치'
          : title,
  };

  factory MessageAttachment.fromMap(Map<String, dynamic> data) {
    return MessageAttachment(
      type: AttachmentType.fromWire(data['type'] as String?),
      title: (data['title'] as String?) ?? '',
      url: data['url'] as String?,
      storagePath: data['storagePath'] as String?,
      mimeType: data['mimeType'] as String?,
      sizeBytes: (data['sizeBytes'] as num?)?.round(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      address: data['address'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'title': title,
      if (url != null) 'url': url,
      if (storagePath != null) 'storagePath': storagePath,
      if (mimeType != null) 'mimeType': mimeType,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (address != null) 'address': address,
    };
  }

  MessageAttachment copyWith({
    String? title,
    String? url,
    String? storagePath,
    String? mimeType,
    int? sizeBytes,
    double? latitude,
    double? longitude,
    String? address,
  }) {
    return MessageAttachment(
      type: type,
      title: title ?? this.title,
      url: url ?? this.url,
      storagePath: storagePath ?? this.storagePath,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
    );
  }
}

class MessageTranslation {
  const MessageTranslation({
    required this.targetLanguage,
    required this.text,
    required this.createdAt,
  });

  final String targetLanguage;
  final String text;
  final DateTime createdAt;

  factory MessageTranslation.fromMap(
    String targetLanguage,
    Map<String, dynamic> data,
  ) {
    return MessageTranslation(
      targetLanguage: targetLanguage,
      text: (data['text'] as String?) ?? '',
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() {
    return {'text': text, 'createdAt': createdAt.toIso8601String()};
  }
}

class MessageReply {
  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.preview,
  });

  final String messageId;
  final String senderId;
  final String preview;

  factory MessageReply.fromMap(Map<String, dynamic> data) {
    return MessageReply(
      messageId: (data['messageId'] as String?) ?? '',
      senderId: (data['senderId'] as String?) ?? '',
      preview: (data['preview'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'messageId': messageId, 'senderId': senderId, 'preview': preview};
  }
}

class TranscriptionDraft {
  const TranscriptionDraft({
    required this.id,
    required this.audioPath,
    required this.transcript,
    required this.status,
    required this.durationMs,
    this.errorCode,
    this.audioHash,
    this.sttCacheHit = false,
  });

  final String id;
  final String audioPath;
  final String transcript;
  final SttStatus status;
  final int durationMs;
  final String? errorCode;
  final String? audioHash;
  final bool sttCacheHit;

  factory TranscriptionDraft.fromMap(String id, Map<String, dynamic> data) {
    return TranscriptionDraft(
      id: id,
      audioPath: (data['audioPath'] as String?) ?? '',
      transcript: (data['transcript'] as String?) ?? '',
      status: SttStatus.fromWire(data['status'] as String?),
      durationMs: (data['durationMs'] as num?)?.round() ?? 0,
      errorCode: data['errorCode'] as String?,
      audioHash: data['audioHash'] as String?,
      sttCacheHit: data['sttCacheHit'] == true,
    );
  }
}

class CalendarIntentDraft {
  const CalendarIntentDraft({
    required this.id,
    required this.transcript,
    required this.parsedTitle,
    required this.startAt,
    required this.endAt,
    required this.timezone,
    required this.missingFields,
  });

  final String id;
  final String transcript;
  final String? parsedTitle;
  final DateTime? startAt;
  final DateTime? endAt;
  final String timezone;
  final List<String> missingFields;

  bool get isComplete =>
      parsedTitle?.trim().isNotEmpty == true &&
      startAt != null &&
      endAt != null &&
      missingFields.isEmpty;

  factory CalendarIntentDraft.fromMap(Map<String, dynamic> data) {
    return CalendarIntentDraft(
      id: (data['draftId'] as String?) ?? (data['id'] as String?) ?? '',
      transcript: (data['transcript'] as String?) ?? '',
      parsedTitle: data['parsedTitle'] as String?,
      startAt: _dateFromAny(data['startAt']),
      endAt: _dateFromAny(data['endAt']),
      timezone: (data['timezone'] as String?) ?? 'Asia/Seoul',
      missingFields: List<String>.from(
        data['missingFields'] as List? ?? const <String>[],
      ),
    );
  }
}

class CalendarProposalCandidate {
  const CalendarProposalCandidate({
    required this.id,
    required this.startAt,
    required this.endAt,
  });

  final String id;
  final DateTime startAt;
  final DateTime endAt;

  int get durationMinutes =>
      endAt.difference(startAt).inMinutes.clamp(1, 24 * 60).toInt();

  factory CalendarProposalCandidate.fromMap(Map<String, dynamic> data) {
    final startAt = _dateFromAny(data['startAt']) ?? DateTime.now();
    final endAt =
        _dateFromAny(data['endAt']) ?? startAt.add(const Duration(hours: 1));
    return CalendarProposalCandidate(
      id: (data['candidateId'] as String?) ?? (data['id'] as String?) ?? '',
      startAt: startAt,
      endAt: endAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'candidateId': id,
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
    };
  }
}

class CalendarProposal {
  const CalendarProposal({
    required this.id,
    required this.roomId,
    required this.messageId,
    required this.createdBy,
    required this.title,
    required this.details,
    required this.timezone,
    required this.status,
    required this.candidates,
    required this.votes,
    required this.createdAt,
    required this.updatedAt,
    this.finalCandidateId,
    this.source = 'manual',
    this.transcript = '',
  });

  final String id;
  final String roomId;
  final String messageId;
  final String createdBy;
  final String title;
  final String details;
  final String timezone;
  final String status;
  final List<CalendarProposalCandidate> candidates;
  final Map<String, List<String>> votes;
  final String? finalCandidateId;
  final String source;
  final String transcript;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => status == 'open';

  bool get isFinalized => status == 'finalized';

  bool get isCancelled => status == 'cancelled';

  int voteCount(String candidateId) {
    return votes.values.where((ids) => ids.contains(candidateId)).length;
  }

  List<String> selectedCandidateIds(String uid) {
    return List<String>.from(votes[uid] ?? const <String>[]);
  }

  CalendarProposalCandidate? get finalCandidate {
    final id = finalCandidateId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final candidate in candidates) {
      if (candidate.id == id) {
        return candidate;
      }
    }
    return null;
  }

  factory CalendarProposal.fromMap(Map<String, dynamic> data) {
    final rawVotes = data['votes'];
    final votes = <String, List<String>>{};
    if (rawVotes is Map) {
      for (final entry in rawVotes.entries) {
        final value = entry.value;
        votes['${entry.key}'] = value is List
            ? value.map((item) => '$item').toList(growable: false)
            : const <String>[];
      }
    }
    return CalendarProposal(
      id: (data['proposalId'] as String?) ?? (data['id'] as String?) ?? '',
      roomId: (data['roomId'] as String?) ?? '',
      messageId: (data['messageId'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      details: (data['details'] as String?) ?? '',
      timezone: (data['timezone'] as String?) ?? 'Asia/Seoul',
      status: (data['status'] as String?) ?? 'open',
      candidates: (data['candidates'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => CalendarProposalCandidate.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      votes: votes,
      finalCandidateId: data['finalCandidateId'] as String?,
      source: (data['source'] as String?) ?? 'manual',
      transcript: (data['transcript'] as String?) ?? '',
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _dateFromAny(data['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'proposalId': id,
      'roomId': roomId,
      'messageId': messageId,
      'createdBy': createdBy,
      'title': title,
      'details': details,
      'timezone': timezone,
      'status': status,
      'candidates': candidates.map((candidate) => candidate.toMap()).toList(),
      'votes': votes,
      if (finalCandidateId != null) 'finalCandidateId': finalCandidateId,
      'source': source,
      'transcript': transcript,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  CalendarProposal copyWith({
    String? status,
    Map<String, List<String>>? votes,
    String? finalCandidateId,
    DateTime? updatedAt,
  }) {
    return CalendarProposal(
      id: id,
      roomId: roomId,
      messageId: messageId,
      createdBy: createdBy,
      title: title,
      details: details,
      timezone: timezone,
      status: status ?? this.status,
      candidates: candidates,
      votes: votes ?? this.votes,
      finalCandidateId: finalCandidateId ?? this.finalCandidateId,
      source: source,
      transcript: transcript,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.timezone,
    required this.source,
    required this.details,
    required this.transcript,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.roomId,
    this.proposalId,
    this.messageId,
    this.candidateId,
  });

  final String id;
  final String ownerId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String timezone;
  final String source;
  final String details;
  final String transcript;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? roomId;
  final String? proposalId;
  final String? messageId;
  final String? candidateId;

  int get durationMinutes =>
      endAt.difference(startAt).inMinutes.clamp(1, 24 * 60).toInt();

  bool get isToday {
    final now = DateTime.now();
    return startAt.year == now.year &&
        startAt.month == now.month &&
        startAt.day == now.day;
  }

  factory CalendarEvent.fromMap(String id, Map<String, dynamic> data) {
    final startAt = _dateFromAny(data['startAt']) ?? DateTime.now();
    final endAt =
        _dateFromAny(data['endAt']) ?? startAt.add(const Duration(hours: 1));
    return CalendarEvent(
      id: id,
      ownerId: (data['ownerId'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      startAt: startAt,
      endAt: endAt,
      timezone: (data['timezone'] as String?) ?? 'Asia/Seoul',
      source: (data['source'] as String?) ?? 'manual',
      details: (data['details'] as String?) ?? '',
      transcript: (data['transcript'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'active',
      createdAt:
          _dateFromAny(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _dateFromAny(data['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      roomId: data['roomId'] as String?,
      proposalId: data['proposalId'] as String?,
      messageId: data['messageId'] as String?,
      candidateId: data['candidateId'] as String?,
    );
  }
}

DateTime? _dateFromAny(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

int _boundedInt(Object? value, int fallback, int min, int max) {
  final parsed = value is num ? value.round() : int.tryParse('$value');
  final next = parsed ?? fallback;
  return next.clamp(min, max).toInt();
}

Map<String, List<String>> _reactionsFromAny(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final reactions = <String, List<String>>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final users = entry.value;
    if (key is! String || users is! List) {
      continue;
    }
    reactions[key] = users.whereType<String>().toList(growable: false);
  }
  return Map.unmodifiable(reactions);
}

Map<String, MessageTranslation> _translationsFromAny(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final translations = <String, MessageTranslation>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final data = entry.value;
    if (key is! String || data is! Map) {
      continue;
    }
    translations[key] = MessageTranslation.fromMap(
      key,
      Map<String, dynamic>.from(data),
    );
  }
  return Map.unmodifiable(translations);
}
