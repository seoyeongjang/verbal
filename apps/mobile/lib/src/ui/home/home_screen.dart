import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/messenger_models.dart';
import '../../services/app_preferences.dart';
import '../../services/handle_policy.dart';
import '../../services/messenger_backend.dart';
import '../../services/telemetry_service.dart';
import '../calendar/calendar_screen.dart';
import '../chat/chat_screen.dart';
import '../shared/profile_avatar.dart';

const _kMuted = Color(0xFF8E8E93);
const _kSoft = Color(0xFFF2F2F5);
const _kSelectedGreen = Color(0xFFE2FAEE);
const _kAccentGreen = Color(0xFF00A86B);
const _kActionRed = Color(0xFFFF3040);
const _kLogoBlack = Color(0xFF111111);
const _kHomeInk = Color(0xFFF7F7F8);
const _kHomeMuted = Color(0xFFB7BBC3);
const _kHomeSurface = Color(0xFF1C1C1E);
const _kHomeSoft = Color(0xFF27282B);
const _kHomeBorder = Color(0xFF34363A);
const _kHomeSelectedGreen = Color(0xFF103C2B);
const _kHomeActionSurface = Color(0xFF2B2D30);

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _InboxTab {
  messages('메시지'),
  channels('채널'),
  requests('요청 메시지');

  const _InboxTab(this.label);

  final String label;
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = _InboxTab.messages;

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      backgroundColor: _kLogoBlack,
      body: Column(
        children: [
          const _FakeStatusBar(),
          _DirectHeader(
            user: widget.user,
            onMenu: () => _showSettings(context),
            onSearch: () => _showGlobalSearch(context),
            onCalendar: () => _openCalendar(context),
            onCompose: () => _showNewRoomSheet(context),
          ),
          _NotesRail(user: widget.user),
          _InboxTabs(
            selected: _tab,
            onSelected: (tab) => setState(() => _tab = tab),
          ),
          Expanded(
            child: StreamBuilder<List<ChatRoom>>(
              stream: backend.watchRooms(widget.user.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorState(
                    message: '연결이 불안정합니다. 네트워크를 확인한 뒤 다시 시도해 주세요.',
                    detail: snapshot.error.toString(),
                    onRetry: () => setState(() {}),
                  );
                }
                final rooms = _filteredRooms(
                  snapshot.data ?? const <ChatRoom>[],
                );
                if (snapshot.connectionState == ConnectionState.waiting &&
                    rooms.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rooms.isEmpty) {
                  return _EmptyRooms(tab: _tab);
                }
                final adIndex = rooms.length > 1 ? 1 : rooms.length;
                final showRevenueTile = _tab != _InboxTab.requests;
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 20),
                  itemCount: rooms.length + (showRevenueTile ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (showRevenueTile && index == adIndex) {
                      return _RevenueTile(tab: _tab);
                    }
                    final roomIndex = showRevenueTile && index > adIndex
                        ? index - 1
                        : index;
                    final room = rooms[roomIndex];
                    return _SwipeRoomTile(
                      room: room,
                      user: widget.user,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatScreen(room: room, user: widget.user),
                          ),
                        );
                      },
                      onPin: () => _setRoomPinned(room),
                      onMute: () => _setRoomMuted(room),
                      onDelete: () => _deleteRoom(room),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ChatRoom> _filteredRooms(List<ChatRoom> rooms) {
    return rooms.where((room) {
      return switch (_tab) {
        _InboxTab.messages => !room.archived && room.type != RoomType.group,
        _InboxTab.channels => !room.archived && room.type == RoomType.group,
        _InboxTab.requests => room.archived,
      };
    }).toList();
  }

  void _showNewRoomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => NewRoomSheet(user: widget.user),
    );
  }

  void _openCalendar(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CalendarScreen(user: widget.user)),
    );
  }

  void _showGlobalSearch(BuildContext context) {
    final backend = BackendScope.of(context);
    unawaited(AppTelemetry.logEvent('global_search_used'));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return _GlobalSearchSheet(
          user: widget.user,
          backend: backend,
          onOpenRoom: (room) {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(room: room, user: widget.user),
              ),
            );
          },
          onOpenCalendar: () {
            Navigator.of(sheetContext).pop();
            _openCalendar(context);
          },
        );
      },
    );
  }

  Future<void> _setRoomPinned(ChatRoom room) async {
    await BackendScope.of(
      context,
    ).setRoomPinned(roomId: room.id, pinned: !room.pinned);
  }

  Future<void> _setRoomMuted(ChatRoom room) async {
    await BackendScope.of(
      context,
    ).setRoomMuted(roomId: room.id, muted: !room.muted);
  }

  Future<void> _deleteRoom(ChatRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('대화 삭제'),
          content: Text('${room.title} 대화를 목록에서 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await BackendScope.of(context).leaveRoom(roomId: room.id);
    }
  }

  void _showSettings(BuildContext context) {
    final backend = BackendScope.of(context);
    final isGuestSession = !backend.isConfigured;
    final userProfile = contactProfileForLabel(
      widget.user.handle.trim().isEmpty
          ? widget.user.displayName
          : widget.user.handle,
    );
    void closeAndRun(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _kSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _StoryAvatar(
                        label: userProfile.displayName,
                        size: 48,
                        avatarAsset: userProfile.avatarAsset,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userProfile.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '@${widget.user.handle}',
                              style: const TextStyle(color: _kMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _MenuSection(
                    title: '계정/관계',
                    children: [
                      _MenuTile(
                        icon: Icons.person_outline_rounded,
                        title: '내 프로필',
                        subtitle: '표시명, 아이디, 공개 범위',
                        onTap: () {
                          closeAndRun(() => _showProfileSettings(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.contacts_outlined,
                        title: '친구/연락처',
                        subtitle: '친구 추가, 연락처 동기화, 차단 목록',
                        onTap: () {
                          closeAndRun(
                            () => _showContactsSettings(this.context),
                          );
                        },
                      ),
                      _MenuTile(
                        icon: Icons.bookmark_border_rounded,
                        title: '저장한 메시지',
                        subtitle: '나에게 보내는 개인 저장함',
                        onTap: () {
                          closeAndRun(() => _showSavedMessages(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.manage_accounts_outlined,
                        title: '계정 관리',
                        subtitle: '전화번호, 로그인 기기, 인증 관리',
                        onTap: () {
                          closeAndRun(
                            () => _showAccountManagementSettings(this.context),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MenuSection(
                    title: '대화/데이터',
                    children: [
                      _MenuTile(
                        icon: Icons.storage_rounded,
                        title: '데이터 및 저장 공간',
                        subtitle: '음성 보존, 캐시, 저장공간 관리',
                        onTap: () {
                          closeAndRun(
                            () => _showDataStorageSettings(this.context),
                          );
                        },
                      ),
                      _MenuTile(
                        icon: Icons.backup_outlined,
                        title: '대화 백업 및 복원',
                        subtitle: '텍스트, 캘린더, 기기 변경 복원',
                        onTap: () {
                          closeAndRun(
                            () => _showChatBackupSettings(this.context),
                          );
                        },
                      ),
                      _MenuTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: '권한 관리',
                        subtitle: '마이크, 알림, 연락처, 위치, 파일',
                        onTap: () {
                          closeAndRun(
                            () => _showPermissionSettings(this.context),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MenuSection(
                    title: '설정',
                    children: [
                      _MenuTile(
                        icon: Icons.notifications_none_rounded,
                        title: '알림 설정',
                        subtitle: '메시지, 요청, 캘린더 알림',
                        onTap: () {
                          closeAndRun(
                            () => _showNotificationSettings(this.context),
                          );
                        },
                      ),
                      _MenuTile(
                        icon: Icons.lock_outline_rounded,
                        title: '개인정보 및 보안',
                        subtitle: '요청 메시지, 차단, 세션 관리',
                        onTap: () {
                          closeAndRun(() => _showPrivacySettings(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.translate_rounded,
                        title: '언어',
                        subtitle: AppPreferenceScope.of(context).language.label,
                        onTap: () {
                          closeAndRun(
                            () => _showLanguageSettings(this.context),
                          );
                        },
                      ),
                      _MenuTile(
                        icon: Icons.dark_mode_outlined,
                        title: '테마',
                        subtitle: AppPreferenceScope.of(
                          context,
                        ).themeChoice.label,
                        onTap: () {
                          closeAndRun(() => _showThemeSettings(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.format_size_rounded,
                        title: '폰트 크기',
                        subtitle: AppPreferenceScope.of(
                          context,
                        ).fontSizeChoice.label,
                        onTap: () {
                          closeAndRun(
                            () => _showFontSizeSettings(this.context),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MenuSection(
                    title: '안전/지원',
                    children: [
                      _MenuTile(
                        icon: Icons.health_and_safety_outlined,
                        title: '안전센터',
                        subtitle: '차단, 신고 내역, 스팸/사칭 신고',
                        onTap: () {
                          closeAndRun(() => _showSafetyCenter(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.support_agent_rounded,
                        title: '고객지원',
                        subtitle: '문의, 계정 문제, 음성 인식 오류 신고',
                        onTap: () {
                          closeAndRun(() => _showSupportCenter(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.campaign_outlined,
                        title: '공지사항',
                        subtitle: '업데이트, 점검, 정책 변경 안내',
                        onTap: () {
                          closeAndRun(() => _showAnnouncements(this.context));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MenuSection(
                    title: '정보/정책',
                    children: [
                      _MenuTile(
                        icon: Icons.policy_outlined,
                        title: '약관 및 정책',
                        subtitle: '이용약관, 개인정보, 커뮤니티 정책',
                        onTap: () {
                          closeAndRun(() => _showLegalPolicy(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.info_outline_rounded,
                        title: '앱 정보',
                        subtitle: '버전, 빌드, 서비스 정보',
                        onTap: () {
                          closeAndRun(() => _showAppInfo(this.context));
                        },
                      ),
                      _MenuTile(
                        icon: Icons.code_rounded,
                        title: '오픈소스 라이선스',
                        subtitle: '사용 중인 패키지와 라이선스',
                        onTap: () {
                          closeAndRun(
                            () => _showOpenSourceLicenses(this.context),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MenuSection(
                    title: '계정 상태',
                    children: [
                      _MenuTile(
                        icon: isGuestSession
                            ? Icons.login_rounded
                            : Icons.logout_rounded,
                        title: isGuestSession ? '로그인' : '로그아웃',
                        subtitle: isGuestSession
                            ? '데모 세션을 종료하고 로그인 화면으로 이동'
                            : '현재 계정에서 로그아웃',
                        onTap: () => _confirmSignOut(context, isGuestSession),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showProfileSettings(BuildContext context) {
    final userProfile = contactProfileForLabel(
      widget.user.handle.trim().isEmpty
          ? widget.user.displayName
          : widget.user.handle,
    );
    final displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    final handleController = TextEditingController(text: widget.user.handle);
    var visibility = '친구만';
    var saving = false;
    String? error;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveProfile() async {
              final displayName = displayNameController.text.trim();
              final handle = normalizeHandle(handleController.text);
              if (displayName.isEmpty) {
                setSheetState(() => error = '닉네임을 입력하세요.');
                return;
              }
              final handleError = validateHandle(handle);
              if (handleError != null) {
                setSheetState(() => error = handleError);
                return;
              }
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                await BackendScope.of(
                  context,
                ).saveProfile(displayName: displayName, handle: handle);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(
                    this.context,
                  ).showSnackBar(const SnackBar(content: Text('프로필을 저장했습니다.')));
                }
              } catch (saveError) {
                if (context.mounted) {
                  setSheetState(() {
                    saving = false;
                    error = saveError.toString();
                  });
                }
              }
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _kSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '내 프로필',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _StoryAvatar(
                          label: userProfile.displayName,
                          size: 64,
                          avatarAsset: userProfile.avatarAsset,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userProfile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '@${widget.user.handle}',
                                style: const TextStyle(
                                  color: _kMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('profile-display-name-field'),
                      controller: displayNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '닉네임',
                        hintText: '표시할 이름',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('profile-handle-field'),
                      controller: handleController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'User ID',
                        hintText: '예: minji_123',
                        helperText: '한글, 영어, 일본어, 중국어, 숫자, _ 3~30자',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _InfoRow(label: '프로필 이미지', value: '이니셜 아바타 사용 중'),
                    const _InfoRow(label: '상태 메시지', value: '필요 시 직접 입력'),
                    const SizedBox(height: 12),
                    const Text(
                      '프로필 공개 범위',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '전체', label: Text('전체')),
                        ButtonSegment(value: '친구만', label: Text('친구만')),
                        ButtonSegment(value: '비공개', label: Text('비공개')),
                      ],
                      selected: {visibility},
                      onSelectionChanged: (value) {
                        setSheetState(() => visibility = value.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    _SettingTile(
                      icon: Icons.qr_code_2_rounded,
                      title: '초대 링크/QR',
                      subtitle: '내 프로필 링크를 공유해 친구를 초대합니다.',
                      onTap: () => _showProfileInvite(context),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: saving ? null : saveProfile,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('저장'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileInvite(BuildContext context) {
    final profileLink = 'https://verbal.local/profile/${widget.user.handle}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _kSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '초대 링크/QR',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  '친구가 링크나 QR로 내 프로필을 열고 대화를 시작할 수 있습니다.',
                  style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8E8EC)),
                    ),
                    child: QrImageView(
                      data: profileLink,
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    profileLink,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: profileLink));
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('초대 링크를 복사했습니다.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('링크 복사'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showContactsSettings(BuildContext context) {
    var syncContacts = false;
    var hideSuggestions = true;
    _showMenuDetailSheet(
      context,
      title: '친구/연락처',
      children: [
        _SettingTile(
          icon: Icons.people_outline_rounded,
          title: '친구 목록',
          subtitle: '현재 대화 가능한 친구를 확인합니다.',
        ),
        const _AddFriendSettingTile(),
        StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: syncContacts,
                  onChanged: (value) =>
                      setSheetState(() => syncContacts = value),
                  title: const Text('연락처 동기화'),
                  subtitle: const Text('기기 연락처로 친구를 찾습니다.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: hideSuggestions,
                  onChanged: (value) =>
                      setSheetState(() => hideSuggestions = value),
                  title: const Text('추천 친구 숨김'),
                  subtitle: const Text('알 수도 있는 사람 추천을 숨깁니다.'),
                ),
              ],
            );
          },
        ),
        _SettingTile(
          icon: Icons.block_rounded,
          title: '차단 목록',
          subtitle: '차단한 사용자를 확인하고 해제합니다.',
        ),
      ],
    );
  }

  void _showSavedMessages(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '저장한 메시지',
      children: const [
        _EmptyDetailState(
          icon: Icons.bookmark_border_rounded,
          title: '아직 저장한 메시지가 없습니다',
          body: '대화에서 중요한 메시지, 음성 transcript, 파일, 위치를 저장하면 이곳에서 다시 찾을 수 있습니다.',
        ),
        SizedBox(height: 12),
        _SettingTile(
          icon: Icons.search_rounded,
          title: '검색',
          subtitle: '저장한 메시지 안에서 텍스트와 태그를 검색합니다.',
        ),
        _SettingTile(
          icon: Icons.label_outline_rounded,
          title: '태그',
          subtitle: '업무, 가족, 일정처럼 저장 항목을 분류합니다.',
        ),
        _SettingTile(
          icon: Icons.push_pin_outlined,
          title: '고정',
          subtitle: '자주 보는 저장 메시지를 상단에 고정합니다.',
        ),
      ],
    );
  }

  void _showAccountManagementSettings(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '계정 관리',
      children: [
        const _SettingTile(
          icon: Icons.phone_android_outlined,
          title: '전화번호 변경',
          subtitle: '인증된 새 번호로 로그인 전화번호를 변경합니다.',
        ),
        const _SettingTile(
          icon: Icons.devices_rounded,
          title: '로그인 기기',
          subtitle: '현재 로그인된 기기와 세션을 확인합니다.',
        ),
        const _SettingTile(
          icon: Icons.password_rounded,
          title: '패스키/2단계 인증',
          subtitle: '계정 보호를 위한 추가 인증 방식을 설정합니다.',
        ),
        _SettingTile(
          icon: Icons.delete_outline_rounded,
          title: '계정 삭제',
          subtitle: '프로필, 아이디 선점, 푸시 토큰, 활성 대화방 멤버십을 삭제합니다.',
          onTap: () => _confirmDeleteAccount(context),
        ),
      ],
    );
  }

  void _showChatBackupSettings(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '대화 백업 및 복원',
      children: const [
        _SettingTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: '텍스트/캘린더 백업',
          subtitle: '텍스트 대화와 앱 내부 캘린더 일정을 백업합니다.',
        ),
        _SettingTile(
          icon: Icons.restore_rounded,
          title: '기기 변경 복원',
          subtitle: '새 기기에서 동일 계정으로 백업 데이터를 복원합니다.',
        ),
        _SettingTile(
          icon: Icons.do_not_disturb_on_outlined,
          title: '백업 제외 항목',
          subtitle: '만료된 음성파일과 삭제된 메시지는 백업하지 않습니다.',
        ),
        _SettingTile(
          icon: Icons.keyboard_voice_outlined,
          title: '음성파일 보존기간 안내',
          subtitle: '보존기간이 지나면 원본 음성은 삭제되고 transcript만 남습니다.',
        ),
      ],
    );
  }

  void _showPermissionSettings(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '권한 관리',
      children: const [
        _SettingTile(
          icon: Icons.mic_none_rounded,
          title: '마이크',
          subtitle: '음성 메시지와 음성 일정 추가에 사용합니다.',
        ),
        _SettingTile(
          icon: Icons.notifications_none_rounded,
          title: '알림',
          subtitle: '메시지, 캘린더 알림, 아침 브리핑에 사용합니다.',
        ),
        _SettingTile(
          icon: Icons.contacts_outlined,
          title: '연락처',
          subtitle: '친구 찾기와 연락처 동기화에 사용합니다.',
        ),
        _SettingTile(
          icon: Icons.location_on_outlined,
          title: '위치',
          subtitle: '대화방에서 위치 공유를 보낼 때만 사용합니다.',
        ),
        _SettingTile(
          icon: Icons.photo_library_outlined,
          title: '사진/파일',
          subtitle: '사진, 영상, 문서 첨부를 보낼 때 사용합니다.',
        ),
      ],
    );
  }

  void _showSafetyCenter(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '안전센터',
      children: const [
        _SettingTile(
          icon: Icons.block_rounded,
          title: '차단 사용자',
          subtitle: '차단한 사용자와 해제 옵션을 관리합니다.',
        ),
        _SettingTile(
          icon: Icons.fact_check_outlined,
          title: '신고한 내역',
          subtitle: '내가 접수한 신고와 처리 상태를 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.report_outlined,
          title: '메시지/사용자 신고',
          subtitle: '부적절한 메시지, 사용자, 대화방을 신고합니다.',
        ),
        _SettingTile(
          icon: Icons.verified_user_outlined,
          title: '스팸/사칭 신고',
          subtitle: '스팸, 피싱, 사칭 계정을 신고합니다.',
        ),
        _SettingTile(
          icon: Icons.shield_outlined,
          title: '보호 조치 안내',
          subtitle: '신고, 차단, 메시지 요청 제한 정책을 확인합니다.',
        ),
      ],
    );
  }

  void _showSupportCenter(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '고객지원',
      children: const [
        _SettingTile(
          icon: Icons.mail_outline_rounded,
          title: '문의하기',
          subtitle: '서비스 이용 중 발생한 문제를 고객지원팀에 보냅니다.',
        ),
        _SettingTile(
          icon: Icons.fact_check_outlined,
          title: '신고 처리 현황',
          subtitle: '신고 접수와 처리 결과를 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.account_circle_outlined,
          title: '로그인/계정 문제',
          subtitle: '전화번호 인증, 로그인, 계정 복구 문제를 요청합니다.',
        ),
        _SettingTile(
          icon: Icons.record_voice_over_outlined,
          title: '음성 인식 오류 신고',
          subtitle: 'STT transcript 품질 문제를 신고합니다.',
        ),
        _SettingTile(
          icon: Icons.perm_device_information_outlined,
          title: '앱 버전/기기 정보 자동 첨부',
          subtitle: '문의 시 오류 분석에 필요한 기본 진단 정보를 함께 보냅니다.',
        ),
      ],
    );
  }

  void _showAnnouncements(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '공지사항',
      children: const [
        _EmptyDetailState(
          icon: Icons.campaign_outlined,
          title: '새 공지사항이 없습니다',
          body: '서비스 업데이트, 장애/점검 안내, 정책 변경 사항이 생기면 이곳에 표시됩니다.',
        ),
        SizedBox(height: 12),
        _SettingTile(
          icon: Icons.new_releases_outlined,
          title: '서비스 업데이트',
          subtitle: '신규 기능과 개선사항을 안내합니다.',
        ),
        _SettingTile(
          icon: Icons.build_outlined,
          title: '장애/점검 안내',
          subtitle: '점검 일정과 장애 복구 현황을 공지합니다.',
        ),
        _SettingTile(
          icon: Icons.policy_outlined,
          title: '정책 변경 안내',
          subtitle: '약관, 개인정보, 운영정책 변경을 안내합니다.',
        ),
      ],
    );
  }

  void _showLegalPolicy(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '약관 및 정책',
      children: const [
        _SettingTile(
          icon: Icons.article_outlined,
          title: '이용약관',
          subtitle: '서비스 이용 조건과 사용자 의무를 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.privacy_tip_outlined,
          title: '개인정보 처리방침',
          subtitle: '수집, 이용, 보관, 삭제되는 개인정보를 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.groups_outlined,
          title: '운영정책/커뮤니티 가이드라인',
          subtitle: '대화, 신고, 제재 기준을 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.location_on_outlined,
          title: '위치기반서비스 약관',
          subtitle: '위치 공유 기능 이용 조건을 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.child_care_outlined,
          title: '청소년 보호정책',
          subtitle: '청소년 보호와 유해 콘텐츠 대응 기준을 확인합니다.',
        ),
      ],
    );
  }

  void _showAppInfo(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '앱 정보',
      children: [
        const _InfoRow(label: '서비스', value: 'Verbal'),
        const _InfoRow(label: '버전', value: '1.0.0+1'),
        _InfoRow(
          label: '모드',
          value: BackendScope.of(context).isConfigured ? 'Firebase' : 'Demo',
        ),
        const SizedBox(height: 10),
        const _SettingTile(
          icon: Icons.info_outline_rounded,
          title: '서비스 정보',
          subtitle: '음성 메시지, STT, 앱 내부 캘린더를 제공하는 메신저입니다.',
        ),
      ],
    );
  }

  void _showAdSettings(BuildContext context) {
    _showMenuDetailSheet(
      context,
      title: '광고 설정',
      children: const [
        _SettingTile(
          icon: Icons.tune_rounded,
          title: '맞춤형 광고 설정',
          subtitle: '관심사 기반 광고 사용 여부를 관리합니다.',
        ),
        _SettingTile(
          icon: Icons.info_outline_rounded,
          title: '광고 정보',
          subtitle: '광고 노출 위치와 데이터 사용 방식을 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.report_gmailerrorred_outlined,
          title: '부적절한 광고 신고',
          subtitle: '연령 부적합하거나 불쾌한 광고를 신고합니다.',
        ),
      ],
    );
  }

  void _showOpenSourceLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Verbal',
      applicationVersion: '1.0.0+1',
      applicationLegalese: '© 2026 Verbal',
    );
  }

  void _showNotificationSettings(BuildContext context) {
    var all = true;
    var direct = true;
    var group = true;
    var requests = true;
    var calendar = widget.user.calendarReminderEnabled;
    var preview = true;
    var vibration = true;
    _showMenuDetailSheet(
      context,
      title: '알림 설정',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: all,
                  onChanged: (value) => setSheetState(() => all = value),
                  title: const Text('전체 알림'),
                  subtitle: const Text('앱의 모든 알림을 켜거나 끕니다.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: direct,
                  onChanged: all
                      ? (value) => setSheetState(() => direct = value)
                      : null,
                  title: const Text('1:1 메시지'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: group,
                  onChanged: all
                      ? (value) => setSheetState(() => group = value)
                      : null,
                  title: const Text('그룹/채널'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: requests,
                  onChanged: all
                      ? (value) => setSheetState(() => requests = value)
                      : null,
                  title: const Text('요청 메시지'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: calendar,
                  onChanged: all
                      ? (value) => setSheetState(() => calendar = value)
                      : null,
                  title: const Text('캘린더 알림'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preview,
                  onChanged: all
                      ? (value) => setSheetState(() => preview = value)
                      : null,
                  title: const Text('미리보기 표시'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: vibration,
                  onChanged: all
                      ? (value) => setSheetState(() => vibration = value)
                      : null,
                  title: const Text('진동'),
                ),
              ],
            );
          },
        ),
        const _SettingTile(
          icon: Icons.nightlight_outlined,
          title: '무음 시간',
          subtitle: '수면/집중 시간에는 알림을 잠시 멈춥니다.',
        ),
        const _SettingTile(
          icon: Icons.music_note_outlined,
          title: '소리',
          subtitle: '메시지 알림음을 선택합니다.',
        ),
      ],
    );
  }

  void _showPrivacySettings(BuildContext context) {
    var requestScope = '친구의 친구';
    var onlineScope = '친구만';
    _showMenuDetailSheet(
      context,
      title: '개인정보 및 보안',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '메시지 요청 허용 범위',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '전체', label: Text('전체')),
                    ButtonSegment(value: '친구의 친구', label: Text('친구의 친구')),
                    ButtonSegment(value: '친구만', label: Text('친구만')),
                  ],
                  selected: {requestScope},
                  onSelectionChanged: (value) =>
                      setSheetState(() => requestScope = value.first),
                ),
                const SizedBox(height: 18),
                const Text(
                  '마지막 접속/온라인 표시',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '전체', label: Text('전체')),
                    ButtonSegment(value: '친구만', label: Text('친구만')),
                    ButtonSegment(value: '숨김', label: Text('숨김')),
                  ],
                  selected: {onlineScope},
                  onSelectionChanged: (value) =>
                      setSheetState(() => onlineScope = value.first),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _SettingTile(
          icon: Icons.mark_email_unread_outlined,
          title: '요청 메시지함 열기',
          subtitle: '아직 수락하지 않은 대화를 확인합니다.',
          onTap: () => _openRequestsFromDetail(context),
        ),
        const _SettingTile(
          icon: Icons.block_rounded,
          title: '차단 사용자',
          subtitle: '차단한 사용자와 해제 옵션을 관리합니다.',
        ),
        const _SettingTile(
          icon: Icons.devices_rounded,
          title: '로그인 기기/세션 관리',
          subtitle: '연결된 기기와 세션을 확인합니다.',
        ),
        const _SettingTile(
          icon: Icons.lock_outline_rounded,
          title: '앱 잠금',
          subtitle: '앱 실행 시 추가 잠금을 사용합니다.',
        ),
        const _SettingTile(
          icon: Icons.report_outlined,
          title: '신고/스팸 정책',
          subtitle: '신고 기준과 스팸 차단 정책을 확인합니다.',
        ),
        _SettingTile(
          icon: Icons.ads_click_outlined,
          title: '광고 설정',
          subtitle: '맞춤형 광고, 광고 정보, 부적절한 광고 신고를 관리합니다.',
          onTap: () {
            Navigator.of(context).pop();
            _showAdSettings(this.context);
          },
        ),
      ],
    );
  }

  void _showDataStorageSettings(BuildContext context) {
    var retention = '1일';
    var autoDownload = false;
    _showMenuDetailSheet(
      context,
      title: '데이터 및 저장 공간',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '음성 파일 보존기간',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '1일', label: Text('1일')),
                    ButtonSegment(value: '7일', label: Text('7일')),
                    ButtonSegment(value: '사용자 지정', label: Text('사용자 지정')),
                  ],
                  selected: {retention},
                  onSelectionChanged: (value) =>
                      setSheetState(() => retention = value.first),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: autoDownload,
                  onChanged: (value) =>
                      setSheetState(() => autoDownload = value),
                  title: const Text('미디어 자동 다운로드'),
                  subtitle: const Text('Wi-Fi 환경에서 이미지와 파일을 자동 저장합니다.'),
                ),
              ],
            );
          },
        ),
        const _SettingTile(
          icon: Icons.cleaning_services_outlined,
          title: '캐시 정리',
          subtitle: '기기에 임시 저장된 미디어 캐시를 비웁니다.',
        ),
        const _SettingTile(
          icon: Icons.pie_chart_outline_rounded,
          title: '저장공간 사용량',
          subtitle: '현재 약 24 MB 사용 중',
        ),
        const _SettingTile(
          icon: Icons.keyboard_voice_outlined,
          title: '음성 자동 전송',
          subtitle: '음성은 STT 변환 후 확인 단계 없이 메시지로 전송됩니다.',
        ),
        _SettingTile(
          icon: Icons.download_rounded,
          title: '내 데이터 다운로드',
          subtitle: '계정, 대화, 저장한 메시지, 캘린더 데이터를 JSON으로 확인합니다.',
          onTap: () {
            Navigator.of(context).pop();
            _exportMyData(this.context);
          },
        ),
      ],
    );
  }

  void _showLanguageSettings(BuildContext context) {
    var selected = AppPreferenceScope.of(context).language;
    _showMenuDetailSheet(
      context,
      title: '언어',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            final preferences = AppPreferenceScope.of(context);
            return Column(
              children: [
                for (final language in AppLanguage.values)
                  _ChoiceTile(
                    title: Text(language.label),
                    subtitle: Text(language.code),
                    selected: selected == language,
                    onTap: () {
                      preferences.setLanguage(language);
                      setSheetState(() => selected = language);
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showThemeSettings(BuildContext context) {
    var selected = AppPreferenceScope.of(context).themeChoice;
    _showMenuDetailSheet(
      context,
      title: '테마',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            final preferences = AppPreferenceScope.of(context);
            return Column(
              children: [
                for (final choice in MessengerThemeChoice.values)
                  _ChoiceTile(
                    title: Text(choice.label),
                    selected: selected == choice,
                    onTap: () {
                      preferences.setThemeChoice(choice);
                      setSheetState(() => selected = choice);
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showFontSizeSettings(BuildContext context) {
    var selected = AppPreferenceScope.of(context).fontSizeChoice;
    _showMenuDetailSheet(
      context,
      title: '폰트 크기',
      children: [
        StatefulBuilder(
          builder: (context, setSheetState) {
            final preferences = AppPreferenceScope.of(context);
            return Column(
              children: [
                for (final choice in MessengerFontSizeChoice.values)
                  _ChoiceTile(
                    title: Text(choice.label),
                    subtitle: Text('${(choice.scale * 100).round()}%'),
                    selected: selected == choice,
                    onTap: () {
                      preferences.setFontSizeChoice(choice);
                      setSheetState(() => selected = choice);
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showMenuDetailSheet(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _kSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(
    BuildContext sheetContext,
    bool isGuestSession,
  ) async {
    Navigator.of(sheetContext).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isGuestSession ? '로그인 화면으로 이동' : '로그아웃'),
          content: Text(
            isGuestSession ? '데모 세션을 종료하고 로그인 화면으로 이동할까요?' : '현재 계정에서 로그아웃할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(isGuestSession ? '이동' : '로그아웃'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await BackendScope.of(context).signOut();
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('계정 삭제'),
          content: const Text(
            '계정을 삭제하면 프로필, 아이디 선점, 푸시 토큰, 활성 대화방 멤버십이 삭제됩니다. 계속할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await BackendScope.of(context).deleteAccount();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('계정을 삭제했습니다.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _openRequestsFromDetail(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    if (mounted) {
      setState(() => _tab = _InboxTab.requests);
    }
  }

  Future<void> _exportMyData(BuildContext sheetContext) async {
    try {
      final data = await BackendScope.of(context).exportMyData();
      final encoded = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted || !sheetContext.mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '내 데이터 다운로드',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '계정 정보, 참여 대화, 내가 보낸 메시지, 저장한 메시지, 캘린더 데이터를 JSON으로 확인할 수 있습니다.',
                    style: TextStyle(
                      color: _kMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        encoded,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(this.context);
                      await Clipboard.setData(ClipboardData(text: encoded));
                      if (context.mounted) {
                        navigator.pop();
                      }
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('데이터를 복사했습니다.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('JSON 복사'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E8EC)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _IconBadge(icon: icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _IconBadge(icon: icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _AddFriendSettingTile extends StatefulWidget {
  const _AddFriendSettingTile();

  @override
  State<_AddFriendSettingTile> createState() => _AddFriendSettingTileState();
}

class _AddFriendSettingTileState extends State<_AddFriendSettingTile> {
  final _handleController = TextEditingController();
  var _expanded = false;
  var _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const _IconBadge(icon: Icons.alternate_email_rounded),
          title: const Text(
            '아이디로 친구 추가',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            '한글, 영어, 일본어, 중국어, 숫자, _ 아이디를 지원합니다.',
            style: TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: Icon(
            _expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
          ),
          onTap: _saving
              ? null
              : () => setState(() {
                  _expanded = !_expanded;
                  _error = null;
                  _success = null;
                }),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 50, right: 2, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('add-friend-handle-field'),
                  controller: _handleController,
                  enabled: !_saving,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '친구 아이디',
                    hintText: 'friend_id',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_success != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _success!,
                    style: const TextStyle(
                      color: _kAccentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('add-friend-submit-button'),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(_saving ? '추가 중' : '친구 추가'),
                ),
              ],
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final handle = normalizeHandle(_handleController.text);
    final handleError = validateHandle(handle);
    if (handle.isEmpty || handleError != null) {
      setState(() {
        _error = handleError ?? '친구 아이디를 입력하세요.';
        _success = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final friend = await BackendScope.read(
        context,
      ).addFriendByHandle(handle: handle);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _success = '${friend.displayName} 님을 친구로 추가했습니다.';
        _handleController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _friendlyFriendAddError(error);
      });
    }
  }

  String _friendlyFriendAddError(Object error) {
    final raw = error.toString();
    if (raw.contains('not-found') || raw.contains('Handle not found')) {
      return '입력한 아이디를 찾을 수 없습니다.';
    }
    if (raw.contains('failed-precondition') || raw.contains('profile')) {
      return '프로필 설정이 필요합니다.';
    }
    if (raw.contains('invalid-argument')) {
      return '아이디 형식을 확인해 주세요.';
    }
    if (raw.contains('already-exists')) {
      return '이미 추가된 친구입니다.';
    }
    if (raw.contains('permission-denied')) {
      return '친구 추가 권한을 확인할 수 없습니다. 다시 로그인해 주세요.';
    }
    return raw
        .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '')
        .replaceFirst('Exception: ', '')
        .trim();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: _kMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final Widget title;
  final Widget? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? _kAccentGreen : _kMuted,
      ),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _EmptyDetailState extends StatelessWidget {
  const _EmptyDetailState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kSelectedGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _kAccentGreen, size: 21),
    );
  }
}

class _FakeStatusBar extends StatelessWidget {
  const _FakeStatusBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 42,
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 12, 24, 10),
        child: Row(
          children: [
            Text(
              '9:41',
              style: TextStyle(
                color: _kHomeInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            Spacer(),
            Icon(
              Icons.signal_cellular_4_bar_rounded,
              color: _kHomeInk,
              size: 14,
            ),
            SizedBox(width: 4),
            Icon(Icons.wifi_rounded, color: _kHomeInk, size: 14),
            SizedBox(width: 4),
            Icon(Icons.battery_full_rounded, color: _kHomeInk, size: 16),
          ],
        ),
      ),
    );
  }
}

class _DirectHeader extends StatelessWidget {
  const _DirectHeader({
    required this.user,
    required this.onMenu,
    required this.onSearch,
    required this.onCalendar,
    required this.onCompose,
  });

  final AppUser user;
  final VoidCallback onMenu;
  final VoidCallback onSearch;
  final VoidCallback onCalendar;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final rawTitle = user.handle.trim().isEmpty
        ? user.displayName
        : user.handle;
    final title = contactProfileForLabel(rawTitle).displayName;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          IconButton(
            tooltip: '메뉴',
            onPressed: onMenu,
            style: IconButton.styleFrom(
              fixedSize: const Size(58, 58),
              minimumSize: const Size(58, 58),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.menu_rounded, color: _kHomeInk, size: 29),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kHomeInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: '전체 검색',
            onPressed: onSearch,
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 58),
              minimumSize: const Size(52, 58),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.search_rounded, color: _kHomeInk, size: 24),
          ),
          IconButton(
            tooltip: '일정',
            onPressed: onCalendar,
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 58),
              minimumSize: const Size(52, 58),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(
              Icons.calendar_month_rounded,
              color: _kHomeInk,
              size: 24,
            ),
          ),
          IconButton(
            tooltip: '새 메시지',
            onPressed: onCompose,
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 58),
              minimumSize: const Size(52, 58),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_square, color: _kHomeInk, size: 22),
          ),
        ],
      ),
    );
  }
}

class _NotesRail extends StatelessWidget {
  const _NotesRail({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final userProfile = contactProfileForLabel(
      user.handle.trim().isEmpty ? user.displayName : user.handle,
    );
    final items = [
      _NoteData(
        userProfile.displayName,
        'Share a thought...',
        'Your note',
        true,
        userProfile.avatarAsset,
      ),
      const _NoteData(
        '이지훈',
        '주말에 바다 갈래?',
        '이지훈',
        false,
        'assets/avatars/contact_jihoon.png',
      ),
      const _NoteData(
        '정유나',
        '☕ 새 카페 찾음',
        '정유나',
        false,
        'assets/avatars/contact_yuna.png',
      ),
      const _NoteData(
        '최아린',
        'Boo!',
        '최아린',
        true,
        'assets/avatars/contact_arin.png',
      ),
    ];
    return SizedBox(
      height: 126,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 22),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) => _NoteItem(data: items[index]),
      ),
    );
  }
}

class _NoteData {
  const _NoteData(
    this.avatarLabel,
    this.note,
    this.caption,
    this.online, [
    this.avatarAsset,
  ]);

  final String avatarLabel;
  final String note;
  final String caption;
  final bool online;
  final String? avatarAsset;
}

class _NoteItem extends StatelessWidget {
  const _NoteItem({required this.data});

  final _NoteData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 4,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: _kHomeSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kHomeBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                data.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kHomeInk,
                  fontSize: 9,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _StoryAvatar(
                  label: data.avatarLabel,
                  size: 54,
                  avatarAsset: data.avatarAsset,
                ),
                if (data.online)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        shape: BoxShape.circle,
                        border: Border.all(color: _kLogoBlack, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 94,
            child: SizedBox(
              width: 68,
              child: Text(
                data.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kHomeMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxTabs extends StatelessWidget {
  const _InboxTabs({required this.selected, required this.onSelected});

  final _InboxTab selected;
  final ValueChanged<_InboxTab> onSelected;

  @override
  Widget build(BuildContext context) {
    const visibleTabs = [_InboxTab.messages, _InboxTab.channels];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          for (final tab in visibleTabs) ...[
            Expanded(
              child: _InboxTabButton(
                tab: tab,
                selected: tab == selected,
                onTap: () => onSelected(tab),
              ),
            ),
            if (tab != visibleTabs.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _InboxTabButton extends StatelessWidget {
  const _InboxTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _InboxTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kHomeSelectedGreen : _kHomeSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 32,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected && tab == _InboxTab.messages) ...[
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: _kAccentGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _kAccentGreen : _kHomeInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchSheet extends StatefulWidget {
  const _GlobalSearchSheet({
    required this.user,
    required this.backend,
    required this.onOpenRoom,
    required this.onOpenCalendar,
  });

  final AppUser user;
  final MessengerBackend backend;
  final ValueChanged<ChatRoom> onOpenRoom;
  final VoidCallback onOpenCalendar;

  @override
  State<_GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<_GlobalSearchSheet> {
  final _controller = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _kSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '전체 검색',
              style: TextStyle(
                color: _kLogoBlack,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('global-search-field'),
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: '검색어',
                hintText: '대화, 음성 transcript, 일정 검색',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: StreamBuilder<List<ChatRoom>>(
                stream: widget.backend.watchRooms(widget.user.uid),
                builder: (context, roomsSnapshot) {
                  return StreamBuilder<List<CalendarEvent>>(
                    stream: widget.backend.watchCalendarEvents(widget.user.uid),
                    builder: (context, eventsSnapshot) {
                      final query = _query.trim().toLowerCase();
                      if (query.isEmpty) {
                        return const _GlobalSearchHint();
                      }
                      final rooms = (roomsSnapshot.data ?? const <ChatRoom>[])
                          .where((room) => _roomMatches(room, query))
                          .toList(growable: false);
                      final allRooms = roomsSnapshot.data ?? const <ChatRoom>[];
                      final events =
                          (eventsSnapshot.data ?? const <CalendarEvent>[])
                              .where((event) => _eventMatches(event, query))
                              .toList(growable: false);
                      if (rooms.isEmpty && events.isEmpty && allRooms.isEmpty) {
                        return const _EmptyDetailState(
                          icon: Icons.search_off_rounded,
                          title: '검색 결과가 없습니다',
                          body: '다른 단어로 다시 검색해 보세요.',
                        );
                      }
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          if (rooms.isNotEmpty) ...[
                            const _SearchSectionLabel('대화'),
                            for (final room in rooms)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _IconBadge(
                                  icon: switch (room.type) {
                                    RoomType.group => Icons.groups_rounded,
                                    RoomType.open => Icons.tag_rounded,
                                    RoomType.direct =>
                                      Icons.chat_bubble_outline_rounded,
                                  },
                                ),
                                title: Text(
                                  contactProfileForLabel(
                                    room.title,
                                  ).displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  room.lastMessage?.preview.trim().isNotEmpty ==
                                          true
                                      ? room.lastMessage!.preview.trim()
                                      : '최근 메시지 없음',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => widget.onOpenRoom(room),
                              ),
                          ],
                          _SearchMessageResults(
                            rooms: allRooms,
                            query: query,
                            backend: widget.backend,
                            showEmptyWhenEmpty: rooms.isEmpty && events.isEmpty,
                            onOpenRoom: widget.onOpenRoom,
                          ),
                          if (events.isNotEmpty) ...[
                            const _SearchSectionLabel('일정'),
                            for (final event in events)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const _IconBadge(
                                  icon: Icons.event_available_rounded,
                                ),
                                title: Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_calendarResultDate(event.startAt)} · ${event.details.isEmpty ? '상세 내용 없음' : event.details}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: widget.onOpenCalendar,
                              ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _roomMatches(ChatRoom room, String query) {
    return room.title.toLowerCase().contains(query) ||
        (room.lastMessage?.preview.toLowerCase().contains(query) ?? false);
  }

  static bool _eventMatches(CalendarEvent event, String query) {
    return event.title.toLowerCase().contains(query) ||
        event.details.toLowerCase().contains(query) ||
        event.transcript.toLowerCase().contains(query);
  }

  static String _calendarResultDate(DateTime value) {
    return '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _SearchMessageResults extends StatelessWidget {
  const _SearchMessageResults({
    required this.rooms,
    required this.query,
    required this.backend,
    required this.showEmptyWhenEmpty,
    required this.onOpenRoom,
  });

  final List<ChatRoom> rooms;
  final String query;
  final MessengerBackend backend;
  final bool showEmptyWhenEmpty;
  final ValueChanged<ChatRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_GlobalMessageHit>>(
      future: _loadMessageHits(),
      builder: (context, snapshot) {
        final hits = snapshot.data ?? const <_GlobalMessageHit>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (hits.isEmpty) {
          if (!showEmptyWhenEmpty) {
            return const SizedBox.shrink();
          }
          return const _EmptyDetailState(
            icon: Icons.search_off_rounded,
            title: '검색 결과가 없습니다',
            body: '다른 단어로 다시 검색해 보세요.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SearchSectionLabel('메시지'),
            for (final hit in hits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _IconBadge(icon: Icons.forum_rounded),
                title: Text(
                  contactProfileForLabel(hit.room.title).displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  hit.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpenRoom(hit.room),
              ),
          ],
        );
      },
    );
  }

  Future<List<_GlobalMessageHit>> _loadMessageHits() async {
    if (query.isEmpty || rooms.isEmpty) {
      return const [];
    }
    final hits = <_GlobalMessageHit>[];
    for (final room in rooms.take(25)) {
      final messages = await backend
          .watchMessages(room.id)
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => const []);
      for (final message in messages) {
        final preview = _messageSearchText(message);
        if (preview.toLowerCase().contains(query)) {
          hits.add(_GlobalMessageHit(room: room, preview: preview));
        }
        if (hits.length >= 30) {
          return hits;
        }
      }
    }
    return hits;
  }

  static String _messageSearchText(ChatMessage message) {
    final parts =
        <String>[
              message.displayText,
              message.voiceTranscriptText,
              message.attachment?.title ?? '',
              message.attachment?.address ?? '',
            ]
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false);
    return parts.isEmpty ? '메시지' : parts.join(' · ');
  }
}

class _GlobalMessageHit {
  const _GlobalMessageHit({required this.room, required this.preview});

  final ChatRoom room;
  final String preview;
}

class _SearchSectionLabel extends StatelessWidget {
  const _SearchSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GlobalSearchHint extends StatelessWidget {
  const _GlobalSearchHint();

  @override
  Widget build(BuildContext context) {
    return const _EmptyDetailState(
      icon: Icons.manage_search_rounded,
      title: '찾고 싶은 내용을 입력하세요',
      body: '대화방, 최근 메시지, 음성 transcript, 캘린더 일정까지 한 번에 검색합니다.',
    );
  }
}

class _SwipeRoomTile extends StatefulWidget {
  const _SwipeRoomTile({
    required this.room,
    required this.user,
    required this.onTap,
    required this.onPin,
    required this.onMute,
    required this.onDelete,
  });

  final ChatRoom room;
  final AppUser user;
  final VoidCallback onTap;
  final Future<void> Function() onPin;
  final Future<void> Function() onMute;
  final Future<void> Function() onDelete;

  @override
  State<_SwipeRoomTile> createState() => _SwipeRoomTileState();
}

class _SwipeRoomTileState extends State<_SwipeRoomTile> {
  static const _actionsWidth = 210.0;
  double _offset = 0;
  var _busy = false;

  bool get _open => _offset < -20;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_open ? 12 : 0),
        child: SizedBox(
          height: 70,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              _SwipeActions(
                pinned: widget.room.pinned,
                muted: widget.room.muted,
                busy: _busy,
                onPin: () => _runAction(widget.onPin),
                onMute: () => _runAction(widget.onMute),
                onDelete: () => _runAction(widget.onDelete),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(_offset, 0, 0),
                decoration: BoxDecoration(
                  color: _kHomeSurface,
                  borderRadius: BorderRadius.circular(_open ? 12 : 0),
                  border: Border.all(color: _kHomeBorder),
                  boxShadow: _open
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _open ? _close : widget.onTap,
                  onLongPress: _openFully,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _offset = (_offset + details.delta.dx).clamp(
                        -_actionsWidth,
                        0,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_offset.abs() > 52) {
                      _openFully();
                    } else {
                      _close();
                    }
                  },
                  child: _RoomRowContent(room: widget.room, user: widget.user),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFully() {
    setState(() => _offset = -_actionsWidth);
  }

  void _close() {
    setState(() => _offset = 0);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        _close();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _SwipeActions extends StatelessWidget {
  const _SwipeActions({
    required this.pinned,
    required this.muted,
    required this.busy,
    required this.onPin,
    required this.onMute,
    required this.onDelete,
  });

  final bool pinned;
  final bool muted;
  final bool busy;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionButton(
          label: pinned ? '해제' : '고정',
          background: _kHomeActionSurface,
          foreground: _kHomeInk,
          onTap: busy ? null : onPin,
        ),
        _ActionButton(
          label: muted ? '알림 켬' : '알림 끔',
          background: _kHomeSoft,
          foreground: _kHomeInk,
          onTap: busy ? null : onMute,
        ),
        _ActionButton(
          label: '삭제',
          background: _kActionRed,
          foreground: Colors.white,
          onTap: busy ? null : onDelete,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          height: 70,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomRowContent extends StatelessWidget {
  const _RoomRowContent({required this.room, required this.user});

  final ChatRoom room;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final last = room.lastMessage;
    final profile = contactProfileForLabel(room.title);
    final preview = last?.preview.trim().isNotEmpty == true
        ? last!.preview.trim()
        : '새 대화를 시작하세요';
    final subtitle = last == null
        ? preview
        : '$preview · ${_relativeTime(last.createdAt)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _StoryAvatar(
            label: profile.displayName,
            size: 52,
            avatarAsset: room.type == RoomType.direct
                ? profile.avatarAsset
                : null,
            icon: switch (room.type) {
              RoomType.group => Icons.groups_rounded,
              RoomType.open => Icons.tag_rounded,
              RoomType.direct => null,
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kHomeInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (room.pinned) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: _kHomeMuted,
                      ),
                    ],
                    if (room.muted) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.notifications_off_outlined,
                        size: 12,
                        color: _kHomeMuted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kHomeMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (room.unreadCount > 0)
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _kAccentGreen,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

enum _RoomCreateMode {
  normal,
  open;

  String get title => switch (this) {
    _RoomCreateMode.normal => '일반채팅',
    _RoomCreateMode.open => '오픈채팅',
  };
}

class NewRoomSheet extends StatefulWidget {
  const NewRoomSheet({required this.user, super.key});

  final AppUser user;

  @override
  State<NewRoomSheet> createState() => _NewRoomSheetState();
}

class _NewRoomSheetState extends State<NewRoomSheet> {
  final _searchController = TextEditingController();
  final _manualHandleController = TextEditingController();
  final _titleController = TextEditingController();
  final _inviteController = TextEditingController();
  final _openHandlesController = TextEditingController();
  Future<List<AppUser>>? _contactsFuture;
  _RoomCreateMode? _mode;
  final _selectedHandles = <String>{};
  final _selectedUsers = <String, AppUser>{};
  String? _error;
  var _saving = false;
  var _joining = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _contactsFuture ??= BackendScope.of(context).listUserDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualHandleController.dispose();
    _titleController.dispose();
    _inviteController.dispose();
    _openHandlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final sheetTheme = baseTheme.copyWith(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kAccentGreen,
        brightness: Brightness.light,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: _kLogoBlack,
        displayColor: _kLogoBlack,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: _kLogoBlack,
        iconColor: _kAccentGreen,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: _kLogoBlack),
        helperStyle: const TextStyle(color: _kMuted),
        hintStyle: const TextStyle(color: _kMuted),
        prefixIconColor: _kAccentGreen,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _kAccentGreen,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kLogoBlack,
          side: const BorderSide(color: _kAccentGreen),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: _kLogoBlack),
      ),
    );
    return Theme(
      data: sheetTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _kLogoBlack),
        child: IconTheme(
          data: const IconThemeData(color: _kLogoBlack),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _kSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _NewRoomHeader(
                    title: _mode?.title ?? '채팅 시작',
                    showBack: _mode != null,
                    onBack: () => setState(() {
                      _mode = null;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (_mode == null) ...[
                    _CreateModeCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '일반채팅',
                      subtitle: '친구 1명을 선택하면 1:1, 2명 이상 선택하면 그룹 대화방으로 열립니다.',
                      onTap: () => _selectMode(_RoomCreateMode.normal),
                    ),
                    const SizedBox(height: 10),
                    _CreateModeCard(
                      icon: Icons.tag_rounded,
                      title: '오픈채팅',
                      subtitle: '등록 친구를 초대하거나 링크와 QR을 만들어 공유할 수 있습니다.',
                      onTap: () => _selectMode(_RoomCreateMode.open),
                    ),
                    const SizedBox(height: 20),
                    _InviteJoinSection(
                      controller: _inviteController,
                      joining: _joining,
                      onJoin: _joinInvite,
                    ),
                  ] else if (_mode == _RoomCreateMode.open) ...[
                    _buildOpenChatForm(),
                  ] else ...[
                    _buildFriendPicker(_mode!),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendPicker(_RoomCreateMode mode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('new-room-friend-search-field'),
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '친구 검색',
            hintText: '이름 또는 아이디',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<AppUser>>(
          future: _contactsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final contacts = _filteredContacts(snapshot.data ?? const []);
            return Container(
              constraints: const BoxConstraints(maxHeight: 310),
              decoration: BoxDecoration(
                color: _kSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: contacts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '초대할 친구가 없습니다. 아이디를 직접 입력할 수 있습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _kMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: contacts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final selected = _selectedHandles.contains(
                          contact.handle,
                        );
                        return _FriendSelectTile(
                          contact: contact,
                          selected: selected,
                          onTap: () => _toggleContact(contact),
                        );
                      },
                    ),
            );
          },
        ),
        const SizedBox(height: 12),
        _ManualHandleAdder(
          controller: _manualHandleController,
          onAdd: _addManualHandle,
        ),
        if (_selectedHandles.length > 1) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('new-room-title-field'),
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '대화방 이름',
              hintText: '예: 프로젝트 팀',
              prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('new-room-create-button'),
          onPressed: _saving ? null : () => _createSelectedRoom(mode),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_selectedHandles.length > 1 ? '그룹 만들기' : '채팅 시작'),
        ),
      ],
    );
  }

  Widget _buildOpenChatForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OpenChatNotice(),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('open-room-title-field'),
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '오픈채팅방 이름',
            hintText: '예: 런칭 준비방',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('open-room-friend-search-field'),
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '등록 친구 검색',
            hintText: '이름 또는 아이디',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<AppUser>>(
          future: _contactsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final contacts = _filteredContacts(snapshot.data ?? const []);
            return Container(
              constraints: const BoxConstraints(maxHeight: 230),
              decoration: BoxDecoration(
                color: _kSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: contacts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          '등록된 친구가 없습니다. 아래에서 아이디를 직접 추가할 수 있습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _kMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: contacts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final selected = _selectedHandles.contains(
                          contact.handle,
                        );
                        return _FriendSelectTile(
                          contact: contact,
                          selected: selected,
                          onTap: () => _toggleContact(contact),
                        );
                      },
                    ),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('open-room-handles-field'),
          controller: _openHandlesController,
          decoration: const InputDecoration(
            labelText: '추가로 초대할 아이디',
            hintText: 'user_a, user_b',
            prefixIcon: Icon(Icons.alternate_email_rounded),
            helperText: '쉼표로 여러 명을 입력할 수 있고, 선택한 친구와 함께 초대됩니다.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('open-room-create-button'),
          onPressed: _saving ? null : _createOpenRoom,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('오픈채팅 만들기'),
        ),
      ],
    );
  }

  List<AppUser> _filteredContacts(List<AppUser> contacts) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return contacts;
    }
    return contacts
        .where(
          (contact) =>
              contact.displayName.toLowerCase().contains(query) ||
              contact.handle.toLowerCase().contains(query),
        )
        .toList();
  }

  void _selectMode(_RoomCreateMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _selectedHandles.clear();
      _selectedUsers.clear();
      _searchController.clear();
      _manualHandleController.clear();
      _titleController.clear();
      _openHandlesController.clear();
    });
  }

  void _toggleContact(AppUser contact) {
    final handle = normalizeHandle(contact.handle);
    if (handle.isEmpty) {
      return;
    }
    setState(() {
      if (_selectedHandles.contains(handle)) {
        _selectedHandles.remove(handle);
        _selectedUsers.remove(handle);
      } else {
        _selectedHandles.add(handle);
        _selectedUsers[handle] = contact;
      }
      _error = null;
    });
  }

  void _addManualHandle() {
    final handle = normalizeHandle(_manualHandleController.text);
    final error = validateHandle(handle);
    if (handle.isEmpty || error != null) {
      setState(() => _error = error ?? '올바른 아이디를 입력해 주세요.');
      return;
    }
    setState(() {
      _selectedHandles.add(handle);
      _manualHandleController.clear();
      _error = null;
    });
  }

  Future<void> _createSelectedRoom(_RoomCreateMode mode) async {
    final handles = _selectedHandles.toList(growable: false);
    if (handles.isEmpty) {
      setState(() => _error = '초대할 친구를 선택하거나 아이디를 입력해 주세요.');
      return;
    }
    final type = handles.length == 1 ? RoomType.direct : RoomType.group;
    await _createRoom(
      handles: handles,
      type: type,
      title: _titleForSelectedRoom(type, handles),
    );
  }

  String? _titleForSelectedRoom(RoomType type, List<String> handles) {
    final typedTitle = _titleController.text.trim();
    if (typedTitle.isNotEmpty) {
      return typedTitle;
    }
    final labels = handles
        .map((handle) => _selectedUsers[handle]?.displayName)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList();
    if (type == RoomType.direct && labels.length == 1) {
      return labels.single;
    }
    if (type == RoomType.group && labels.length > 1) {
      return labels.join(', ');
    }
    return null;
  }

  Future<void> _createOpenRoom() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '오픈채팅방 이름을 입력해 주세요.');
      return;
    }
    final handles = {
      ..._selectedHandles,
      ..._handlesFromText(_openHandlesController.text),
    }.toList();
    await _createRoom(handles: handles, type: RoomType.open, title: title);
  }

  List<String> _handlesFromText(String text) {
    final handles = text
        .split(',')
        .map(normalizeHandle)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    for (final handle in handles) {
      final error = validateHandle(handle);
      if (error != null) {
        setState(() => _error = error);
        return const [];
      }
    }
    return handles;
  }

  Future<void> _createRoom({
    required List<String> handles,
    required RoomType type,
    String? title,
  }) async {
    final navigator = Navigator.of(context);
    final ownerContext = navigator.context;
    final backend = BackendScope.of(context);
    final user = widget.user;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final room = await backend.createRoom(
        participantHandles: handles,
        type: type,
        title: title,
      );
      RoomInvite? openInvite;
      if (type == RoomType.open) {
        openInvite = await backend.createRoomInvite(roomId: room.id);
      }
      if (!mounted) {
        return;
      }
      navigator.pop();
      if (openInvite != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!ownerContext.mounted) {
            return;
          }
          _showOpenInviteSheet(ownerContext, room, openInvite!, user);
        });
      } else {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(room: room, user: user),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyRoomError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showOpenInviteSheet(
    BuildContext ownerContext,
    ChatRoom room,
    RoomInvite invite,
    AppUser user,
  ) {
    showModalBottomSheet<void>(
      context: ownerContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return _OpenInviteCreatedSheet(
          room: room,
          invite: invite,
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: invite.url));
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(
                sheetContext,
              ).showSnackBar(const SnackBar(content: Text('초대 링크를 복사했습니다.')));
            }
          },
          onEnter: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(ownerContext).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(room: room, user: user),
              ),
            );
          },
        );
      },
    );
  }

  String _friendlyRoomError(Object error) {
    final raw = error.toString();
    if (raw.contains('not-found') || raw.contains('Handle not found')) {
      return '해당 아이디를 찾을 수 없습니다.';
    }
    if (raw.contains('Direct rooms must have exactly two participants')) {
      return '1:1 대화는 친구 1명만 선택할 수 있습니다.';
    }
    return raw
        .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '')
        .replaceFirst('Exception: ', '')
        .trim();
  }

  Future<void> _joinInvite() async {
    final token = _inviteController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = '초대 링크 또는 코드를 입력해 주세요.');
      return;
    }

    final navigator = Navigator.of(context);
    final backend = BackendScope.of(context);
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final result = await backend.joinRoomByInvite(token: token);
      if (!mounted) {
        return;
      }
      if (result.pending) {
        setState(() => _error = '승인 대기 중입니다. 관리자가 승인하면 입장할 수 있습니다.');
        return;
      }
      navigator.pop();
      final room = result.room;
      if (room != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(room: room, user: widget.user),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }
}

class _NewRoomHeader extends StatelessWidget {
  const _NewRoomHeader({
    required this.title,
    required this.showBack,
    required this.onBack,
  });

  final String title;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            tooltip: '뒤로',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          )
        else
          const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _CreateModeCard extends StatelessWidget {
  const _CreateModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: _kSelectedGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _kAccentGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _kMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteJoinSection extends StatelessWidget {
  const _InviteJoinSection({
    required this.controller,
    required this.joining,
    required this.onJoin,
  });

  final TextEditingController controller;
  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _kSoft),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '초대 링크로 참여',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '초대 링크 또는 코드',
                hintText: 'https://.../invite/abc123',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: joining ? null : onJoin,
              icon: joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: const Text('초대 참여'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenInviteCreatedSheet extends StatelessWidget {
  const _OpenInviteCreatedSheet({
    required this.room,
    required this.invite,
    required this.onCopy,
    required this.onEnter,
  });

  final ChatRoom room;
  final RoomInvite invite;
  final Future<void> Function() onCopy;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final sheetTheme = baseTheme.copyWith(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kAccentGreen,
        brightness: Brightness.light,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: _kLogoBlack,
        displayColor: _kLogoBlack,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _kAccentGreen,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kLogoBlack,
          side: const BorderSide(color: _kAccentGreen),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
    return Theme(
      data: sheetTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _kLogoBlack),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _kSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '오픈채팅 링크가 생성되었습니다',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 172,
                    height: 172,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _kSoft),
                    ),
                    child: QrImageView(
                      data: invite.url,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: _kLogoBlack,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: _kLogoBlack,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    invite.url,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('open-room-copy-link-button'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('링크 복사'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('open-room-enter-button'),
                  onPressed: onEnter,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('채팅방 입장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendSelectTile extends StatelessWidget {
  const _FriendSelectTile({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  final AppUser contact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = contactProfileForLabel(contact.displayName);
    return ListTile(
      key: ValueKey('friend-select-${contact.handle}'),
      onTap: onTap,
      leading: ProfileAvatar(
        label: profile.displayName,
        size: 42,
        assetPath: profile.avatarAsset,
      ),
      title: Text(
        contact.displayName,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('@${contact.handle}'),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? _kAccentGreen : _kMuted,
      ),
    );
  }
}

class _ManualHandleAdder extends StatelessWidget {
  const _ManualHandleAdder({required this.controller, required this.onAdd});

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('manual-handle-field'),
            controller: controller,
            decoration: const InputDecoration(
              labelText: '아이디 직접 추가',
              hintText: 'friend_id',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: '아이디 추가',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _OpenChatNotice extends StatelessWidget {
  const _OpenChatNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSelectedGreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: _kAccentGreen),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '오픈채팅은 등록 친구를 바로 초대하거나 링크만 만들어 공유할 수 있습니다.',
              style: TextStyle(fontWeight: FontWeight.w800, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.tab});

  final _InboxTab tab;

  @override
  Widget build(BuildContext context) {
    final label = switch (tab) {
      _InboxTab.messages => '아직 메시지가 없습니다',
      _InboxTab.channels => '아직 채널이 없습니다',
      _InboxTab.requests => '아직 요청이 없습니다',
    };
    return Center(
      child: Text(
        label,
        style: const TextStyle(
          color: _kHomeMuted,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RevenueTile extends StatelessWidget {
  const _RevenueTile({required this.tab});

  final _InboxTab tab;

  @override
  Widget build(BuildContext context) {
    final isChannel = tab == _InboxTab.channels;
    final title = isChannel ? '공식 계정' : '스폰서드';
    final body = isChannel
        ? '브랜드 상담, 예약 알림, 쿠폰을 채널에서 받기'
        : '대화방 밖에서만 노출되는 네이티브 광고';
    final icon = isChannel ? Icons.verified_outlined : Icons.campaign_outlined;
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kHomeSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kHomeBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kHomeSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _kAccentGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kHomeInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kHomeMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '광고',
            style: TextStyle(
              color: _kHomeMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.detail, this.onRetry});

  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: _kHomeMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kHomeInk,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kHomeMuted, fontSize: 12),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.label,
    required this.size,
    this.avatarAsset,
    this.icon,
  });

  final String label;
  final double size;
  final String? avatarAsset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(
      label: label,
      size: size,
      assetPath: avatarAsset,
      icon: icon,
    );
  }
}

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) {
    return 'now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d';
  }
  return '${(diff.inDays / 7).floor()}w';
}
