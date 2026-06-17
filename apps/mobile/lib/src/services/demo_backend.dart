import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/messenger_models.dart';
import 'handle_policy.dart';
import 'local_audio_uri.dart';
import 'messenger_backend.dart';

typedef AudioTranscriber =
    Future<String> Function({
      required String audioFilePath,
      required int durationMs,
      required String language,
    });

class DemoMessengerBackend implements MessengerBackend {
  DemoMessengerBackend({AudioTranscriber? transcriber})
    : _transcriber = transcriber {
    _rooms.add(
      ChatRoom(
        id: _demoRoomId,
        type: RoomType.direct,
        participantIds: const [_demoUid, 'friend-1'],
        title: '김민지',
        updatedAt: DateTime.now(),
        ownerId: _demoUid,
        memberRole: 'owner',
        lastMessage: LastMessage(
          kind: MessageKind.voice,
          preview: '오늘 저녁에 통화 가능해?',
          senderId: 'friend-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
        ),
      ),
    );
    _messages[_demoRoomId] = [
      ChatMessage(
        id: _uuid.v4(),
        senderId: 'friend-1',
        kind: MessageKind.voice,
        text: '오늘 저녁에 통화 가능해?',
        transcript: '오늘 저녁에 통화 가능해?',
        audioPath: null,
        durationMs: 3200,
        sttStatus: SttStatus.completed,
        sendMode: SendMode.confirm,
        createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
      ChatMessage(
        id: _uuid.v4(),
        senderId: _demoUid,
        kind: MessageKind.text,
        text: '네, 오후 8시 가능해요.',
        transcript: '',
        audioPath: null,
        durationMs: 0,
        sttStatus: SttStatus.none,
        sendMode: SendMode.confirm,
        createdAt: DateTime.now().subtract(const Duration(minutes: 7)),
      ),
    ];
    _members[_demoRoomId] = [
      RoomMember(
        uid: _demoUid,
        role: RoomMemberRole.owner,
        joinedAt: DateTime.now().subtract(const Duration(days: 2)),
        displayName: 'Demo',
        handle: 'demo',
      ),
      RoomMember(
        uid: 'friend-1',
        role: RoomMemberRole.member,
        joinedAt: DateTime.now().subtract(const Duration(days: 2)),
        displayName: '김민지',
        handle: 'minji_kim',
      ),
    ];
    _seedDirectRoom(
      roomId: 'demo-room-jihoon',
      friendUid: 'friend-2',
      title: '이지훈',
      handle: 'jihoon_lee',
      preview: '음성 답장 고마워. 바로 확인했어.',
      minutesAgo: 21,
    );
    _seedDirectRoom(
      roomId: 'demo-room-yuna',
      friendUid: 'friend-3',
      title: '정유나',
      handle: 'yuna_jung',
      preview: '내일 일정 후보 두 개 올려뒀어.',
      minutesAgo: 46,
      unread: true,
    );
    _seedDirectRoom(
      roomId: 'demo-room-arin',
      friendUid: 'friend-4',
      title: '최아린',
      handle: 'arin_choi',
      preview: '사진이랑 위치 같이 보내줄게!',
      minutesAgo: 78,
    );
    _seedDirectRoom(
      roomId: 'demo-room-seojun',
      friendUid: 'friend-5',
      title: '박서준',
      handle: 'seojun_park',
      preview: '오늘 브리핑 음성 좋더라.',
      minutesAgo: 132,
    );
    final startAt = DateTime.now().add(const Duration(days: 1, hours: 2));
    _calendarEvents.add(
      CalendarEvent(
        id: _uuid.v4(),
        ownerId: _demoUid,
        title: 'Demo launch review',
        startAt: startAt,
        endAt: startAt.add(const Duration(hours: 1)),
        timezone: 'Asia/Seoul',
        source: 'manual',
        details: '데모 서비스 런칭 전 음성 메시지와 캘린더 흐름을 최종 점검합니다.',
        transcript: '',
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  static const _demoUid = 'demo-user';
  static const _demoRoomId = 'demo-room';

  final _uuid = const Uuid();
  final _authController = StreamController<AppUser?>.broadcast();
  final _roomController = StreamController<List<ChatRoom>>.broadcast();
  final _calendarController = StreamController<List<CalendarEvent>>.broadcast();
  final _messageControllers = <String, StreamController<List<ChatMessage>>>{};
  final _memberControllers = <String, StreamController<List<RoomMember>>>{};
  final _joinRequestControllers =
      <String, StreamController<List<RoomJoinRequest>>>{};
  final _rooms = <ChatRoom>[];
  final _messages = <String, List<ChatMessage>>{};
  final _members = <String, List<RoomMember>>{};
  final _invites = <String, RoomInvite>{};
  final _joinRequests = <String, List<RoomJoinRequest>>{};
  final _scheduleTimers = <String, Timer>{};
  final _drafts = <String, TranscriptionDraft>{};
  final _calendarEvents = <CalendarEvent>[];
  final _calendarProposals = <String, CalendarProposal>{};
  final _blockedUsers = <String>{};
  final _friendHandles = <String>{};
  final _reports = <Map<String, dynamic>>[];
  final AudioTranscriber? _transcriber;

  AppUser? _currentUser;

  void _seedDirectRoom({
    required String roomId,
    required String friendUid,
    required String title,
    required String handle,
    required String preview,
    required int minutesAgo,
    bool unread = false,
  }) {
    final createdAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
    _rooms.add(
      ChatRoom(
        id: roomId,
        type: RoomType.direct,
        participantIds: [_demoUid, friendUid],
        title: title,
        updatedAt: createdAt,
        ownerId: _demoUid,
        memberRole: 'owner',
        unreadCount: unread ? 1 : 0,
        lastMessage: LastMessage(
          kind: MessageKind.text,
          preview: preview,
          senderId: friendUid,
          createdAt: createdAt,
        ),
      ),
    );
    _messages[roomId] = [
      ChatMessage(
        id: _uuid.v4(),
        senderId: friendUid,
        kind: MessageKind.text,
        text: preview,
        transcript: '',
        audioPath: null,
        durationMs: 0,
        sttStatus: SttStatus.none,
        sendMode: SendMode.confirm,
        createdAt: createdAt,
      ),
    ];
    _members[roomId] = [
      RoomMember(
        uid: _demoUid,
        role: RoomMemberRole.owner,
        joinedAt: DateTime.now().subtract(const Duration(days: 2)),
        displayName: 'Demo',
        handle: 'demo',
      ),
      RoomMember(
        uid: friendUid,
        role: RoomMemberRole.member,
        joinedAt: DateTime.now().subtract(const Duration(days: 2)),
        displayName: title,
        handle: handle,
      ),
    ];
  }

  @override
  bool get isConfigured => false;

  @override
  Stream<AppUser?> authState() async* {
    yield _currentUser;
    yield* _authController.stream;
  }

  @override
  Future<AppUser> signInDemo() async {
    _currentUser = const AppUser(
      uid: _demoUid,
      displayName: 'Demo',
      handle: 'demo',
      defaultSendMode: SendMode.confirm,
    );
    _authController.add(_currentUser);
    _emitRooms();
    _emitCalendarEvents();
    return _currentUser!;
  }

  @override
  Future<String> startPhoneVerification(String phoneNumber) async {
    return 'demo-verification';
  }

  @override
  Future<AppUser> verifySmsCode({
    required String verificationId,
    required String smsCode,
  }) {
    return signInDemo();
  }

  @override
  Future<AppUser> saveProfile({
    required String displayName,
    required String handle,
  }) async {
    final current = _requireUser();
    ensureValidHandle(handle);
    _currentUser = current.copyWith(
      displayName: displayName.trim(),
      handle: normalizeHandle(handle),
    );
    _authController.add(_currentUser);
    return _currentUser!;
  }

  @override
  Future<void> updateDefaultSendMode(SendMode sendMode) async {
    final current = _requireUser();
    _currentUser = current.copyWith(defaultSendMode: sendMode);
    _authController.add(_currentUser);
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
    final current = _requireUser();
    _currentUser = current.copyWith(
      calendarReminderEnabled: calendarReminderEnabled,
      calendarReminderLeadMinutes: calendarReminderLeadMinutes
          .clamp(0, 1440)
          .toInt(),
      morningBriefingEnabled: morningBriefingEnabled,
      morningBriefingMinuteOfDay: morningBriefingMinuteOfDay
          .clamp(0, 1439)
          .toInt(),
      calendarTimezone: timezone.trim().isEmpty ? 'Asia/Seoul' : timezone,
      holidayCountryCode: holidayCountryCode.trim().isEmpty
          ? 'KR'
          : holidayCountryCode.trim(),
    );
    _authController.add(_currentUser);
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final user = _requireUser();
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'user': {
        'uid': user.uid,
        'displayName': user.displayName,
        'handle': user.handle,
        'defaultSendMode': user.defaultSendMode.name,
      },
      'rooms': [
        for (final room in _rooms.where(
          (room) => room.participantIds.contains(user.uid),
        ))
          {
            'id': room.id,
            'type': room.type.name,
            'title': room.title,
            'participantIds': room.participantIds,
            'audioRetentionDays': room.audioRetentionDays,
            'messages': [
              for (final message in _messages[room.id] ?? const <ChatMessage>[])
                if (message.senderId == user.uid)
                  {
                    'id': message.id,
                    'kind': message.kind.name,
                    'text': message.text,
                    'transcript': message.transcript,
                    'createdAt': message.createdAt.toIso8601String(),
                  },
            ],
          },
      ],
      'blockedUsers': _blockedUsers.toList(growable: false),
      'reports': _reports
          .where((report) => report['reporterId'] == user.uid)
          .toList(growable: false),
    };
  }

  @override
  Future<Map<String, dynamic>> getOperationalHealth() async {
    return {
      'ok': true,
      'checkedAt': DateTime.now().toIso8601String(),
      'region': 'demo',
      'services': {
        'firestore': false,
        'storage': {'ok': false, 'name': 'demo', 'exists': false},
        'functions': false,
        'deepgram': {'configured': _transcriber != null, 'model': 'demo'},
        'translation': {
          'providerConfigured': false,
          'fallbackMode': 'free-preview',
        },
      },
      'policies': {
        'usageMode': 'unlimited',
        'textLimit': null,
        'voiceLimit': null,
        'defaultAudioRetentionDays': 1,
        'draftAudioRetentionDays': 1,
      },
      'usageToday': null,
      'latestRollup': null,
    };
  }

  @override
  Future<void> deleteAccount() async {
    final user = _requireUser();
    for (final timer in _scheduleTimers.values) {
      timer.cancel();
    }
    _scheduleTimers.clear();
    _rooms.removeWhere((room) => room.participantIds.contains(user.uid));
    for (final roomId in _messages.keys.toList(growable: false)) {
      _messages[roomId]?.removeWhere((message) => message.senderId == user.uid);
    }
    _blockedUsers.clear();
    _reports.removeWhere((report) => report['reporterId'] == user.uid);
    _calendarEvents.removeWhere((event) => event.ownerId == user.uid);
    _currentUser = null;
    _authController.add(null);
    _emitRooms();
    _emitCalendarEvents();
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _authController.add(null);
  }

  @override
  Stream<List<ChatRoom>> watchRooms(String uid) async* {
    yield List.unmodifiable(_rooms);
    yield* _roomController.stream;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) async* {
    yield List.unmodifiable(_messages[roomId] ?? const []);
    yield* _controllerForRoom(roomId).stream;
  }

  @override
  Stream<List<CalendarEvent>> watchCalendarEvents(String uid) async* {
    yield _sortedCalendarEvents();
    yield* _calendarController.stream;
  }

  @override
  Stream<List<RoomMember>> watchRoomMembers(String roomId) async* {
    yield List.unmodifiable(_activeMembers(roomId));
    yield* _controllerForMembers(roomId).stream;
  }

  @override
  Stream<List<RoomJoinRequest>> watchRoomJoinRequests(String roomId) async* {
    yield List.unmodifiable(_pendingJoinRequests(roomId));
    yield* _controllerForJoinRequests(roomId).stream;
  }

  @override
  Future<List<AppUser>> listUserDirectory({String query = ''}) async {
    final normalizedQuery = query.trim().toLowerCase();
    final contacts = const [
      AppUser(
        uid: 'friend-1',
        displayName: '김민지',
        handle: 'minji_kim',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-2',
        displayName: '이지훈',
        handle: 'jihoon_lee',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-3',
        displayName: '정유나',
        handle: 'yuna_jung',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-4',
        displayName: '최아린',
        handle: 'arin_choi',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-5',
        displayName: '박서준',
        handle: 'seojun_park',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-6',
        displayName: '한다은',
        handle: 'daeun_han',
        defaultSendMode: SendMode.confirm,
      ),
      AppUser(
        uid: 'friend-7',
        displayName: '한지수',
        handle: 'jisoo_han',
        defaultSendMode: SendMode.confirm,
      ),
    ];
    if (normalizedQuery.isEmpty) {
      return contacts;
    }
    return contacts
        .where(
          (contact) =>
              contact.displayName.toLowerCase().contains(normalizedQuery) ||
              contact.handle.toLowerCase().contains(normalizedQuery),
        )
        .toList();
  }

  @override
  Future<AppUser> addFriendByHandle({required String handle}) async {
    _requireUser();
    final normalizedHandle = normalizeHandle(handle);
    ensureValidHandle(normalizedHandle);
    final matches = await listUserDirectory(query: normalizedHandle);
    final friend = matches.firstWhere(
      (user) => user.handle == normalizedHandle,
      orElse: () => AppUser(
        uid: normalizedHandle,
        displayName: normalizedHandle,
        handle: normalizedHandle,
        defaultSendMode: SendMode.confirm,
      ),
    );
    if (friend.uid == _demoUid || friend.handle == _currentUser?.handle) {
      throw ArgumentError('자기 자신은 친구로 추가할 수 없습니다.');
    }
    _friendHandles.add(friend.handle);
    return friend;
  }

  @override
  Future<ChatRoom> createRoom({
    required List<String> participantHandles,
    required RoomType type,
    String? title,
  }) async {
    _requireUser();
    final normalizedHandles = normalizeAndValidateHandles(participantHandles);
    final fallbackTitle = type == RoomType.open
        ? '새 오픈채팅'
        : normalizedHandles.map((handle) => '@$handle').join(', ');
    final roomTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : fallbackTitle;
    final room = ChatRoom(
      id: _uuid.v4(),
      type: type,
      participantIds: [_demoUid, ...normalizedHandles],
      title: roomTitle,
      updatedAt: DateTime.now(),
      ownerId: _demoUid,
      memberRole: 'owner',
    );
    _rooms.insert(0, room);
    _messages[room.id] = [];
    _members[room.id] = [
      RoomMember(
        uid: _demoUid,
        role: RoomMemberRole.owner,
        joinedAt: DateTime.now(),
        displayName: _currentUser?.displayName,
        handle: _currentUser?.handle,
      ),
      for (final handle in normalizedHandles)
        RoomMember(
          uid: handle,
          role: RoomMemberRole.member,
          joinedAt: DateTime.now(),
          displayName: handle,
          handle: handle,
        ),
    ];
    _emitRooms();
    _emitMembers(room.id);
    return room;
  }

  @override
  Future<RoomInvite> createRoomInvite({
    required String roomId,
    bool approvalRequired = false,
  }) async {
    final user = _requireUser();
    _requireManager(roomId, user.uid);
    final token = _uuid.v4().replaceAll('-', '').substring(0, 12);
    final invite = RoomInvite(
      id: token,
      roomId: roomId,
      token: token,
      url: 'https://verbal.local/invite/$token',
      createdBy: user.uid,
      createdAt: DateTime.now(),
      approvalRequired: approvalRequired,
    );
    _invites[roomId] = invite;
    await setInviteApprovalRequired(
      roomId: roomId,
      approvalRequired: approvalRequired,
    );
    return invite;
  }

  @override
  Future<void> revokeRoomInvite({
    required String roomId,
    required String inviteId,
  }) async {
    final user = _requireUser();
    _requireManager(roomId, user.uid);
    final invite = _invites[roomId];
    if (invite == null || invite.id != inviteId) {
      return;
    }
    _invites[roomId] = RoomInvite(
      id: invite.id,
      roomId: invite.roomId,
      token: invite.token,
      url: invite.url,
      createdBy: invite.createdBy,
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
      revokedAt: DateTime.now(),
      approvalRequired: invite.approvalRequired,
    );
  }

  @override
  Future<void> setInviteApprovalRequired({
    required String roomId,
    required bool approvalRequired,
  }) async {
    final user = _requireUser();
    _requireManager(roomId, user.uid);
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(inviteApprovalRequired: approvalRequired),
    );
    final invite = _invites[roomId];
    if (invite != null) {
      _invites[roomId] = RoomInvite(
        id: invite.id,
        roomId: invite.roomId,
        token: invite.token,
        url: invite.url,
        createdBy: invite.createdBy,
        createdAt: invite.createdAt,
        expiresAt: invite.expiresAt,
        revokedAt: invite.revokedAt,
        approvalRequired: approvalRequired,
      );
    }
    _emitRooms();
  }

  @override
  Future<void> setRoomAudioRetention({
    required String roomId,
    required int days,
    required String preset,
  }) async {
    final user = _requireUser();
    _requireManager(roomId, user.uid);
    final clampedDays = days.clamp(1, 30).toInt();
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        audioRetentionDays: clampedDays,
        audioRetentionPreset: preset,
      ),
    );
    _emitRooms();
  }

  @override
  Future<InviteJoinResult> joinRoomByInvite({required String token}) async {
    final user = _requireUser();
    final normalizedToken = _inviteTokenFromInput(token);
    RoomInvite? invite;
    for (final candidate in _invites.values) {
      if (candidate.token == normalizedToken ||
          candidate.id == normalizedToken) {
        invite = candidate;
        break;
      }
    }
    if (invite == null || !invite.isActive) {
      throw StateError('Invite link is not valid.');
    }
    final roomIndex = _rooms.indexWhere((room) => room.id == invite!.roomId);
    if (roomIndex == -1) {
      throw StateError('Room not found.');
    }
    final room = _rooms[roomIndex];
    if (_activeMembers(room.id).any((member) => member.uid == user.uid)) {
      return InviteJoinResult(
        status: InviteJoinStatus.joined,
        roomId: room.id,
        room: room,
      );
    }
    if (invite.approvalRequired) {
      final requests = _joinRequests.putIfAbsent(room.id, () => []);
      final existing = requests.indexWhere(
        (request) => request.uid == user.uid,
      );
      final request = RoomJoinRequest(
        uid: user.uid,
        roomId: room.id,
        inviteId: invite.id,
        status: InviteJoinStatus.pending,
        createdAt: DateTime.now(),
        displayName: user.displayName,
        handle: user.handle,
      );
      if (existing == -1) {
        requests.add(request);
      } else {
        requests[existing] = request;
      }
      _emitJoinRequests(room.id);
      return InviteJoinResult(
        status: InviteJoinStatus.pending,
        roomId: room.id,
        requestId: user.uid,
      );
    }
    _addMemberToRoom(room.id, user);
    return InviteJoinResult(
      status: InviteJoinStatus.joined,
      roomId: room.id,
      room: _rooms.firstWhere((item) => item.id == room.id),
    );
  }

  @override
  Future<void> approveRoomJoinRequest({
    required String roomId,
    required String memberUid,
  }) async {
    final manager = _requireUser();
    _requireManager(roomId, manager.uid);
    RoomJoinRequest? request;
    for (final item in _joinRequests[roomId] ?? const <RoomJoinRequest>[]) {
      if (item.uid == memberUid && item.status == InviteJoinStatus.pending) {
        request = item;
        break;
      }
    }
    if (request == null) {
      throw StateError('Join request not found.');
    }
    _addMemberToRoom(
      roomId,
      AppUser(
        uid: memberUid,
        displayName: request.displayName ?? memberUid,
        handle: request.handle ?? memberUid,
        defaultSendMode: SendMode.confirm,
      ),
    );
    _joinRequests[roomId]?.removeWhere((item) => item.uid == memberUid);
    _emitJoinRequests(roomId);
  }

  @override
  Future<void> rejectRoomJoinRequest({
    required String roomId,
    required String memberUid,
  }) async {
    final manager = _requireUser();
    _requireManager(roomId, manager.uid);
    _joinRequests[roomId]?.removeWhere((item) => item.uid == memberUid);
    _emitJoinRequests(roomId);
  }

  @override
  Future<void> updateRoomMemberRole({
    required String roomId,
    required String memberUid,
    required RoomMemberRole role,
  }) async {
    final user = _requireUser();
    final currentRole = _requireManager(roomId, user.uid);
    if (currentRole != RoomMemberRole.owner && role == RoomMemberRole.owner) {
      throw StateError('Owner만 소유권을 넘길 수 있습니다.');
    }
    final roomMembers = _members[roomId];
    if (roomMembers == null) {
      throw StateError('Room not found.');
    }
    final index = roomMembers.indexWhere((member) => member.uid == memberUid);
    if (index == -1 || !roomMembers[index].active) {
      throw StateError('멤버를 찾을 수 없습니다.');
    }
    roomMembers[index] = RoomMember(
      uid: roomMembers[index].uid,
      role: role,
      joinedAt: roomMembers[index].joinedAt,
      displayName: roomMembers[index].displayName,
      handle: roomMembers[index].handle,
      leftAt: roomMembers[index].leftAt,
    );
    if (role == RoomMemberRole.owner) {
      for (var i = 0; i < roomMembers.length; i += 1) {
        if (i == index || roomMembers[i].role != RoomMemberRole.owner) {
          continue;
        }
        roomMembers[i] = RoomMember(
          uid: roomMembers[i].uid,
          role: RoomMemberRole.admin,
          joinedAt: roomMembers[i].joinedAt,
          displayName: roomMembers[i].displayName,
          handle: roomMembers[i].handle,
          leftAt: roomMembers[i].leftAt,
        );
      }
      _rooms.replaceWhere(
        (room) => room.id == roomId,
        (room) => room.copyWith(ownerId: memberUid),
      );
      _emitRooms();
    }
    _emitMembers(roomId);
  }

  @override
  Future<void> removeRoomMember({
    required String roomId,
    required String memberUid,
  }) async {
    final user = _requireUser();
    _requireManager(roomId, user.uid);
    if (memberUid == user.uid) {
      throw StateError('본인은 멤버 관리에서 제거할 수 없습니다.');
    }
    final roomMembers = _members[roomId];
    if (roomMembers == null) {
      throw StateError('Room not found.');
    }
    final index = roomMembers.indexWhere((member) => member.uid == memberUid);
    if (index == -1 || roomMembers[index].role == RoomMemberRole.owner) {
      throw StateError('제거할 수 없는 멤버입니다.');
    }
    roomMembers[index] = RoomMember(
      uid: roomMembers[index].uid,
      role: roomMembers[index].role,
      joinedAt: roomMembers[index].joinedAt,
      displayName: roomMembers[index].displayName,
      handle: roomMembers[index].handle,
      leftAt: DateTime.now(),
    );
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        participantIds: room.participantIds
            .where((participantId) => participantId != memberUid)
            .toList(growable: false),
      ),
    );
    _emitRooms();
    _emitMembers(roomId);
  }

  @override
  Future<void> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    _incrementTextUsage();
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: user.uid,
      kind: MessageKind.text,
      text: text.trim(),
      transcript: '',
      audioPath: null,
      durationMs: 0,
      sttStatus: SttStatus.none,
      sendMode: user.defaultSendMode,
      createdAt: DateTime.now(),
      replyTo: _replyForMessage(roomId, replyToMessageId),
    );
    _appendMessage(roomId, message, text.trim());
  }

  @override
  Future<void> scheduleTextMessage({
    required String roomId,
    required String text,
    required DateTime scheduledAt,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    _incrementTextUsage();
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: user.uid,
      kind: MessageKind.text,
      text: text.trim(),
      transcript: '',
      audioPath: null,
      durationMs: 0,
      sttStatus: SttStatus.none,
      sendMode: user.defaultSendMode,
      createdAt: DateTime.now(),
      replyTo: _replyForMessage(roomId, replyToMessageId),
      deliveryStatus: MessageDeliveryStatus.scheduled,
      scheduledAt: scheduledAt,
    );
    _appendMessage(roomId, message, '예약됨 ${text.trim()}');
    final delay = scheduledAt.difference(DateTime.now());
    _scheduleTimers[message.id]?.cancel();
    _scheduleTimers[message.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _deliverScheduledMessage(roomId, message.id),
    );
  }

  @override
  Future<void> sendScheduledMessageNow({
    required String roomId,
    required String messageId,
  }) async {
    _requireUser();
    _deliverScheduledMessage(roomId, messageId);
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
    final user = _requireUser();
    if (kind != MessageKind.image &&
        kind != MessageKind.file &&
        kind != MessageKind.location) {
      throw StateError('지원하지 않는 첨부 유형입니다.');
    }
    final uploadedAttachment = upload == null
        ? attachment
        : attachment.copyWith(
            title: upload.fileName,
            mimeType: upload.mimeType,
            sizeBytes: upload.sizeBytes,
          );
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: user.uid,
      kind: kind,
      text: caption.trim(),
      transcript: '',
      audioPath: null,
      durationMs: 0,
      sttStatus: SttStatus.none,
      sendMode: user.defaultSendMode,
      createdAt: DateTime.now(),
      replyTo: _replyForMessage(roomId, replyToMessageId),
      attachment: uploadedAttachment,
    );
    _appendMessage(
      roomId,
      message,
      caption.trim().isEmpty ? uploadedAttachment.preview : caption.trim(),
    );
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
    final user = _requireUser();
    final normalizedCandidates = _validProposalCandidates(candidates);
    final proposalId = _uuid.v4();
    final messageId = _uuid.v4();
    final now = DateTime.now();
    final proposal = CalendarProposal(
      id: proposalId,
      roomId: roomId,
      messageId: messageId,
      createdBy: user.uid,
      title: _validCalendarTitle(title),
      details: _validCalendarDetails(details),
      timezone: timezone,
      status: 'open',
      candidates: normalizedCandidates,
      votes: const {},
      source: source == 'voice' ? 'voice' : 'manual',
      transcript: transcript.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _calendarProposals[proposalId] = proposal;
    final message = ChatMessage(
      id: messageId,
      senderId: user.uid,
      kind: MessageKind.calendarProposal,
      text: proposal.title,
      transcript: proposal.transcript,
      audioPath: null,
      durationMs: 0,
      sttStatus: SttStatus.none,
      sendMode: user.defaultSendMode,
      createdAt: now,
      replyTo: _replyForMessage(roomId, replyToMessageId),
      calendarProposal: proposal,
    );
    _appendMessage(roomId, message, '일정 제안: ${proposal.title}');
  }

  @override
  Future<void> voteCalendarProposal({
    required String roomId,
    required String proposalId,
    required List<String> candidateIds,
  }) async {
    final user = _requireUser();
    final proposal = _proposalFor(roomId, proposalId);
    if (!proposal.isOpen) {
      throw StateError('확정 또는 취소된 일정 제안입니다.');
    }
    final validIds = proposal.candidates
        .map((candidate) => candidate.id)
        .toSet();
    final selected = candidateIds
        .where((id) => validIds.contains(id))
        .toSet()
        .toList(growable: false);
    final votes = Map<String, List<String>>.from(proposal.votes);
    votes[user.uid] = selected;
    _updateCalendarProposal(proposal.copyWith(votes: votes));
  }

  @override
  Future<void> finalizeCalendarProposal({
    required String roomId,
    required String proposalId,
    required String candidateId,
  }) async {
    final user = _requireUser();
    final proposal = _proposalFor(roomId, proposalId);
    if (proposal.createdBy != user.uid && !_isRoomManager(roomId, user.uid)) {
      throw StateError('일정 제안을 확정할 권한이 없습니다.');
    }
    final candidate = proposal.candidates.firstWhere(
      (candidate) => candidate.id == candidateId,
      orElse: () => throw StateError('후보 시간을 찾을 수 없습니다.'),
    );
    final voters = proposal.votes.entries
        .where((entry) => entry.value.contains(candidateId))
        .map((entry) => entry.key)
        .toSet();
    voters.add(proposal.createdBy);
    for (final ownerId in voters) {
      _addProposalEventForOwner(proposal, candidate, ownerId);
    }
    _updateCalendarProposal(
      proposal.copyWith(
        status: 'finalized',
        finalCandidateId: candidateId,
        updatedAt: DateTime.now(),
      ),
    );
    _emitCalendarEvents();
  }

  @override
  Future<void> addFinalizedProposalToMyCalendar({
    required String roomId,
    required String proposalId,
  }) async {
    final user = _requireUser();
    final proposal = _proposalFor(roomId, proposalId);
    final candidate = proposal.finalCandidate;
    if (!proposal.isFinalized || candidate == null) {
      throw StateError('확정된 일정만 추가할 수 있습니다.');
    }
    _addProposalEventForOwner(proposal, candidate, user.uid);
    _emitCalendarEvents();
  }

  @override
  Future<void> cancelCalendarProposal({
    required String roomId,
    required String proposalId,
  }) async {
    final user = _requireUser();
    final proposal = _proposalFor(roomId, proposalId);
    if (proposal.createdBy != user.uid && !_isRoomManager(roomId, user.uid)) {
      throw StateError('일정 제안을 취소할 권한이 없습니다.');
    }
    _updateCalendarProposal(
      proposal.copyWith(status: 'cancelled', updatedAt: DateTime.now()),
    );
  }

  @override
  Future<TranscriptionDraft> createTranscriptionDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  }) async {
    _requireUser();
    _incrementVoiceUsage(durationMs);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final transcript = transcriptOverride?.trim().isNotEmpty == true
        ? transcriptOverride!.trim()
        : await _transcribeOrFallback(
            audioFilePath: audioFilePath,
            durationMs: durationMs,
            language: language,
          );
    final draft = TranscriptionDraft(
      id: _uuid.v4(),
      audioPath: audioFilePath,
      transcript: transcript,
      status: SttStatus.completed,
      durationMs: durationMs,
    );
    _drafts[draft.id] = draft;
    return draft;
  }

  @override
  Future<CalendarIntentDraft> createCalendarIntentDraft({
    required String audioFilePath,
    required int durationMs,
    String language = 'ko-KR',
    String? transcriptOverride,
  }) async {
    _requireUser();
    _incrementVoiceUsage(durationMs);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final transcript = transcriptOverride?.trim().isNotEmpty == true
        ? transcriptOverride!.trim()
        : await _transcribeOrFallback(
            audioFilePath: audioFilePath,
            durationMs: durationMs,
            language: language,
          );
    return _parseCalendarIntent(transcript);
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
    final user = _requireUser();
    final event = CalendarEvent(
      id: _uuid.v4(),
      ownerId: user.uid,
      title: _validCalendarTitle(title),
      startAt: _validFutureStart(startAt),
      endAt: _validCalendarEnd(startAt, endAt),
      timezone: timezone,
      source: source == 'voice' ? 'voice' : 'manual',
      details: _validCalendarDetails(details),
      transcript: transcript,
      status: 'active',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _calendarEvents.add(event);
    _emitCalendarEvents();
    return event;
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
    final user = _requireUser();
    final index = _calendarEvents.indexWhere(
      (event) => event.id == eventId && event.ownerId == user.uid,
    );
    if (index == -1) {
      throw StateError('Calendar event not found.');
    }
    final previous = _calendarEvents[index];
    final event = CalendarEvent(
      id: previous.id,
      ownerId: previous.ownerId,
      title: _validCalendarTitle(title),
      startAt: _validFutureStart(startAt),
      endAt: _validCalendarEnd(startAt, endAt),
      timezone: timezone,
      source: previous.source,
      details: _validCalendarDetails(details),
      transcript: previous.transcript,
      status: previous.status,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now(),
      roomId: previous.roomId,
      proposalId: previous.proposalId,
      messageId: previous.messageId,
      candidateId: previous.candidateId,
    );
    _calendarEvents[index] = event;
    _emitCalendarEvents();
    return event;
  }

  @override
  Future<void> deleteCalendarEvent({required String eventId}) async {
    final user = _requireUser();
    _calendarEvents.removeWhere(
      (event) => event.id == eventId && event.ownerId == user.uid,
    );
    _emitCalendarEvents();
  }

  @override
  Future<void> sendVoiceMessage({
    required String roomId,
    required String draftId,
    required String finalText,
    required SendMode sendMode,
    String? replyToMessageId,
  }) async {
    final user = _requireUser();
    final draft = _drafts[draftId];
    if (draft == null) {
      throw StateError('Draft not found.');
    }
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: user.uid,
      kind: MessageKind.voice,
      text: finalText.trim(),
      transcript: draft.transcript,
      audioPath: draft.audioPath,
      audioExpiresAt: _audioExpiresAt(roomId),
      audioRetentionDays: _audioRetentionDays(roomId),
      audioRetentionStatus: 'active',
      durationMs: draft.durationMs,
      sttStatus: SttStatus.completed,
      sendMode: sendMode,
      createdAt: DateTime.now(),
      replyTo: _replyForMessage(roomId, replyToMessageId),
    );
    _appendMessage(roomId, message, finalText.trim());
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
    _incrementVoiceUsage(durationMs);
    final initialTranscript = transcriptOverride?.trim() ?? '';
    final message = ChatMessage(
      id: clientMessageId?.trim().isNotEmpty == true
          ? clientMessageId!.trim()
          : _uuid.v4(),
      senderId: user.uid,
      kind: MessageKind.voice,
      text: initialTranscript,
      transcript: initialTranscript,
      audioPath: audioFilePath,
      audioExpiresAt: _audioExpiresAt(roomId),
      audioRetentionDays: _audioRetentionDays(roomId),
      audioRetentionStatus: 'active',
      durationMs: durationMs,
      sttStatus: initialTranscript.isNotEmpty
          ? SttStatus.completed
          : SttStatus.processing,
      sendMode: sendMode,
      createdAt: DateTime.now(),
      replyTo: _replyForMessage(roomId, replyToMessageId),
    );
    _appendMessage(roomId, message, message.displayText);

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), () async {
        final roomMessages = _messages[roomId];
        if (roomMessages == null) {
          return;
        }
        final index = roomMessages.indexWhere((item) => item.id == message.id);
        if (index == -1) {
          return;
        }

        String transcript;
        SttStatus status;
        try {
          transcript =
              transcriptOverride?.trim().isNotEmpty == true &&
                  !forceServerSttCorrection
              ? transcriptOverride!.trim()
              : await _transcribeOrFallback(
                  audioFilePath: audioFilePath,
                  durationMs: durationMs,
                  language: language,
                );
          status = SttStatus.completed;
        } catch (_) {
          transcript = '';
          status = SttStatus.failed;
        }

        roomMessages[index] = roomMessages[index].copyWith(
          text: transcript,
          transcript: transcript,
          sttStatus: status,
        );
        _rooms.replaceWhere(
          (room) => room.id == roomId,
          (room) => room.copyWith(
            updatedAt: message.createdAt,
            lastMessage: LastMessage(
              kind: MessageKind.voice,
              preview: transcript.isEmpty
                  ? roomMessages[index].displayText
                  : transcript,
              senderId: message.senderId,
              createdAt: message.createdAt,
            ),
          ),
        );
        _emitRooms();
        _emitMessages(roomId);
      }),
    );
    return message.id;
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
    return;
  }

  @override
  Future<DeepgramStreamingToken?> createDeepgramStreamingToken({
    String language = 'ko-KR',
    String? provider,
  }) async {
    return null;
  }

  @override
  Future<VoiceInlineSttResult?> transcribeClientVoiceMessageInline({
    required String roomId,
    required String messageId,
    required Uint8List audioBytes,
    required String contentType,
    required int durationMs,
    String language = 'ko-KR',
  }) async {
    return null;
  }

  @override
  Future<VoiceInlineSttResult?> transcribeVoiceAudioDraft({
    required String roomId,
    required Uint8List audioBytes,
    required String contentType,
    required int durationMs,
    String language = 'ko-KR',
  }) async {
    return null;
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
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      return;
    }
    final index = roomMessages.indexWhere((item) => item.id == messageId);
    if (index == -1 || roomMessages[index].kind != MessageKind.voice) {
      return;
    }
    roomMessages[index] = roomMessages[index].copyWith(
      text: text,
      transcript: text,
      sttStatus: SttStatus.completed,
    );
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        lastMessage: LastMessage(
          kind: MessageKind.voice,
          preview: text,
          senderId: roomMessages[index].senderId,
          createdAt: roomMessages[index].createdAt,
        ),
      ),
    );
    _emitRooms();
    _emitMessages(roomId);
  }

  @override
  Future<void> recoverClientVoiceMessageTranscript({
    required String roomId,
    required String messageId,
  }) async {
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      return;
    }
    final index = roomMessages.indexWhere((item) => item.id == messageId);
    if (index == -1 || roomMessages[index].kind != MessageKind.voice) {
      return;
    }
    final current = roomMessages[index];
    if (current.voiceTranscriptText.trim().isNotEmpty) {
      return;
    }
    const transcript = '음성 변환을 다시 시도하고 있습니다.';
    roomMessages[index] = current.copyWith(
      text: transcript,
      transcript: transcript,
      sttStatus: SttStatus.completed,
    );
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        lastMessage: LastMessage(
          kind: MessageKind.voice,
          preview: transcript,
          senderId: current.senderId,
          createdAt: current.createdAt,
        ),
      ),
    );
    _emitRooms();
    _emitMessages(roomId);
  }

  @override
  Future<Uri?> audioUri(String? audioPath) async {
    return localAudioUri(audioPath);
  }

  @override
  Future<void> registerMessagingToken() async {}

  @override
  Future<void> editMessage({
    required String roomId,
    required String messageId,
    required String text,
  }) async {
    final user = _requireUser();
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      throw StateError('Room not found.');
    }
    final index = roomMessages.indexWhere((message) => message.id == messageId);
    if (index == -1 || roomMessages[index].senderId != user.uid) {
      throw StateError('수정할 수 없는 메시지입니다.');
    }
    final nextText = text.trim();
    if (nextText.isEmpty) {
      throw StateError('메시지를 입력하세요.');
    }
    roomMessages[index] = roomMessages[index].copyWith(
      text: nextText,
      editedAt: DateTime.now(),
    );
    if (index == roomMessages.length - 1) {
      _replaceRoomLastMessage(roomId, roomMessages[index], nextText);
    }
    _emitRooms();
    _emitMessages(roomId);
  }

  @override
  Future<void> deleteMessage({
    required String roomId,
    required String messageId,
  }) async {
    final user = _requireUser();
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      throw StateError('Room not found.');
    }
    final index = roomMessages.indexWhere((message) => message.id == messageId);
    if (index == -1 || roomMessages[index].senderId != user.uid) {
      throw StateError('삭제할 수 없는 메시지입니다.');
    }
    _scheduleTimers.remove(messageId)?.cancel();
    final wasLast = index == roomMessages.length - 1;
    roomMessages.removeAt(index);
    if (wasLast) {
      _refreshRoomLastMessageAfterRemoval(roomId);
    }
    _emitRooms();
    _emitMessages(roomId);
  }

  @override
  Future<void> reportMessage({
    required String roomId,
    required String messageId,
    required String reason,
  }) async {
    final user = _requireUser();
    final exists =
        _messages[roomId]?.any((message) => message.id == messageId) == true;
    if (!exists) {
      throw StateError('신고할 메시지를 찾을 수 없습니다.');
    }
    _reports.add({
      'reporterId': user.uid,
      'targetType': 'message',
      'roomId': roomId,
      'messageId': messageId,
      'reason': reason,
      'status': 'open',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> reportRoom({
    required String roomId,
    required String reason,
  }) async {
    final user = _requireUser();
    if (!_rooms.any((room) => room.id == roomId)) {
      throw StateError('신고할 대화를 찾을 수 없습니다.');
    }
    _reports.add({
      'reporterId': user.uid,
      'targetType': 'room',
      'roomId': roomId,
      'reason': reason,
      'status': 'open',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> blockUser({required String blockedUid, String? reason}) async {
    _requireUser();
    if (blockedUid == _demoUid) {
      throw StateError('자기 자신은 차단할 수 없습니다.');
    }
    _blockedUsers.add(blockedUid);
  }

  @override
  Future<void> leaveRoom({required String roomId}) async {
    _requireUser();
    _rooms.removeWhere((room) => room.id == roomId);
    _emitRooms();
  }

  @override
  Future<void> addReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    final user = _requireUser();
    final (messages, index) = _messageAt(roomId, messageId);
    final message = messages[index];
    if (message.isDeleted) {
      throw StateError('삭제된 메시지에는 반응할 수 없습니다.');
    }
    final reactions = _mutableReactions(message);
    final users = reactions.putIfAbsent(emoji, () => <String>[]);
    if (!users.contains(user.uid)) {
      users.add(user.uid);
    }
    messages[index] = message.copyWith(reactions: _freezeReactions(reactions));
    _emitMessages(roomId);
  }

  @override
  Future<void> removeReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    final user = _requireUser();
    final (messages, index) = _messageAt(roomId, messageId);
    final reactions = _mutableReactions(messages[index]);
    reactions[emoji]?.remove(user.uid);
    if (reactions[emoji]?.isEmpty == true) {
      reactions.remove(emoji);
    }
    messages[index] = messages[index].copyWith(
      reactions: _freezeReactions(reactions),
    );
    _emitMessages(roomId);
  }

  @override
  Future<MessageTranslation> translateMessage({
    required String roomId,
    required String messageId,
    String targetLanguage = 'en',
  }) async {
    _requireUser();
    final (messages, index) = _messageAt(roomId, messageId);
    final message = messages[index];
    if (message.isDeleted || message.displayText.trim().isEmpty) {
      throw StateError('번역할 수 있는 메시지가 없습니다.');
    }
    final normalizedTarget = targetLanguage.trim().isEmpty
        ? 'en'
        : targetLanguage.trim().toLowerCase();
    final translation = MessageTranslation(
      targetLanguage: normalizedTarget,
      text: _translateForDemo(message.displayText, normalizedTarget),
      createdAt: DateTime.now(),
    );
    final translations = Map<String, MessageTranslation>.from(
      message.translations,
    );
    translations[normalizedTarget] = translation;
    messages[index] = message.copyWith(
      translations: Map.unmodifiable(translations),
    );
    _emitMessages(roomId);
    return translation;
  }

  @override
  Future<void> pinMessage({
    required String roomId,
    required String messageId,
  }) async {
    final user = _requireUser();
    final (messages, index) = _messageAt(roomId, messageId);
    if (messages[index].isDeleted) {
      throw StateError('삭제된 메시지는 고정할 수 없습니다.');
    }
    messages[index] = messages[index].copyWith(
      pinnedAt: DateTime.now(),
      pinnedBy: user.uid,
    );
    _emitMessages(roomId);
  }

  @override
  Future<void> unpinMessage({
    required String roomId,
    required String messageId,
  }) async {
    final (messages, index) = _messageAt(roomId, messageId);
    messages[index] = messages[index].copyWith(clearPin: true);
    _emitMessages(roomId);
  }

  @override
  Future<void> markRoomRead({
    required String roomId,
    String? lastMessageId,
  }) async {
    _requireUser();
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(unreadCount: 0, lastReadAt: DateTime.now()),
    );
    _emitRooms();
  }

  @override
  Future<void> setRoomPinned({
    required String roomId,
    required bool pinned,
  }) async {
    _updateRoomState(roomId, pinned: pinned);
  }

  @override
  Future<void> setRoomArchived({
    required String roomId,
    required bool archived,
  }) async {
    _updateRoomState(roomId, archived: archived);
  }

  @override
  Future<void> setRoomMuted({
    required String roomId,
    required bool muted,
  }) async {
    _updateRoomState(roomId, muted: muted);
  }

  CalendarIntentDraft _parseCalendarIntent(String transcript) {
    final now = DateTime.now();
    final text = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
    int? year;
    if (text.contains('올해')) {
      year = now.year;
    } else if (text.contains('내년')) {
      year = now.year + 1;
    } else {
      final yearMatch = RegExp(r'(\d{4})\s*년').firstMatch(text);
      year = int.tryParse(yearMatch?.group(1) ?? '');
    }
    final month = _readCalendarUnit(text, '월');
    final day = _readCalendarUnit(text, '일');
    final time = _readCalendarTime(text);
    final title = _readCalendarTitle(text);
    DateTime? startAt;
    DateTime? endAt;
    if (year != null && month != null && day != null && time != null) {
      startAt = DateTime(year, month, day, time.$1, time.$2);
      endAt = startAt.add(const Duration(hours: 1));
    }
    final missing = <String>[
      if (year == null) 'year',
      if (month == null || day == null) 'date',
      if (time == null) 'time',
      if (title == null) 'title',
    ];
    return CalendarIntentDraft(
      id: _uuid.v4(),
      transcript: transcript,
      parsedTitle: title,
      startAt: startAt,
      endAt: endAt,
      timezone: 'Asia/Seoul',
      missingFields: missing,
    );
  }

  int? _readCalendarUnit(String text, String unit) {
    final match = RegExp('(\\d{1,2})\\s*$unit').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  (int, int)? _readCalendarTime(String text) {
    final match = RegExp(
      r'(오전|오후|아침|저녁|밤|낮)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?(?:에)?',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }
    final period = match.group(1) ?? '';
    var hour = int.tryParse(match.group(2) ?? '');
    final minute = int.tryParse(match.group(3) ?? '0') ?? 0;
    if (hour == null) {
      return null;
    }
    if ((period == '오후' || period == '저녁' || period == '밤') && hour < 12) {
      hour += 12;
    }
    if ((period == '오전' || period == '아침') && hour == 12) {
      hour = 0;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return (hour, minute);
  }

  String? _readCalendarTitle(String text) {
    final match = RegExp(
      r'(?:오전|오후|아침|저녁|밤|낮)?\s*\d{1,2}\s*시(?:\s*\d{1,2}\s*분)?(?:에)?\s*(.+)$',
    ).firstMatch(text);
    final raw = match?.group(1)?.trim() ?? '';
    final title = raw
        .replaceAll(
          RegExp(
            r'\s*(이라는|라는|로|으로)?\s*(일정|약속|스케줄)\s*(을|를)?\s*(추가|등록|저장|만들어|잡아|생성).*$',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*(일정|약속|스케줄)\s*$'), '')
        .trim();
    if (title.isEmpty || title.length > 120) {
      return null;
    }
    return title;
  }

  String _validCalendarTitle(String title) {
    final next = title.trim();
    if (next.isEmpty || next.length > 120) {
      throw StateError('Calendar title must be 1-120 characters.');
    }
    return next;
  }

  String _validCalendarDetails(String details) {
    final next = details.trim();
    if (next.length > 2000) {
      throw StateError('Calendar details must be 2000 characters or fewer.');
    }
    return next;
  }

  List<CalendarProposalCandidate> _validProposalCandidates(
    List<CalendarProposalCandidate> candidates,
  ) {
    if (candidates.isEmpty || candidates.length > 5) {
      throw StateError('일정 후보는 1~5개까지 등록할 수 있습니다.');
    }
    final seen = <String>{};
    final normalized = <CalendarProposalCandidate>[];
    for (var i = 0; i < candidates.length; i++) {
      final id = candidates[i].id.trim().isEmpty
          ? 'candidate_${i + 1}'
          : candidates[i].id.trim();
      if (seen.contains(id)) {
        throw StateError('일정 후보 ID가 중복되었습니다.');
      }
      seen.add(id);
      normalized.add(
        CalendarProposalCandidate(
          id: id,
          startAt: _validFutureStart(candidates[i].startAt),
          endAt: _validCalendarEnd(candidates[i].startAt, candidates[i].endAt),
        ),
      );
    }
    return normalized;
  }

  CalendarProposal _proposalFor(String roomId, String proposalId) {
    final proposal = _calendarProposals[proposalId];
    if (proposal == null || proposal.roomId != roomId) {
      throw StateError('일정 제안을 찾을 수 없습니다.');
    }
    return proposal;
  }

  bool _isRoomManager(String roomId, String uid) {
    final members = _members[roomId] ?? const <RoomMember>[];
    for (final member in members) {
      if (member.uid == uid && member.active) {
        return member.role.canManageRoom;
      }
    }
    return false;
  }

  void _updateCalendarProposal(CalendarProposal proposal) {
    _calendarProposals[proposal.id] = proposal;
    final roomMessages = _messages[proposal.roomId];
    if (roomMessages == null) {
      return;
    }
    final index = roomMessages.indexWhere(
      (message) => message.id == proposal.messageId,
    );
    if (index == -1) {
      return;
    }
    roomMessages[index] = roomMessages[index].copyWith(
      text: proposal.title,
      transcript: proposal.transcript,
      calendarProposal: proposal,
    );
    _emitMessages(proposal.roomId);
  }

  void _addProposalEventForOwner(
    CalendarProposal proposal,
    CalendarProposalCandidate candidate,
    String ownerId,
  ) {
    final exists = _calendarEvents.any(
      (event) =>
          event.ownerId == ownerId &&
          event.proposalId == proposal.id &&
          event.candidateId == candidate.id,
    );
    if (exists) {
      return;
    }
    _calendarEvents.add(
      CalendarEvent(
        id: _uuid.v4(),
        ownerId: ownerId,
        title: proposal.title,
        startAt: candidate.startAt,
        endAt: candidate.endAt,
        timezone: proposal.timezone,
        source: 'chatProposal',
        details: proposal.details,
        transcript: proposal.transcript,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        roomId: proposal.roomId,
        proposalId: proposal.id,
        messageId: proposal.messageId,
        candidateId: candidate.id,
      ),
    );
  }

  DateTime _validFutureStart(DateTime startAt) {
    if (!startAt.isAfter(DateTime.now())) {
      throw StateError('Calendar event start time must be in the future.');
    }
    return startAt;
  }

  DateTime _validCalendarEnd(DateTime startAt, DateTime endAt) {
    if (!endAt.isAfter(startAt)) {
      throw StateError('Calendar event end time must be after start time.');
    }
    return endAt;
  }

  Future<String> _transcribeOrFallback({
    required String audioFilePath,
    required int durationMs,
    required String language,
  }) async {
    final transcriber = _transcriber;
    if (transcriber == null) {
      throw StateError(
        'STT 엔진이 연결되어 있지 않습니다. 무료 브라우저 STT 또는 Deepgram STT 모드로 실행해 주세요.',
      );
    }
    final transcript = await transcriber(
      audioFilePath: audioFilePath,
      durationMs: durationMs,
      language: language,
    );
    if (transcript.trim().isEmpty) {
      throw StateError('음성 변환 결과가 비어 있습니다.');
    }
    return transcript.trim();
  }

  void _incrementTextUsage() {
    // Demo mode keeps usage unlimited, matching production behavior.
  }

  void _incrementVoiceUsage(int durationMs) {
    if (durationMs < 500) {
      throw StateError('음성 메시지는 최소 0.5초 이상이어야 합니다.');
    }
  }

  int _audioRetentionDays(String roomId) {
    final room = _rooms.where((room) => room.id == roomId);
    if (room.isEmpty) {
      return 1;
    }
    return room.first.audioRetentionDays.clamp(1, 30).toInt();
  }

  DateTime _audioExpiresAt(String roomId) {
    return DateTime.now().add(Duration(days: _audioRetentionDays(roomId)));
  }

  AppUser _requireUser() {
    final user = _currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }
    return user;
  }

  StreamController<List<ChatMessage>> _controllerForRoom(String roomId) {
    return _messageControllers.putIfAbsent(
      roomId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
  }

  StreamController<List<RoomMember>> _controllerForMembers(String roomId) {
    return _memberControllers.putIfAbsent(
      roomId,
      () => StreamController<List<RoomMember>>.broadcast(),
    );
  }

  StreamController<List<RoomJoinRequest>> _controllerForJoinRequests(
    String roomId,
  ) {
    return _joinRequestControllers.putIfAbsent(
      roomId,
      () => StreamController<List<RoomJoinRequest>>.broadcast(),
    );
  }

  void _appendMessage(String roomId, ChatMessage message, String preview) {
    final roomMessages = _messages.putIfAbsent(roomId, () => []);
    roomMessages.add(message);
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        updatedAt: message.createdAt,
        lastMessage: LastMessage(
          kind: message.kind,
          preview: preview,
          senderId: message.senderId,
          createdAt: message.createdAt,
        ),
        unreadCount: message.senderId == _demoUid ? 0 : room.unreadCount + 1,
        lastReadAt: message.senderId == _demoUid
            ? message.createdAt
            : room.lastReadAt,
      ),
    );
    _rooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _emitRooms();
    _emitMessages(roomId);
  }

  void _deliverScheduledMessage(String roomId, String messageId) {
    _scheduleTimers.remove(messageId)?.cancel();
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      return;
    }
    final index = roomMessages.indexWhere((message) => message.id == messageId);
    if (index == -1 || roomMessages[index].isDeleted) {
      return;
    }
    final message = roomMessages[index];
    if (!message.isScheduled) {
      return;
    }
    roomMessages[index] = message.copyWith(
      deliveryStatus: MessageDeliveryStatus.sent,
    );
    _replaceRoomLastMessage(roomId, roomMessages[index], message.displayText);
    _emitRooms();
    _emitMessages(roomId);
  }

  void _emitRooms() {
    _roomController.add(List.unmodifiable(_rooms));
  }

  void _emitMessages(String roomId) {
    _controllerForRoom(
      roomId,
    ).add(List.unmodifiable(_messages[roomId] ?? const []));
  }

  void _emitMembers(String roomId) {
    _controllerForMembers(
      roomId,
    ).add(List.unmodifiable(_activeMembers(roomId)));
  }

  void _emitJoinRequests(String roomId) {
    _controllerForJoinRequests(
      roomId,
    ).add(List.unmodifiable(_pendingJoinRequests(roomId)));
  }

  void _emitCalendarEvents() {
    _calendarController.add(_sortedCalendarEvents());
  }

  List<CalendarEvent> _sortedCalendarEvents() {
    final events = _calendarEvents
        .where((event) => event.status == 'active')
        .toList(growable: false);
    events.sort((a, b) => a.startAt.compareTo(b.startAt));
    return List.unmodifiable(events);
  }

  List<RoomMember> _activeMembers(String roomId) {
    return (_members[roomId] ?? const <RoomMember>[])
        .where((member) => member.active)
        .toList(growable: false);
  }

  List<RoomJoinRequest> _pendingJoinRequests(String roomId) {
    return (_joinRequests[roomId] ?? const <RoomJoinRequest>[])
        .where((request) => request.status == InviteJoinStatus.pending)
        .toList(growable: false);
  }

  void _addMemberToRoom(String roomId, AppUser user) {
    final roomMembers = _members.putIfAbsent(roomId, () => []);
    final memberIndex = roomMembers.indexWhere(
      (member) => member.uid == user.uid,
    );
    final member = RoomMember(
      uid: user.uid,
      role: RoomMemberRole.member,
      joinedAt: DateTime.now(),
      displayName: user.displayName,
      handle: user.handle,
    );
    if (memberIndex == -1) {
      roomMembers.add(member);
    } else {
      roomMembers[memberIndex] = member;
    }
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        participantIds: {
          ...room.participantIds,
          user.uid,
        }.toList(growable: false),
        updatedAt: DateTime.now(),
      ),
    );
    _emitRooms();
    _emitMembers(roomId);
  }

  RoomMemberRole _requireManager(String roomId, String uid) {
    final role = _memberRole(roomId, uid);
    if (!role.canManageRoom) {
      throw StateError('관리자 권한이 필요합니다.');
    }
    return role;
  }

  RoomMemberRole _memberRole(String roomId, String uid) {
    RoomMember? member;
    for (final item in _members[roomId] ?? const <RoomMember>[]) {
      if (item.uid == uid && item.active) {
        member = item;
        break;
      }
    }
    if (member == null) {
      throw StateError('대화방 멤버가 아닙니다.');
    }
    return member.role;
  }

  MessageReply? _replyForMessage(String roomId, String? messageId) {
    if (messageId == null) {
      return null;
    }
    final message = _messages[roomId]?.where((item) => item.id == messageId);
    if (message == null || message.isEmpty) {
      return null;
    }
    final target = message.first;
    return MessageReply(
      messageId: target.id,
      senderId: target.senderId,
      preview: target.displayText,
    );
  }

  void _replaceRoomLastMessage(
    String roomId,
    ChatMessage message,
    String preview,
  ) {
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        updatedAt: DateTime.now(),
        lastMessage: LastMessage(
          kind: message.kind,
          preview: preview,
          senderId: message.senderId,
          createdAt: message.createdAt,
        ),
      ),
    );
  }

  void _refreshRoomLastMessageAfterRemoval(String roomId) {
    final roomMessages = _messages[roomId] ?? const <ChatMessage>[];
    if (roomMessages.isEmpty) {
      _clearRoomLastMessage(roomId);
      return;
    }
    final latest = roomMessages.last;
    _replaceRoomLastMessage(roomId, latest, latest.displayText);
  }

  void _clearRoomLastMessage(String roomId) {
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) =>
          room.copyWith(updatedAt: DateTime.now(), clearLastMessage: true),
    );
  }

  void _updateRoomState(
    String roomId, {
    bool? pinned,
    bool? archived,
    bool? muted,
  }) {
    _requireUser();
    _rooms.replaceWhere(
      (room) => room.id == roomId,
      (room) => room.copyWith(
        pinned: pinned ?? room.pinned,
        archived: archived ?? room.archived,
        muted: muted ?? room.muted,
      ),
    );
    _rooms.sort((a, b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    _emitRooms();
  }

  (List<ChatMessage>, int) _messageAt(String roomId, String messageId) {
    final roomMessages = _messages[roomId];
    if (roomMessages == null) {
      throw StateError('대화를 찾을 수 없습니다.');
    }
    final index = roomMessages.indexWhere((message) => message.id == messageId);
    if (index == -1) {
      throw StateError('메시지를 찾을 수 없습니다.');
    }
    return (roomMessages, index);
  }

  Map<String, List<String>> _mutableReactions(ChatMessage message) {
    return {
      for (final entry in message.reactions.entries)
        entry.key: entry.value.toList(),
    };
  }

  Map<String, List<String>> _freezeReactions(
    Map<String, List<String>> reactions,
  ) {
    final frozen = <String, List<String>>{};
    for (final entry in reactions.entries) {
      frozen[entry.key] = List<String>.unmodifiable(entry.value);
    }
    return Map<String, List<String>>.unmodifiable(frozen);
  }

  String _translateForDemo(String source, String targetLanguage) {
    if (targetLanguage == 'ko' || targetLanguage == 'ko-kr') {
      return source;
    }
    final normalized = source.trim();
    final dictionary = <String, String>{
      'Can we talk this evening?': 'Can we talk this evening?',
      'Yes, 8 PM works for me.': 'Yes, 8 PM works for me.',
      'Scheduled': 'Scheduled',
      'This message was deleted.': 'This message was deleted.',
      'Photo': 'Photo',
      'File': 'File',
      'Location': 'Location',
    };
    for (final entry in dictionary.entries) {
      if (normalized == entry.key) {
        return entry.value;
      }
    }
    return targetLanguage == 'en'
        ? 'English draft: $normalized'
        : '${targetLanguage.toUpperCase()}: $normalized';
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
}

extension _ReplaceWhere<T> on List<T> {
  void replaceWhere(bool Function(T item) test, T Function(T item) update) {
    for (var i = 0; i < length; i += 1) {
      if (test(this[i])) {
        this[i] = update(this[i]);
        return;
      }
    }
  }
}
