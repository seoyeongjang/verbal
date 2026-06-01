import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/messenger_models.dart';
import '../../services/attachment_picker.dart';
import '../../services/browser_speech_recognizer.dart';
import '../../services/location_picker.dart';
import '../../services/messenger_backend.dart';
import 'room_info_screen.dart';

const _kPrimaryGreen = Color(0xFF00A86B);
const _kBubbleGreenA = Color(0xFF35C987);
const _kBubbleGreenB = Color(0xFF008F6E);
const _kInk = Color(0xFF111111);
const _kMuted = Color(0xFF70727A);
const _kChatBackground = Colors.white;
const _kIncomingBubble = Color(0xFFF0F0F0);
const _kComposerFill = Color(0xFFEFFAF4);
const _kDivider = Color(0xFFEEEEF0);

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.room, required this.user, super.key});

  final ChatRoom room;
  final AppUser user;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late SendMode _sendMode;
  final _searchController = TextEditingController();
  ChatMessage? _replyTo;
  String? _lastMarkedMessageId;
  var _searching = false;
  var _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _sendMode = widget.user.defaultSendMode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      backgroundColor: _kChatBackground,
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: _kDivider, width: 0.7)),
        title: Row(
          children: [
            _InitialAvatar(label: widget.room.title, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.room.type == RoomType.group ? '그룹 대화' : '1:1 대화',
                    style: const TextStyle(
                      color: _kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '음성 통화',
            onPressed: () => _showUnavailable('음성 통화'),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: '영상 통화',
            onPressed: () => _showUnavailable('영상 통화'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          PopupMenuButton<Object>(
            tooltip: '더 보기',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'search') {
                _toggleSearch();
              } else if (value == 'info') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RoomInfoScreen(room: widget.room, user: widget.user),
                  ),
                );
              } else if (value is SendMode) {
                setState(() => _sendMode = value);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'search',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search_rounded),
                  title: Text('대화 검색'),
                ),
              ),
              PopupMenuItem(
                value: 'info',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('대화 정보'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: SendMode.confirm,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.rate_review_outlined),
                  title: Text('확인 후 전송'),
                ),
              ),
              PopupMenuItem(
                value: SendMode.instant,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bolt_outlined),
                  title: Text('즉시 전송'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            _ChatSearchBar(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: backend.watchMessages(widget.room.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ChatConnectionState(
                    message: '연결이 불안정합니다. 네트워크를 확인한 뒤 다시 시도해 주세요.',
                    detail: snapshot.error.toString(),
                    onRetry: () => setState(() {}),
                  );
                }
                final messages = snapshot.data ?? const <ChatMessage>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    messages.isEmpty) {
                  return const _ChatConnectionState(
                    message: '메시지를 동기화하는 중입니다.',
                    progress: true,
                  );
                }
                if (messages.isEmpty) {
                  return const _EmptyChat();
                }
                _markRead(messages);
                final visibleMessages = _visibleMessages(messages);
                if (visibleMessages.isEmpty) {
                  return _searchQuery.trim().isEmpty
                      ? const _EmptyChat()
                      : const _SearchEmpty();
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, index) {
                    final message = visibleMessages[index];
                    return MessageBubble(
                      message: message,
                      isMine: message.senderId == widget.user.uid,
                      currentUserId: widget.user.uid,
                      canManageCalendarProposals: RoomMemberRole.fromWire(
                        widget.room.memberRole,
                      ).canManageRoom,
                      roomTitle: widget.room.title,
                      onReply: () => setState(() => _replyTo = message),
                      onReact: (emoji) => _toggleReaction(message, emoji),
                      onPin: () => _toggleMessagePin(message),
                      onTranslate: () => _translateMessage(message),
                      onVoteCalendarProposal: (proposal, candidateIds) =>
                          _voteCalendarProposal(proposal, candidateIds),
                      onFinalizeCalendarProposal: (proposal, candidateId) =>
                          _finalizeCalendarProposal(proposal, candidateId),
                      onAddCalendarProposal: (proposal) =>
                          _addCalendarProposal(proposal),
                      onCancelCalendarProposal: (proposal) =>
                          _cancelCalendarProposal(proposal),
                      onSendNow:
                          message.isScheduled &&
                              message.senderId == widget.user.uid
                          ? () => _sendScheduledNow(message)
                          : null,
                      onEdit:
                          message.senderId == widget.user.uid &&
                              message.kind != MessageKind.calendarProposal
                          ? () => _editMessage(message)
                          : null,
                      onDelete: message.senderId == widget.user.uid
                          ? () => _deleteMessage(message)
                          : null,
                      onReport: message.senderId == widget.user.uid
                          ? null
                          : () => _reportMessage(message),
                    );
                  },
                );
              },
            ),
          ),
          MessageComposer(
            roomId: widget.room.id,
            sendMode: _sendMode,
            replyTo: _replyTo,
            onCancelReply: () => setState(() => _replyTo = null),
            onSent: () {
              if (_replyTo != null) {
                setState(() => _replyTo = null);
              }
            },
          ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _showUnavailable(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 기능은 이후 단계에서 연결됩니다.')));
  }

  List<ChatMessage> _visibleMessages(List<ChatMessage> messages) {
    final liveMessages = messages.where((message) => !message.isDeleted);
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return liveMessages.toList();
    }
    return liveMessages
        .where((message) => _messageMatches(message, query))
        .toList();
  }

  bool _messageMatches(ChatMessage message, String query) {
    return message.displayText.toLowerCase().contains(query) ||
        message.attachment?.preview.toLowerCase().contains(query) == true ||
        message.translations.values.any(
          (translation) => translation.text.toLowerCase().contains(query),
        ) ||
        message.replyTo?.preview.toLowerCase().contains(query) == true;
  }

  void _markRead(List<ChatMessage> messages) {
    final lastMessageId = messages.last.id;
    if (_lastMarkedMessageId == lastMessageId) {
      return;
    }
    _lastMarkedMessageId = lastMessageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        BackendScope.of(
          context,
        ).markRoomRead(roomId: widget.room.id, lastMessageId: lastMessageId),
      );
    });
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.displayText);
    final nextText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '메시지 수정',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 2,
                    maxLines: 6,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '내용'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text.trim()),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('저장'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (nextText == null || nextText.isEmpty || !mounted) {
      return;
    }
    try {
      await BackendScope.of(context).editMessage(
        roomId: widget.room.id,
        messageId: message.id,
        text: nextText,
      );
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await BackendScope.of(
        context,
      ).deleteMessage(roomId: widget.room.id, messageId: message.id);
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text(
                      '신고 사유',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final item in const [
                    ('spam', '스팸 또는 광고'),
                    ('abuse', '괴롭힘 또는 악성 행위'),
                    ('unsafe', '부적절하거나 위험한 콘텐츠'),
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
          ),
        );
      },
    );
    if (reason == null || !mounted) {
      return;
    }
    try {
      await BackendScope.of(context).reportMessage(
        roomId: widget.room.id,
        messageId: message.id,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    final reacted = message.reactions[emoji]?.contains(widget.user.uid) == true;
    try {
      final backend = BackendScope.of(context);
      if (reacted) {
        await backend.removeReaction(
          roomId: widget.room.id,
          messageId: message.id,
          emoji: emoji,
        );
      } else {
        await backend.addReaction(
          roomId: widget.room.id,
          messageId: message.id,
          emoji: emoji,
        );
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _toggleMessagePin(ChatMessage message) async {
    try {
      final backend = BackendScope.of(context);
      if (message.isPinned) {
        await backend.unpinMessage(
          roomId: widget.room.id,
          messageId: message.id,
        );
      } else {
        await backend.pinMessage(roomId: widget.room.id, messageId: message.id);
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _translateMessage(ChatMessage message) async {
    try {
      await BackendScope.of(context).translateMessage(
        roomId: widget.room.id,
        messageId: message.id,
        targetLanguage: 'en',
      );
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _sendScheduledNow(ChatMessage message) async {
    try {
      await BackendScope.of(
        context,
      ).sendScheduledMessageNow(roomId: widget.room.id, messageId: message.id);
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _voteCalendarProposal(
    CalendarProposal proposal,
    List<String> candidateIds,
  ) async {
    try {
      await BackendScope.of(context).voteCalendarProposal(
        roomId: widget.room.id,
        proposalId: proposal.id,
        candidateIds: candidateIds,
      );
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _finalizeCalendarProposal(
    CalendarProposal proposal,
    String candidateId,
  ) async {
    try {
      await BackendScope.of(context).finalizeCalendarProposal(
        roomId: widget.room.id,
        proposalId: proposal.id,
        candidateId: candidateId,
      );
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _addCalendarProposal(CalendarProposal proposal) async {
    try {
      await BackendScope.of(context).addFinalizedProposalToMyCalendar(
        roomId: widget.room.id,
        proposalId: proposal.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내 캘린더에 추가했습니다.')));
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _cancelCalendarProposal(CalendarProposal proposal) async {
    try {
      await BackendScope.of(
        context,
      ).cancelCalendarProposal(roomId: widget.room.id, proposalId: proposal.id);
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ChatSearchBar extends StatelessWidget {
  const _ChatSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kDivider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: TextField(
          key: const ValueKey('chat-search-field'),
          controller: controller,
          autofocus: true,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: '대화 검색',
            prefixIcon: Icon(Icons.search_rounded),
            fillColor: _kComposerFill,
          ),
        ),
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '검색 결과가 없습니다.',
        style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ChatConnectionState extends StatelessWidget {
  const _ChatConnectionState({
    required this.message,
    this.detail,
    this.onRetry,
    this.progress = false,
  });

  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress)
              const CircularProgressIndicator()
            else
              const Icon(Icons.wifi_off_rounded, color: _kMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kMuted, fontSize: 12),
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

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    required this.currentUserId,
    required this.canManageCalendarProposals,
    required this.roomTitle,
    required this.onReply,
    required this.onReact,
    required this.onPin,
    required this.onTranslate,
    required this.onVoteCalendarProposal,
    required this.onFinalizeCalendarProposal,
    required this.onAddCalendarProposal,
    required this.onCancelCalendarProposal,
    this.onSendNow,
    this.onEdit,
    this.onDelete,
    this.onReport,
    super.key,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUserId;
  final bool canManageCalendarProposals;
  final String roomTitle;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final VoidCallback onPin;
  final VoidCallback onTranslate;
  final Future<void> Function(
    CalendarProposal proposal,
    List<String> candidateIds,
  )
  onVoteCalendarProposal;
  final Future<void> Function(CalendarProposal proposal, String candidateId)
  onFinalizeCalendarProposal;
  final Future<void> Function(CalendarProposal proposal) onAddCalendarProposal;
  final Future<void> Function(CalendarProposal proposal)
  onCancelCalendarProposal;
  final VoidCallback? onSendNow;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final _player = AudioPlayer();
  var _playing = false;
  String? _selectedProposalId;
  var _selectedCandidateIds = <String>{};

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget leadingContent(Widget child) {
      return Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: child,
      );
    }

    final proposal =
        widget.message.kind == MessageKind.calendarProposal &&
            !widget.message.isDeleted
        ? widget.message.calendarProposal
        : null;
    if (proposal != null && _selectedProposalId != proposal.id) {
      _selectedProposalId = proposal.id;
      _selectedCandidateIds = proposal
          .selectedCandidateIds(widget.currentUserId)
          .toSet();
    }
    final textColor = widget.message.isDeleted
        ? _kMuted
        : widget.isMine
        ? Colors.white
        : _kInk;
    final bodyText = proposal != null
        ? ''
        : widget.message.isDeleted
        ? widget.message.displayText
        : widget.message.text.trim().isNotEmpty
        ? widget.message.text.trim()
        : widget.message.transcript.trim();
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: proposal != null
              ? Colors.white
              : widget.isMine
              ? null
              : _kIncomingBubble,
          gradient: widget.isMine && proposal == null
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kBubbleGreenA, _kBubbleGreenB],
                )
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(widget.isMine ? 20 : 5),
            bottomRight: Radius.circular(widget.isMine ? 5 : 20),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.message.isPinned) ...[
                leadingContent(const _PinnedLabel()),
                const SizedBox(height: 7),
              ],
              if (widget.message.replyTo != null) ...[
                leadingContent(_ReplyPreview(reply: widget.message.replyTo!)),
                const SizedBox(height: 8),
              ],
              if (widget.message.isScheduled) ...[
                leadingContent(
                  _ScheduledLabel(scheduledAt: widget.message.scheduledAt),
                ),
                const SizedBox(height: 8),
              ],
              if (proposal != null) ...[
                leadingContent(
                  _CalendarProposalCard(
                    proposal: proposal,
                    currentUserId: widget.currentUserId,
                    selectedCandidateIds: _selectedCandidateIds,
                    canManage:
                        proposal.createdBy == widget.currentUserId ||
                        widget.canManageCalendarProposals,
                    onSelectionChanged: (candidateId, selected) {
                      setState(() {
                        if (selected) {
                          _selectedCandidateIds.add(candidateId);
                        } else {
                          _selectedCandidateIds.remove(candidateId);
                        }
                      });
                    },
                    onVote: () => widget.onVoteCalendarProposal(
                      proposal,
                      _selectedCandidateIds.toList(growable: false),
                    ),
                    onFinalize: (candidateId) => widget
                        .onFinalizeCalendarProposal(proposal, candidateId),
                    onAddToCalendar: () =>
                        widget.onAddCalendarProposal(proposal),
                    onCancel: () => widget.onCancelCalendarProposal(proposal),
                  ),
                ),
              ],
              if (widget.message.attachment != null &&
                  !widget.message.isDeleted) ...[
                leadingContent(
                  _AttachmentPreview(
                    attachment: widget.message.attachment!,
                    isMine: widget.isMine,
                  ),
                ),
                if (bodyText.isNotEmpty) const SizedBox(height: 8),
              ],
              if (widget.message.kind == MessageKind.voice &&
                  !widget.message.isDeleted)
                leadingContent(
                  _VoicePlaybackRow(
                    playing: _playing,
                    durationMs: widget.message.durationMs,
                    isMine: widget.isMine,
                    onPressed: !widget.message.hasPlayableAudio
                        ? null
                        : _togglePlayback,
                  ),
                ),
              if (widget.message.kind == MessageKind.voice &&
                  widget.message.audioExpired &&
                  !widget.message.isDeleted) ...[
                const SizedBox(height: 6),
                leadingContent(
                  Text(
                    '음성파일 보존기간이 만료되어 텍스트만 보관됩니다.',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (bodyText.isNotEmpty) ...[
                if (widget.message.kind == MessageKind.voice)
                  const SizedBox(height: 8),
                leadingContent(
                  Text(
                    bodyText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15.5,
                      height: 1.28,
                      fontWeight: FontWeight.w600,
                      fontStyle: widget.message.isDeleted
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
              ],
              if (widget.message.sttStatus == SttStatus.processing ||
                  widget.message.sttStatus == SttStatus.pending) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: _kInk,
                    backgroundColor: _kInk.withValues(alpha: 0.12),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.message.isScheduled) ...[
                    Text(
                      widget.message.deliveryStatus.label,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (widget.message.isEdited) ...[
                    Text(
                      '수정됨(edited)',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.58),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    _clockLabel(widget.message.createdAt),
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              if (widget.message.reactions.isNotEmpty) ...[
                const SizedBox(height: 7),
                leadingContent(
                  _ReactionStrip(reactions: widget.message.reactions),
                ),
              ],
              if (widget.message.translations.isNotEmpty) ...[
                const SizedBox(height: 7),
                leadingContent(
                  _TranslationBlock(
                    translations: widget.message.translations,
                    isMine: widget.isMine,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: widget.isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMine) ...[
            _InitialAvatar(label: widget.roomTitle, size: 28),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: GestureDetector(onLongPress: _showActions, child: bubble),
          ),
        ],
      ),
    );
  }

  void _showActions() {
    if (widget.message.isDeleted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.reply_rounded),
                    title: const Text('답장'),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onReply();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: const Text('반응'),
                    subtitle: const _ReactionPickerHint(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _ReactionPicker(
                      onSelected: (emoji) {
                        Navigator.of(context).pop();
                        widget.onReact(emoji);
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      widget.message.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(widget.message.isPinned ? '고정 해제' : '메시지 고정'),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPin();
                    },
                  ),
                  if (widget.onEdit != null)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('수정'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onEdit!();
                      },
                    ),
                  if (widget.onDelete != null)
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: Text(widget.message.isScheduled ? '예약 취소' : '삭제'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onDelete!();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('영어로 번역'),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onTranslate();
                    },
                  ),
                  if (widget.onSendNow != null)
                    ListTile(
                      leading: const Icon(Icons.send_time_extension_rounded),
                      title: const Text('지금 보내기'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onSendNow!();
                      },
                    ),
                  if (widget.onReport != null)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('신고'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onReport!();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    try {
      final uri = await BackendScope.of(
        context,
      ).audioUri(widget.message.audioPath);
      if (uri == null) {
        _showError('재생할 음성파일이 없습니다.');
        return;
      }
      await _player.setUrl(uri.toString());
      await _player.play();
      if (mounted) {
        setState(() => _playing = true);
      }
      _player.playerStateStream
          .firstWhere(
            (state) => state.processingState == ProcessingState.completed,
          )
          .then((_) {
            if (mounted) {
              setState(() => _playing = false);
            }
          });
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CalendarProposalCard extends StatelessWidget {
  const _CalendarProposalCard({
    required this.proposal,
    required this.currentUserId,
    required this.selectedCandidateIds,
    required this.canManage,
    required this.onSelectionChanged,
    required this.onVote,
    required this.onFinalize,
    required this.onAddToCalendar,
    required this.onCancel,
  });

  final CalendarProposal proposal;
  final String currentUserId;
  final Set<String> selectedCandidateIds;
  final bool canManage;
  final void Function(String candidateId, bool selected) onSelectionChanged;
  final Future<void> Function() onVote;
  final Future<void> Function(String candidateId) onFinalize;
  final Future<void> Function() onAddToCalendar;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final savedSelection = proposal.selectedCandidateIds(currentUserId).toSet();
    final dirty = !_setEquals(savedSelection, selectedCandidateIds);
    final finalCandidate = proposal.finalCandidate;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 248),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FFFB),
        border: Border.all(color: const Color(0xFFBFEEDB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: _kPrimaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _proposalStatusLabel(proposal),
                      style: TextStyle(
                        color: _proposalStatusColor(proposal),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (proposal.details.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              proposal.details.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final candidate in proposal.candidates) ...[
            _CalendarProposalCandidateTile(
              candidate: candidate,
              selected: selectedCandidateIds.contains(candidate.id),
              voteCount: proposal.voteCount(candidate.id),
              locked: !proposal.isOpen,
              highlighted: finalCandidate?.id == candidate.id,
              canFinalize: canManage && proposal.isOpen,
              onChanged: (selected) =>
                  onSelectionChanged(candidate.id, selected),
              onFinalize: () => onFinalize(candidate.id),
            ),
            const SizedBox(height: 8),
          ],
          if (proposal.isOpen)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: dirty ? () => unawaited(onVote()) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPrimaryGreen,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                  label: const Text('투표 저장'),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(onCancel()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kMuted,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('취소'),
                  ),
              ],
            )
          else if (proposal.isFinalized && finalCandidate != null)
            FilledButton.icon(
              onPressed: () => unawaited(onAddToCalendar()),
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: const Text('내 일정에 추가'),
            ),
        ],
      ),
    );
  }
}

class _CalendarProposalCandidateTile extends StatelessWidget {
  const _CalendarProposalCandidateTile({
    required this.candidate,
    required this.selected,
    required this.voteCount,
    required this.locked,
    required this.highlighted,
    required this.canFinalize,
    required this.onChanged,
    required this.onFinalize,
  });

  final CalendarProposalCandidate candidate;
  final bool selected;
  final int voteCount;
  final bool locked;
  final bool highlighted;
  final bool canFinalize;
  final ValueChanged<bool> onChanged;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted
        ? _kPrimaryGreen
        : selected
        ? const Color(0xFF55D6A0)
        : const Color(0xFFE2E5E7);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
      decoration: BoxDecoration(
        color: selected || highlighted ? const Color(0xFFE9FFF4) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected || highlighted,
            onChanged: locked ? null : (value) => onChanged(value == true),
            activeColor: _kPrimaryGreen,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('M월 d일 HH:mm').format(candidate.startAt),
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${candidate.durationMinutes}분 · $voteCount표',
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (highlighted)
            const Icon(
              Icons.check_circle_rounded,
              color: _kPrimaryGreen,
              size: 20,
            )
          else if (canFinalize)
            TextButton(
              onPressed: onFinalize,
              style: TextButton.styleFrom(
                foregroundColor: _kPrimaryGreen,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('확정'),
            ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.reply});

  final MessageReply reply;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _kInk.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: _kInk.withValues(alpha: 0.35), width: 3),
        ),
      ),
      child: Text(
        reply.preview.isEmpty ? '원본 메시지' : reply.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScheduledLabel extends StatelessWidget {
  const _ScheduledLabel({required this.scheduledAt});

  final DateTime? scheduledAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_rounded, size: 14, color: _kMuted),
        const SizedBox(width: 4),
        Text(
          scheduledAt == null ? '예약 메시지' : '${_clockLabel(scheduledAt!)} 예약',
          style: const TextStyle(
            color: _kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, required this.isMine});

  final MessageAttachment attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return switch (attachment.type) {
      AttachmentType.image => _ImageAttachment(attachment: attachment),
      AttachmentType.file => _FileAttachment(
        attachment: attachment,
        foreground: isMine ? Colors.white : _kInk,
      ),
      AttachmentType.location => _LocationAttachment(
        attachment: attachment,
        foreground: isMine ? Colors.white : _kInk,
      ),
    };
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment.url?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 220,
        height: 150,
        child: url == null || url.isEmpty
            ? _ImageFallback(title: attachment.preview)
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _ImageFallback(title: attachment.preview),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 22, 10, 9),
                        child: Text(
                          attachment.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF48D39A), Color(0xFF00A86B), Color(0xFF008F6E)],
        ),
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.image_rounded, color: Colors.white, size: 42),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment, required this.foreground});

  final MessageAttachment attachment;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_rounded, color: foreground, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (attachment.sizeBytes != null)
                  Text(
                    _fileSizeLabel(attachment.sizeBytes!),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationAttachment extends StatelessWidget {
  const _LocationAttachment({
    required this.attachment,
    required this.foreground,
  });

  final MessageAttachment attachment;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFFE2FAEE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.location_on_rounded,
                color: _kPrimaryGreen,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            attachment.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
          ),
          if (attachment.latitude != null && attachment.longitude != null)
            Text(
              '${attachment.latitude!.toStringAsFixed(4)}, ${attachment.longitude!.toStringAsFixed(4)}',
              style: TextStyle(
                color: foreground.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (attachment.url?.trim().isNotEmpty == true)
            Text(
              attachment.url!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _TranslationBlock extends StatelessWidget {
  const _TranslationBlock({required this.translations, required this.isMine});

  final Map<String, MessageTranslation> translations;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final translation = translations.values.last;
    final foreground = isMine ? Colors.white : _kInk;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.translate_rounded, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(
                translation.targetLanguage.toUpperCase(),
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            translation.text,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedLabel extends StatelessWidget {
  const _PinnedLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.push_pin_rounded, size: 14, color: _kMuted),
        SizedBox(width: 4),
        Text(
          '고정됨',
          style: TextStyle(
            color: _kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({required this.reactions});

  final Map<String, List<String>> reactions;

  @override
  Widget build(BuildContext context) {
    final entries = reactions.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final entry in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _kInk.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${entry.key} ${entry.value.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

class _ReactionPickerHint extends StatelessWidget {
  const _ReactionPickerHint();

  @override
  Widget build(BuildContext context) {
    return const Text('같은 반응을 다시 누르면 취소됩니다.');
  }
}

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _items = ['👍', '❤️', '😮', '😢', '🔥'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final emoji in _items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () => onSelected(emoji),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF0F1F4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VoicePlaybackRow extends StatelessWidget {
  const _VoicePlaybackRow({
    required this.playing,
    required this.durationMs,
    required this.isMine,
    required this.onPressed,
  });

  final bool playing;
  final int durationMs;
  final bool isMine;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : _kPrimaryGreen;
    final chipColor = isMine
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          tooltip: playing ? 'Pause' : 'Play',
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: chipColor,
            foregroundColor: foreground,
            shape: const CircleBorder(),
          ),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 8),
        _WaveformBars(color: foreground),
        const SizedBox(width: 8),
        Text(
          _durationLabel(durationMs),
          style: TextStyle(
            color: isMine ? Colors.white.withValues(alpha: 0.78) : _kMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [8.0, 14.0, 10.0, 18.0, 12.0, 16.0, 9.0, 15.0];
    return Row(
      children: [
        for (final height in heights)
          Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _AttachmentDraft {
  const _AttachmentDraft({
    required this.kind,
    required this.attachment,
    this.upload,
  });

  final MessageKind kind;
  final MessageAttachment attachment;
  final AttachmentUploadPayload? upload;
}

class _CalendarProposalSheet extends StatefulWidget {
  const _CalendarProposalSheet({required this.initialTitle});

  final String initialTitle;

  @override
  State<_CalendarProposalSheet> createState() => _CalendarProposalSheetState();
}

class _CalendarProposalSheetState extends State<_CalendarProposalSheet> {
  late final TextEditingController _titleController;
  final _detailsController = TextEditingController();
  final _transcriptController = TextEditingController();
  late final List<_CalendarProposalCandidateDraft> _candidates;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    final base = DateTime.now().add(const Duration(days: 1));
    _candidates = [
      _CalendarProposalCandidateDraft.seed(base),
      _CalendarProposalCandidateDraft.seed(base.add(const Duration(hours: 1))),
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _transcriptController.dispose();
    for (final candidate in _candidates) {
      candidate.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedCandidates = _proposalCandidatesOrNull(_candidates);
    final title = _titleController.text.trim();
    final details = _detailsController.text.trim();
    final canSave =
        title.isNotEmpty &&
        title.length <= 120 &&
        details.length <= 2000 &&
        parsedCandidates != null &&
        _candidates.length >= 2;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '일정 제안',
              style: TextStyle(
                color: _kInk,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('calendar-proposal-title-field'),
              controller: _titleController,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 저녁 약속',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('calendar-proposal-details-field'),
              controller: _detailsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '상세 내용',
                hintText: '장소, 준비물, 메모',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('calendar-proposal-transcript-field'),
              controller: _transcriptController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '음성 변환 텍스트',
                hintText: '음성으로 만든 초안이면 원문을 남깁니다.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '후보 시간',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '후보 추가',
                  onPressed: _candidates.length >= 5
                      ? null
                      : () => setState(() {
                          final last = _candidates.last.startAt;
                          _candidates.add(
                            _CalendarProposalCandidateDraft.seed(
                              last.add(const Duration(hours: 1)),
                            ),
                          );
                        }),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _candidates.length; index++)
              _CalendarProposalCandidateEditor(
                key: ValueKey('calendar-proposal-candidate-$index'),
                index: index,
                draft: _candidates[index],
                canRemove: _candidates.length > 2,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() {
                  final removed = _candidates.removeAt(index);
                  removed.dispose();
                }),
              ),
            if (parsedCandidates == null) ...[
              const SizedBox(height: 4),
              Text(
                '후보는 2~5개, 미래 시간, YYYY-MM-DD / HH:MM 형식이어야 합니다.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canSave
                  ? () => Navigator.of(context).pop(
                      _CalendarProposalFormValue(
                        title: title,
                        details: details,
                        transcript: _transcriptController.text.trim(),
                        candidates: parsedCandidates,
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('제안 보내기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarProposalCandidateDraft {
  _CalendarProposalCandidateDraft({
    required DateTime startAt,
    required int durationMinutes,
  }) : dateController = TextEditingController(
         text: DateFormat('yyyy-MM-dd').format(startAt),
       ),
       timeController = TextEditingController(
         text: DateFormat('HH:mm').format(startAt),
       ),
       durationController = TextEditingController(text: '$durationMinutes');

  factory _CalendarProposalCandidateDraft.seed(DateTime startAt) {
    final rounded = DateTime(
      startAt.year,
      startAt.month,
      startAt.day,
      startAt.hour,
      startAt.minute < 30 ? 30 : 0,
    ).add(startAt.minute < 30 ? Duration.zero : const Duration(hours: 1));
    return _CalendarProposalCandidateDraft(
      startAt: rounded,
      durationMinutes: 60,
    );
  }

  final TextEditingController dateController;
  final TextEditingController timeController;
  final TextEditingController durationController;

  DateTime get startAt {
    final date = _parseScheduleDate(dateController.text);
    final time = _parseScheduleTime(timeController.text);
    if (date == null || time == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void dispose() {
    dateController.dispose();
    timeController.dispose();
    durationController.dispose();
  }
}

class _CalendarProposalCandidateEditor extends StatelessWidget {
  const _CalendarProposalCandidateEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _CalendarProposalCandidateDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '후보 ${index + 1}',
                  style: const TextStyle(
                    color: _kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '후보 삭제',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('calendar-proposal-date-$index'),
                  controller: draft.dateController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: '날짜',
                    hintText: 'YYYY-MM-DD',
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey('calendar-proposal-time-$index'),
                  controller: draft.timeController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: '시간',
                    hintText: 'HH:MM',
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('calendar-proposal-duration-$index'),
            controller: draft.durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '기간',
              hintText: '분 단위',
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _CalendarProposalFormValue {
  const _CalendarProposalFormValue({
    required this.title,
    required this.details,
    required this.transcript,
    required this.candidates,
  });

  final String title;
  final String details;
  final String transcript;
  final List<CalendarProposalCandidate> candidates;
}

class _SttRecoveryResult {
  const _SttRecoveryResult.retry() : retry = true, manualTranscript = null;

  const _SttRecoveryResult.manual(this.manualTranscript) : retry = false;

  final bool retry;
  final String? manualTranscript;
}

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.roomId,
    required this.sendMode,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSent,
    super.key,
  });

  final String roomId;
  final SendMode sendMode;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  final _speechRecognizer = BrowserSpeechRecognizer();
  final _stopwatch = Stopwatch();
  Timer? _timer;
  var _recording = false;
  var _busy = false;
  String? _busyLabel;

  @override
  void dispose() {
    _timer?.cancel();
    _textController.dispose();
    unawaited(_speechRecognizer.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _kDivider)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyTo != null) ...[
                _ComposerReplyBar(
                  message: widget.replyTo!,
                  onCancel: widget.onCancelReply,
                ),
                const SizedBox(height: 8),
              ],
              if (_recording) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFF3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.fiber_manual_record_rounded,
                        color: Color(0xFFFF3040),
                        size: 15,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '녹음 중 ${_durationLabel(_stopwatch.elapsedMilliseconds)}',
                        style: const TextStyle(
                          color: Color(0xFFD92D20),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_busy) ...[
                _ComposerProgress(label: _busyLabel ?? '처리 중입니다.'),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _showAttachmentSheet,
                    tooltip: '첨부',
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: _kPrimaryGreen,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 23),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _kComposerFill,
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: TextField(
                        key: const ValueKey('message-input-field'),
                        controller: _textController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: const InputDecoration(
                          hintText: '메시지...',
                          filled: false,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _ComposerIconButton(
                    tooltip: _recording ? '녹음 중지' : '음성 녹음',
                    onPressed: _busy ? null : _toggleRecording,
                    icon: _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    active: _recording,
                  ),
                  _ComposerIconButton(
                    tooltip: '예약 전송',
                    onPressed: _busy ? null : _showScheduleSheet,
                    icon: Icons.schedule_send_rounded,
                  ),
                  _ComposerIconButton(
                    tooltip: '전송',
                    onPressed: _busy ? null : _sendText,
                    icon: Icons.send_rounded,
                    active: true,
                    busy: _busy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).sendTextMessage(
        roomId: widget.roomId,
        text: text,
        replyToMessageId: widget.replyTo?.id,
      );
      _textController.clear();
      widget.onSent();
    }, busyLabel: '메시지를 전송하는 중입니다.');
  }

  Future<void> _showAttachmentSheet() async {
    final caption = _textController.text.trim();
    final selected = await showModalBottomSheet<_AttachmentDraft>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text(
                      '첨부 보내기',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('사진'),
                    subtitle: const Text('이 기기에서 이미지를 선택합니다'),
                    onTap: () => _pickAndCloseAttachment(
                      context,
                      AttachmentPickKind.image,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: const Text('파일'),
                    subtitle: const Text('문서 또는 파일을 선택합니다'),
                    onTap: () => _pickAndCloseAttachment(
                      context,
                      AttachmentPickKind.file,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('위치'),
                    subtitle: const Text('현재 위치를 공유합니다'),
                    onTap: () => _pickAndCloseLocation(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('일정 제안'),
                    subtitle: const Text('후보 시간을 투표 카드로 보냅니다.'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Future<void>.microtask(_showCalendarProposalSheet);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).sendAttachmentMessage(
        roomId: widget.roomId,
        kind: selected.kind,
        attachment: selected.attachment,
        upload: selected.upload,
        caption: caption,
        replyToMessageId: widget.replyTo?.id,
      );
      _textController.clear();
      widget.onSent();
    }, busyLabel: '첨부파일을 전송하는 중입니다.');
  }

  Future<void> _showCalendarProposalSheet() async {
    if (!mounted) {
      return;
    }
    final value = await showModalBottomSheet<_CalendarProposalFormValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) =>
          _CalendarProposalSheet(initialTitle: _textController.text.trim()),
    );
    if (value == null || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).createCalendarProposal(
        roomId: widget.roomId,
        title: value.title,
        details: value.details,
        candidates: value.candidates,
        source: value.transcript.isEmpty ? 'manual' : 'voice',
        transcript: value.transcript,
        replyToMessageId: widget.replyTo?.id,
      );
      _textController.clear();
      widget.onSent();
    }, busyLabel: '일정 제안을 전송하는 중입니다.');
  }

  Future<void> _pickAndCloseAttachment(
    BuildContext sheetContext,
    AttachmentPickKind pickKind,
  ) async {
    try {
      final picked = await AttachmentPicker.pick(pickKind);
      if (!sheetContext.mounted) {
        return;
      }
      if (picked == null) {
        Navigator.of(sheetContext).pop();
        return;
      }
      final maxBytes = pickKind == AttachmentPickKind.image
          ? 10 * 1024 * 1024
          : 50 * 1024 * 1024;
      if (picked.sizeBytes > maxBytes) {
        throw StateError(
          pickKind == AttachmentPickKind.image
              ? '이미지는 10MB 이하만 업로드할 수 있습니다.'
              : '파일은 50MB 이하만 업로드할 수 있습니다.',
        );
      }
      final kind = pickKind == AttachmentPickKind.image
          ? MessageKind.image
          : MessageKind.file;
      final type = pickKind == AttachmentPickKind.image
          ? AttachmentType.image
          : AttachmentType.file;
      Navigator.of(sheetContext).pop(
        _AttachmentDraft(
          kind: kind,
          attachment: MessageAttachment(
            type: type,
            title: picked.fileName,
            url: picked.previewUrl,
            mimeType: picked.mimeType,
            sizeBytes: picked.sizeBytes,
          ),
          upload: AttachmentUploadPayload(
            fileName: picked.fileName,
            mimeType: picked.mimeType,
            sizeBytes: picked.sizeBytes,
            bytes: picked.bytes,
          ),
        ),
      );
    } catch (error) {
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      _showError(error.toString());
    }
  }

  Future<void> _pickAndCloseLocation(BuildContext sheetContext) async {
    try {
      final picked = await LocationPicker.pickCurrent();
      if (!sheetContext.mounted) {
        return;
      }
      if (picked == null) {
        Navigator.of(sheetContext).pop();
        return;
      }
      Navigator.of(sheetContext).pop(
        _AttachmentDraft(
          kind: MessageKind.location,
          attachment: MessageAttachment(
            type: AttachmentType.location,
            title: picked.label,
            address: picked.mapUrl,
            url: picked.mapUrl,
            latitude: picked.latitude,
            longitude: picked.longitude,
          ),
        ),
      );
    } catch (error) {
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      _showError(error.toString());
    }
  }

  Future<void> _showScheduleSheet() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('예약할 메시지를 먼저 입력해 주세요.');
      return;
    }
    var dateInput = '';
    var timeInput = '';
    DateTime? selected;
    selected = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final parsedDate = _parseScheduleDate(dateInput);
            final parsedTime = _parseScheduleTime(timeInput);
            final scheduledAt = parsedDate == null || parsedTime == null
                ? null
                : DateTime(
                    parsedDate.year,
                    parsedDate.month,
                    parsedDate.day,
                    parsedTime.hour,
                    parsedTime.minute,
                  );
            final isFuture =
                scheduledAt != null &&
                scheduledAt.isAfter(
                  DateTime.now().add(const Duration(seconds: 30)),
                );
            final hasInput =
                dateInput.trim().isNotEmpty || timeInput.trim().isNotEmpty;
            final errorText = scheduledAt == null
                ? hasInput
                      ? '날짜는 YYYY-MM-DD, 시간은 HH:MM 형식으로 입력해 주세요.'
                      : null
                : isFuture
                ? null
                : '현재보다 이후의 시간을 선택해 주세요.';
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '예약 전송',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '기본값 없이 날짜와 시간을 직접 설정합니다.',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const ValueKey('schedule-date-field'),
                      initialValue: dateInput,
                      keyboardType: TextInputType.datetime,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '날짜',
                        hintText: 'YYYY-MM-DD',
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      onChanged: (value) => setSheetState(() {
                        dateInput = value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('schedule-time-field'),
                      initialValue: timeInput,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: '시간',
                        hintText: 'HH:MM',
                        prefixIcon: Icon(Icons.schedule_rounded),
                      ),
                      onChanged: (value) => setSheetState(() {
                        timeInput = value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (scheduledAt != null && isFuture)
                      Text(
                        '${_scheduleLabel(scheduledAt)}에 전송됩니다.',
                        style: const TextStyle(
                          color: _kPrimaryGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else if (errorText != null)
                      Text(
                        errorText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: isFuture
                          ? () => Navigator.of(context).pop(scheduledAt)
                          : null,
                      icon: const Icon(Icons.schedule_send_rounded),
                      label: const Text('예약하기'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    await _run(() async {
      await BackendScope.of(context).scheduleTextMessage(
        roomId: widget.roomId,
        text: text,
        scheduledAt: selected!,
        replyToMessageId: widget.replyTo?.id,
      );
      _textController.clear();
      widget.onSent();
    }, busyLabel: '예약 메시지를 저장하는 중입니다.');
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    await _run(() async {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        throw StateError('마이크 권한이 필요합니다.');
      }
      if (BrowserSpeechRecognizer.enabled) {
        await _speechRecognizer.start();
      }
      final encoder = await _preferredEncoder();
      final path = await _recordingPath(encoder);
      try {
        await _recorder.start(
          RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 16000),
          path: path,
        );
      } catch (_) {
        await _speechRecognizer.cancel();
        rethrow;
      }
      _stopwatch
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    }, keepBusy: false);
  }

  Future<AudioEncoder> _preferredEncoder() async {
    final candidates = kIsWeb
        ? const [AudioEncoder.opus, AudioEncoder.wav]
        : defaultTargetPlatform == TargetPlatform.windows
        ? const [AudioEncoder.wav]
        : const [AudioEncoder.aacLc, AudioEncoder.wav];
    for (final candidate in candidates) {
      if (await _recorder.isEncoderSupported(candidate)) {
        return candidate;
      }
    }
    return AudioEncoder.wav;
  }

  Future<String> _recordingPath(AudioEncoder encoder) async {
    if (kIsWeb) {
      return '';
    }
    final tempDir = await getTemporaryDirectory();
    final extension = encoder == AudioEncoder.wav ? 'wav' : 'm4a';
    return '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Future<void> _stopRecording() async {
    if (!_recording) {
      return;
    }
    final path = await _recorder.stop();
    final transcriptOverride = BrowserSpeechRecognizer.enabled
        ? await _speechRecognizer.stop()
        : null;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    final durationMs = _stopwatch.elapsedMilliseconds;
    setState(() => _recording = false);
    if (path == null || durationMs < 500) {
      _showError('녹음 시간이 너무 짧습니다.');
      return;
    }

    await _run(() async {
      final backend = BackendScope.of(context);
      var manualTranscript = transcriptOverride;
      if (BrowserSpeechRecognizer.enabled &&
          (manualTranscript == null || manualTranscript.trim().isEmpty)) {
        final recovery = await _showSttRecoverySheet(
          title: '음성을 인식하지 못했습니다',
          message: '다시 시도하거나 텍스트를 직접 입력해 전송할 수 있습니다.',
        );
        if (recovery == null) {
          return;
        }
        if (!recovery.retry) {
          manualTranscript = recovery.manualTranscript;
        }
      }

      if (widget.sendMode == SendMode.instant) {
        final sent = await _sendInstantVoiceWithRecovery(
          backend: backend,
          path: path,
          durationMs: durationMs,
          transcriptOverride: manualTranscript,
        );
        if (sent) {
          widget.onSent();
        }
        return;
      }

      final draft = await _createDraftWithRecovery(
        backend: backend,
        path: path,
        durationMs: durationMs,
        transcriptOverride: manualTranscript,
      );
      if (draft == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      final finalText = await _showReviewSheet(context, draft);
      if (finalText == null) {
        return;
      }
      await backend.sendVoiceMessage(
        roomId: widget.roomId,
        draftId: draft.id,
        finalText: finalText,
        sendMode: widget.sendMode,
        replyToMessageId: widget.replyTo?.id,
      );
      widget.onSent();
    }, busyLabel: '음성을 변환하는 중입니다.');
  }

  Future<TranscriptionDraft?> _createDraftWithRecovery({
    required MessengerBackend backend,
    required String path,
    required int durationMs,
    String? transcriptOverride,
  }) async {
    var manualTranscript = transcriptOverride?.trim();
    for (;;) {
      try {
        return await backend.createTranscriptionDraft(
          audioFilePath: path,
          durationMs: durationMs,
          transcriptOverride: manualTranscript?.isNotEmpty == true
              ? manualTranscript
              : null,
        );
      } catch (error) {
        if (!mounted) {
          rethrow;
        }
        final recovery = await _showSttRecoverySheet(
          title: '음성 변환에 실패했습니다',
          message: '네트워크 또는 STT 서버 상태를 확인한 뒤 다시 시도할 수 있습니다.',
          error: error.toString(),
        );
        if (recovery == null) {
          return null;
        }
        manualTranscript = recovery.retry ? null : recovery.manualTranscript;
      }
    }
  }

  Future<bool> _sendInstantVoiceWithRecovery({
    required MessengerBackend backend,
    required String path,
    required int durationMs,
    String? transcriptOverride,
  }) async {
    var manualTranscript = transcriptOverride?.trim();
    for (;;) {
      try {
        await backend.sendInstantVoiceMessage(
          roomId: widget.roomId,
          audioFilePath: path,
          durationMs: durationMs,
          sendMode: widget.sendMode,
          transcriptOverride: manualTranscript?.isNotEmpty == true
              ? manualTranscript
              : null,
          replyToMessageId: widget.replyTo?.id,
        );
        return true;
      } catch (error) {
        if (!mounted) {
          rethrow;
        }
        final recovery = await _showSttRecoverySheet(
          title: '음성 전송에 실패했습니다',
          message: 'STT를 다시 시도하거나 텍스트를 직접 입력해 전송할 수 있습니다.',
          error: error.toString(),
        );
        if (recovery == null) {
          return false;
        }
        manualTranscript = recovery.retry ? null : recovery.manualTranscript;
      }
    }
  }

  Future<_SttRecoveryResult?> _showSttRecoverySheet({
    required String title,
    required String message,
    String? error,
  }) {
    final controller = TextEditingController();
    return showModalBottomSheet<_SttRecoveryResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 22,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '직접 입력할 텍스트',
                    hintText: '음성으로 말한 내용을 입력하세요',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _SttRecoveryResult.retry()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('STT 다시 시도'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(_SttRecoveryResult.manual(text));
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('직접 입력 후 전송'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showReviewSheet(
    BuildContext context,
    TranscriptionDraft draft,
  ) {
    final controller = TextEditingController(text: draft.transcript);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 22,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '음성 메시지 확인',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '변환된 텍스트'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('전송'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _run(
    Future<void> Function() task, {
    bool keepBusy = true,
    String? busyLabel,
  }) async {
    if (keepBusy) {
      setState(() {
        _busy = true;
        _busyLabel = busyLabel;
      });
    }
    try {
      await task();
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted && keepBusy) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ComposerProgress extends StatelessWidget {
  const _ComposerProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kComposerFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 36, height: 42),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: active ? _kPrimaryGreen : _kInk,
        shape: const CircleBorder(),
      ),
      icon: busy
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 22),
    );
  }
}

class _ComposerReplyBar extends StatelessWidget {
  const _ComposerReplyBar({required this.message, required this.onCancel});

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 18, color: _kMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.displayText.isEmpty ? '원본 메시지' : message.displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: '답장 취소',
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '아직 메시지가 없습니다.',
        style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBubbleGreenA, _kBubbleGreenB],
        ),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _durationLabel(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

DateTime? _parseScheduleDate(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw.trim());
  if (match == null) {
    return null;
  }
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

TimeOfDay? _parseScheduleTime(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) {
    return null;
  }
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

List<CalendarProposalCandidate>? _proposalCandidatesOrNull(
  List<_CalendarProposalCandidateDraft> drafts,
) {
  if (drafts.length < 2 || drafts.length > 5) {
    return null;
  }
  final seen = <String>{};
  final candidates = <CalendarProposalCandidate>[];
  for (var index = 0; index < drafts.length; index++) {
    final date = _parseScheduleDate(drafts[index].dateController.text);
    final time = _parseScheduleTime(drafts[index].timeController.text);
    final duration = int.tryParse(drafts[index].durationController.text.trim());
    if (date == null ||
        time == null ||
        duration == null ||
        duration < 1 ||
        duration > 24 * 60) {
      return null;
    }
    final startAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!startAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return null;
    }
    final key = startAt.toIso8601String();
    if (!seen.add(key)) {
      return null;
    }
    candidates.add(
      CalendarProposalCandidate(
        id: 'candidate_${index + 1}',
        startAt: startAt,
        endAt: startAt.add(Duration(minutes: duration)),
      ),
    );
  }
  return candidates;
}

String _clockLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _scheduleLabel(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day ${_clockLabel(value)}';
}

String _proposalStatusLabel(CalendarProposal proposal) {
  if (proposal.isFinalized && proposal.finalCandidate != null) {
    return '확정됨 · ${DateFormat('M월 d일 HH:mm').format(proposal.finalCandidate!.startAt)}';
  }
  if (proposal.isCancelled) {
    return '취소됨';
  }
  return '일정 투표 중';
}

Color _proposalStatusColor(CalendarProposal proposal) {
  if (proposal.isFinalized) {
    return _kPrimaryGreen;
  }
  if (proposal.isCancelled) {
    return _kMuted;
  }
  return const Color(0xFF007C55);
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}

String _fileSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
