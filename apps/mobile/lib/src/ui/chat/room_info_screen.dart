import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/messenger_models.dart';
import '../../services/messenger_backend.dart';
import '../shared/profile_avatar.dart';

const _kAccentGreen = Color(0xFF00A86B);
const _kInk = Color(0xFF111111);
const _kMuted = Color(0xFF70727A);
const _kDivider = Color(0xFFE8E8EC);
const _kSoft = Color(0xFFF0F1F4);

class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({required this.room, required this.user, super.key});

  final ChatRoom room;
  final AppUser user;

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  late bool _pinned;
  late bool _muted;
  late bool _archived;
  late bool _approvalRequired;
  late int _audioRetentionDays;
  late String _audioRetentionPreset;
  RoomInvite? _invite;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _pinned = widget.room.pinned;
    _muted = widget.room.muted;
    _archived = widget.room.archived;
    _approvalRequired = widget.room.inviteApprovalRequired;
    _audioRetentionDays = widget.room.audioRetentionDays;
    _audioRetentionPreset = widget.room.audioRetentionPreset;
  }

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('대화 정보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          _RoomHeader(room: widget.room),
          const SizedBox(height: 22),
          const _SectionTitle('상태'),
          _SettingSwitch(
            value: _pinned,
            enabled: !_busy,
            icon: Icons.push_pin_outlined,
            title: '상단 고정',
            onChanged: _setPinned,
          ),
          _SettingSwitch(
            value: _muted,
            enabled: !_busy,
            icon: Icons.notifications_off_outlined,
            title: '알림 끄기',
            onChanged: _setMuted,
          ),
          _SettingSwitch(
            value: _archived,
            enabled: !_busy,
            icon: Icons.archive_outlined,
            title: '보관',
            onChanged: _setArchived,
          ),
          const Divider(height: 28, color: _kDivider),
          StreamBuilder<List<RoomMember>>(
            stream: backend.watchRoomMembers(widget.room.id),
            builder: (context, snapshot) {
              final members = snapshot.data ?? _fallbackMembers();
              final myRole = _roleFor(members, widget.user.uid);
              final canManage = (myRole ?? RoomMemberRole.member).canManageRoom;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InviteSection(
                    invite: _invite,
                    approvalRequired: _approvalRequired,
                    busy: _busy,
                    canManage: canManage,
                    onCreate: _createInvite,
                    onRevoke: _revokeInvite,
                    onCopy: _copyInvite,
                    onApprovalChanged: _setInviteApproval,
                  ),
                  ListTile(
                    enabled: canManage && !_busy,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('음성파일 보존기간'),
                    subtitle: Text('$_audioRetentionDays일 후 음성 삭제, 텍스트는 유지'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showRetentionSheet,
                  ),
                  if (canManage)
                    _JoinRequestsSection(
                      roomId: widget.room.id,
                      busy: _busy,
                      onApprove: _approveJoinRequest,
                      onReject: _rejectJoinRequest,
                    ),
                  const Divider(height: 28, color: _kDivider),
                  _MembersSection(
                    members: members,
                    currentUid: widget.user.uid,
                    canManage: canManage,
                    onRoleChanged: _updateMemberRole,
                    onRemove: _removeMember,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 28, color: _kDivider),
          _SharedContentSection(roomId: widget.room.id),
          const Divider(height: 28, color: _kDivider),
          const _SectionTitle('안전'),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.flag_outlined),
            title: const Text('대화 신고'),
            onTap: _reportRoom,
          ),
          ListTile(
            enabled: !_busy && widget.room.participantIds.length > 1,
            leading: const Icon(Icons.block_outlined),
            title: const Text('사용자 차단'),
            onTap: () => _blockParticipant(widget.room.participantIds),
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.exit_to_app_rounded),
            title: const Text('대화 나가기'),
            textColor: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: _leaveRoom,
          ),
        ],
      ),
    );
  }

  List<RoomMember> _fallbackMembers() {
    return [
      RoomMember(
        uid: widget.user.uid,
        role: RoomMemberRole.fromWire(widget.room.memberRole),
        joinedAt: DateTime.now(),
        displayName: widget.user.displayName,
        handle: widget.user.handle,
      ),
      for (final uid in widget.room.participantIds.where(
        (uid) => uid != widget.user.uid,
      ))
        RoomMember(
          uid: uid,
          role: RoomMemberRole.member,
          joinedAt: DateTime.now(),
        ),
    ];
  }

  RoomMemberRole? _roleFor(List<RoomMember> members, String uid) {
    for (final member in members) {
      if (member.uid == uid) {
        return member.role;
      }
    }
    return null;
  }

  Future<void> _createInvite() async {
    await _run(() async {
      final invite = await BackendScope.of(context).createRoomInvite(
        roomId: widget.room.id,
        approvalRequired: _approvalRequired,
      );
      setState(() => _invite = invite);
    });
  }

  Future<void> _revokeInvite() async {
    final invite = _invite;
    if (invite == null) {
      return;
    }
    await _run(() async {
      await BackendScope.of(
        context,
      ).revokeRoomInvite(roomId: widget.room.id, inviteId: invite.id);
      setState(() => _invite = null);
    });
  }

  Future<void> _copyInvite() async {
    final invite = _invite;
    if (invite == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: invite.url));
    _showSnack('초대 링크를 복사했습니다.');
  }

  Future<void> _setInviteApproval(bool value) async {
    await _run(() async {
      await BackendScope.of(context).setInviteApprovalRequired(
        roomId: widget.room.id,
        approvalRequired: value,
      );
      setState(() => _approvalRequired = value);
    });
  }

  Future<void> _approveJoinRequest(RoomJoinRequest request) async {
    await _run(() async {
      await BackendScope.of(
        context,
      ).approveRoomJoinRequest(roomId: widget.room.id, memberUid: request.uid);
      _showSnack('참여 요청을 승인했습니다.');
    });
  }

  Future<void> _rejectJoinRequest(RoomJoinRequest request) async {
    await _run(() async {
      await BackendScope.of(
        context,
      ).rejectRoomJoinRequest(roomId: widget.room.id, memberUid: request.uid);
      _showSnack('참여 요청을 거절했습니다.');
    });
  }

  Future<void> _updateMemberRole(RoomMember member, RoomMemberRole role) async {
    await _run(() async {
      await BackendScope.of(context).updateRoomMemberRole(
        roomId: widget.room.id,
        memberUid: member.uid,
        role: role,
      );
    });
  }

  Future<void> _removeMember(RoomMember member) async {
    final confirmed = await _confirm(
      title: '멤버 내보내기',
      content: '${member.displayName ?? member.uid} 님을 대화에서 내보낼까요?',
      actionLabel: '내보내기',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(
        context,
      ).removeRoomMember(roomId: widget.room.id, memberUid: member.uid);
    });
  }

  Future<void> _setPinned(bool value) async {
    await _run(() async {
      await BackendScope.of(
        context,
      ).setRoomPinned(roomId: widget.room.id, pinned: value);
      setState(() => _pinned = value);
    });
  }

  Future<void> _setMuted(bool value) async {
    await _run(() async {
      await BackendScope.of(
        context,
      ).setRoomMuted(roomId: widget.room.id, muted: value);
      setState(() => _muted = value);
    });
  }

  Future<void> _setArchived(bool value) async {
    await _run(() async {
      await BackendScope.of(
        context,
      ).setRoomArchived(roomId: widget.room.id, archived: value);
      setState(() => _archived = value);
    });
  }

  Future<void> _showRetentionSheet() async {
    final selection = await showModalBottomSheet<({int days, String preset})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        final customController = TextEditingController(
          text: _audioRetentionPreset == 'custom'
              ? '$_audioRetentionDays'
              : '14',
        );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.timer_outlined),
                  title: Text(
                    '음성파일 보존기간',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('만료 후 음성파일만 삭제하고 transcript는 유지합니다.'),
                ),
                _RetentionOptionTile(
                  selected: _audioRetentionDays == 1,
                  title: '1일',
                  subtitle: '무료 메신저 기본값',
                  onTap: () =>
                      Navigator.of(context).pop((days: 1, preset: 'oneDay')),
                ),
                _RetentionOptionTile(
                  selected: _audioRetentionDays == 7,
                  title: '7일',
                  subtitle: '재생 여지를 늘리고 저장비는 제한',
                  onTap: () =>
                      Navigator.of(context).pop((days: 7, preset: 'sevenDays')),
                ),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('사용자 지정'),
                  subtitle: TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      suffixText: '일',
                      helperText: '1~30일',
                    ),
                  ),
                  trailing: FilledButton(
                    onPressed: () {
                      final days =
                          int.tryParse(customController.text.trim()) ?? 1;
                      Navigator.of(context).pop((
                        days: days.clamp(1, 30).toInt(),
                        preset: 'custom',
                      ));
                    },
                    child: const Text('적용'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selection == null || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).setRoomAudioRetention(
        roomId: widget.room.id,
        days: selection.days,
        preset: selection.preset,
      );
      setState(() {
        _audioRetentionDays = selection.days;
        _audioRetentionPreset = selection.preset;
      });
    });
  }

  Future<void> _reportRoom() async {
    final reason = await _showReasonSheet(title: '대화 신고 사유');
    if (reason == null || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(
        context,
      ).reportRoom(roomId: widget.room.id, reason: reason);
      _showSnack('신고가 접수되었습니다.');
    });
  }

  Future<void> _blockParticipant(List<String> participantIds) async {
    final targets = participantIds
        .where((participantId) => participantId != widget.user.uid)
        .toList(growable: false);
    final targetUid = targets.length == 1
        ? targets.first
        : await _chooseParticipant(targets);
    if (targetUid == null || !mounted) {
      return;
    }
    final confirmed = await _confirm(
      title: '사용자 차단',
      content: '$targetUid 사용자를 차단할까요?',
      actionLabel: '차단',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).blockUser(blockedUid: targetUid);
      _showSnack('사용자를 차단했습니다.');
    });
  }

  Future<void> _leaveRoom() async {
    final confirmed = await _confirm(
      title: '대화 나가기',
      content: '이 대화를 목록에서 나가고 새 메시지를 받지 않습니다.',
      actionLabel: '나가기',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).leaveRoom(roomId: widget.room.id);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  Future<String?> _chooseParticipant(List<String> participantIds) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    '차단할 사용자',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                for (final id in participantIds)
                  Builder(
                    builder: (context) {
                      final profile = contactProfileForLabel(id);
                      return ListTile(
                        leading: _InitialAvatar(
                          label: profile.displayName,
                          size: 34,
                          avatarAsset: profile.avatarAsset,
                        ),
                        title: Text(profile.displayName),
                        onTap: () => Navigator.of(context).pop(id),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showReasonSheet({required String title}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                for (final item in const [
                  ('spam', '스팸 또는 광고'),
                  ('abuse', '욕설 또는 괴롭힘'),
                  ('unsafe', '위험하거나 부적절한 내용'),
                  ('other', '기타'),
                ])
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(item.$2),
                    onTap: () => Navigator.of(context).pop(item.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String actionLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(actionLabel),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final profile = contactProfileForLabel(room.title);
    return Center(
      child: Column(
        children: [
          _InitialAvatar(
            label: profile.displayName,
            size: 76,
            avatarAsset: room.type == RoomType.direct
                ? profile.avatarAsset
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kInk,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            switch (room.type) {
              RoomType.group => '그룹 대화',
              RoomType.open => '오픈채팅',
              RoomType.direct => '1:1 대화',
            },
            style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InviteSection extends StatelessWidget {
  const _InviteSection({
    required this.invite,
    required this.approvalRequired,
    required this.busy,
    required this.canManage,
    required this.onCreate,
    required this.onRevoke,
    required this.onCopy,
    required this.onApprovalChanged,
  });

  final RoomInvite? invite;
  final bool approvalRequired;
  final bool busy;
  final bool canManage;
  final VoidCallback onCreate;
  final VoidCallback onRevoke;
  final VoidCallback onCopy;
  final ValueChanged<bool> onApprovalChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('초대'),
        SwitchListTile(
          value: approvalRequired,
          onChanged: canManage && !busy ? onApprovalChanged : null,
          secondary: const Icon(Icons.verified_user_outlined),
          title: const Text('초대 승인 필요'),
          contentPadding: EdgeInsets.zero,
        ),
        if (invite == null)
          OutlinedButton.icon(
            onPressed: canManage && !busy ? onCreate : null,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('초대 링크/QR 만들기'),
          )
        else ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kDivider),
              ),
              child: QrImageView(data: invite!.url, size: 150),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            invite!.url,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('복사'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canManage && !busy ? onRevoke : null,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('폐기'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.members,
    required this.currentUid,
    required this.canManage,
    required this.onRoleChanged,
    required this.onRemove,
  });

  final List<RoomMember> members;
  final String currentUid;
  final bool canManage;
  final void Function(RoomMember member, RoomMemberRole role) onRoleChanged;
  final ValueChanged<RoomMember> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('멤버'),
        for (final member in members)
          Builder(
            builder: (context) {
              final rawLabel =
                  member.displayName ?? member.handle ?? member.uid;
              final profile = contactProfileForLabel(rawLabel);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _InitialAvatar(
                  label: profile.displayName,
                  size: 38,
                  avatarAsset: profile.avatarAsset,
                ),
                title: Text(profile.displayName),
                subtitle: Text(
                  member.handle == null ? member.uid : '@${member.handle}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoleChip(role: member.role),
                    if (canManage && member.uid != currentUid)
                      PopupMenuButton<String>(
                        tooltip: '멤버 관리',
                        onSelected: (value) {
                          if (value == 'remove') {
                            onRemove(member);
                            return;
                          }
                          onRoleChanged(member, RoomMemberRole.fromWire(value));
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'admin',
                            child: Text('관리자로 지정'),
                          ),
                          const PopupMenuItem(
                            value: 'member',
                            child: Text('멤버로 지정'),
                          ),
                          if (member.role != RoomMemberRole.owner)
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('내보내기'),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _RetentionOptionTile extends StatelessWidget {
  const _RetentionOptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? _kAccentGreen : _kMuted,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _JoinRequestsSection extends StatelessWidget {
  const _JoinRequestsSection({
    required this.roomId,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final String roomId;
  final bool busy;
  final ValueChanged<RoomJoinRequest> onApprove;
  final ValueChanged<RoomJoinRequest> onReject;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomJoinRequest>>(
      stream: BackendScope.of(context).watchRoomJoinRequests(roomId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <RoomJoinRequest>[];
        if (requests.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('참여 요청'),
              for (final request in requests)
                Builder(
                  builder: (context) {
                    final profile = contactProfileForLabel(request.label);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _InitialAvatar(
                        label: profile.displayName,
                        size: 36,
                        avatarAsset: profile.avatarAsset,
                      ),
                      title: Text(profile.displayName),
                      subtitle: Text(
                        request.handle == null
                            ? request.uid
                            : '@${request.handle}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '거절',
                            onPressed: busy ? null : () => onReject(request),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          IconButton(
                            tooltip: '승인',
                            onPressed: busy ? null : () => onApprove(request),
                            icon: const Icon(Icons.check_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SharedContentSection extends StatelessWidget {
  const _SharedContentSection({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatMessage>>(
      stream: BackendScope.of(context).watchMessages(roomId),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <ChatMessage>[])
            .where(
              (message) => message.attachment != null && !message.isDeleted,
            )
            .toList()
            .reversed
            .take(12)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('공유 보관함'),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  '공유된 미디어, 파일, 위치가 없습니다.',
                  style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
                ),
              )
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final attachment = items[index].attachment!;
                    return _SharedTile(attachment: attachment);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SharedTile extends StatelessWidget {
  const _SharedTile({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final icon = switch (attachment.type) {
      AttachmentType.image => Icons.image_rounded,
      AttachmentType.file => Icons.insert_drive_file_rounded,
      AttachmentType.location => Icons.location_on_rounded,
    };
    return Container(
      width: 106,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _kAccentGreen),
          const Spacer(),
          Text(
            attachment.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.value,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final IconData icon;
  final String title;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      secondary: Icon(icon),
      title: Text(title),
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final RoomMemberRole role;

  @override
  Widget build(BuildContext context) {
    final selected = role != RoomMemberRole.member;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE2FAEE) : _kSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: selected ? _kAccentGreen : _kMuted,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.label,
    required this.size,
    this.avatarAsset,
  });

  final String label;
  final double size;
  final String? avatarAsset;

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(label: label, size: size, assetPath: avatarAsset);
  }
}
