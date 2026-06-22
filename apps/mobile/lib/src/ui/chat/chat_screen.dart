import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/messenger_models.dart';
import '../../services/attachment_picker.dart';
import '../../services/browser_speech_recognizer.dart';
import '../../services/deepgram_streaming_stt.dart';
import '../../services/location_picker.dart';
import '../../services/messenger_backend.dart';
import '../../services/pcm_audio_processing.dart';
import '../../services/pcm_wav_writer.dart';
import '../../services/telemetry_service.dart';
import '../shared/profile_avatar.dart';
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
const _kPreferDeviceSttPrimary =
    bool.fromEnvironment('VERBAL_DEVICE_STT_PRIMARY', defaultValue: false) &&
    bool.fromEnvironment(
      'VERBAL_ENABLE_EXPERIMENTAL_DEVICE_STT_PRIMARY',
      defaultValue: false,
    );
const _kUseDeepgramLiveForKorean = bool.fromEnvironment(
  'VERBAL_USE_DEEPGRAM_LIVE_FOR_KO',
  defaultValue: true,
);
const _kRealtimeSttProvider = String.fromEnvironment(
  'VERBAL_REALTIME_STT_PROVIDER',
  defaultValue: 'auto',
);
const _kUseRealtimeSttForKorean =
    bool.fromEnvironment(
      'VERBAL_USE_REALTIME_STT_FOR_KO',
      defaultValue: false,
    ) ||
    _kUseDeepgramLiveForKorean ||
    _kRealtimeSttProvider == 'openai' ||
    _kRealtimeSttProvider == 'auto';
const _kAllowDeviceSttDuringVoiceRecording = bool.fromEnvironment(
  'VERBAL_ALLOW_DEVICE_STT_WITH_RECORDER',
  defaultValue: false,
);
const _kForceServerSttCorrection = bool.fromEnvironment(
  'VERBAL_FORCE_SERVER_STT_CORRECTION',
  defaultValue: false,
);
const _kUseVoiceRecognitionAudioSource = bool.fromEnvironment(
  'VERBAL_USE_VOICE_RECOGNITION_AUDIO_SOURCE',
  defaultValue: true,
);
const _kVoiceTranscriptWaitWhenEmpty = Duration(milliseconds: 600);
const _kSpeculativeVoiceSttEnabled = bool.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT',
  defaultValue: true,
);
const _kSpeculativeVoiceSttMinRecordingMs = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_MIN_RECORDING_MS',
  defaultValue: 1400,
);
const _kSpeculativeVoiceSttMinSpeechMs = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_MIN_SPEECH_MS',
  defaultValue: 700,
);
const _kSpeculativeVoiceSttMinBytes = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_MIN_BYTES',
  defaultValue: 48000,
);
const _kSpeculativeVoiceSttFollowUpMinRecordingMs = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_FOLLOW_UP_MIN_RECORDING_MS',
  defaultValue: 2600,
);
const _kSpeculativeVoiceSttFollowUpMinSpeechMs = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_FOLLOW_UP_MIN_SPEECH_MS',
  defaultValue: 1600,
);
const _kSpeculativeVoiceSttFollowUpMinBytes = int.fromEnvironment(
  'VERBAL_SPECULATIVE_VOICE_STT_FOLLOW_UP_MIN_BYTES',
  defaultValue: 80000,
);

String get _primaryRealtimeSttProvider {
  final configured = _kRealtimeSttProvider.trim().toLowerCase();
  if (configured == 'openai' || configured == 'deepgram') {
    return configured;
  }
  return 'openai';
}

String? get _fallbackRealtimeSttProvider {
  return _primaryRealtimeSttProvider == 'openai' ? 'deepgram' : null;
}

String _realtimeProviderLogLabel(String provider) =>
    provider == 'openai' ? 'openai_realtime' : 'deepgram_streaming';

String get _realtimeSttProviderLogLabel =>
    _realtimeProviderLogLabel(_primaryRealtimeSttProvider);

AndroidAudioSource get _androidVoiceAudioSource =>
    _kUseVoiceRecognitionAudioSource
    ? AndroidAudioSource.voiceRecognition
    : AndroidAudioSource.mic;

String _messagePreviewText(ChatMessage message) {
  if (message.kind != MessageKind.voice) {
    return message.displayText;
  }
  final voiceText = message.voiceTranscriptText.trim();
  if (voiceText.isNotEmpty) {
    return voiceText;
  }
  if (message.sttStatus == SttStatus.processing ||
      message.sttStatus == SttStatus.pending ||
      message.deliveryStatus == MessageDeliveryStatus.sending) {
    return '\uC74C\uC131 \uBCC0\uD658 \uC911...';
  }
  if (message.sttStatus == SttStatus.failed) {
    return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
  }
  return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
}

String _voiceBubbleBodyText(ChatMessage message) {
  final voiceText = message.voiceTranscriptText.trim();
  if (voiceText.isNotEmpty) {
    return voiceText;
  }
  if (message.deliveryStatus == MessageDeliveryStatus.sending ||
      message.sttStatus == SttStatus.processing ||
      message.sttStatus == SttStatus.pending) {
    return '\uC74C\uC131 \uBCC0\uD658 \uC911...';
  }
  if (message.sttStatus == SttStatus.failed) {
    return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
  }
  if ((message.audioPath ?? '').startsWith('voice_messages/')) {
    return '\uC74C\uC131 \uBCC0\uD658 \uC911...';
  }
  return '';
}

String _sanitizeVoiceTranscriptCandidate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  const placeholders = {
    '\uC74C\uC131 \uBA54\uC2DC\uC9C0',
    '\uC0C8 \uC74C\uC131 \uBA54\uC2DC\uC9C0',
    'Voice message',
    '\uC74C\uC131 \uBCC0\uD658 \uC911...',
    '\uC74C\uC131 \uBCC0\uD658 \uB300\uAE30 \uC911...',
    '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328',
    '\uC74C\uC131 \uBCC0\uD658\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.',
    '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC \uC5C6\uC74C',
    '\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC\uAC00 \uBE44\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.',
  };
  if (placeholders.contains(trimmed) ||
      _looksLikeCorruptedVoiceTranscript(trimmed)) {
    return '';
  }
  return trimmed;
}

bool _looksLikeCorruptedVoiceTranscript(String value) {
  if (value.contains('\uFFFD')) {
    return true;
  }
  const signals = [
    '\u7650',
    '\u7B4C',
    '\u63F6',
    '\u69AE',
    '\u6FE1',
    '\u5A9B',
    '\u8E42',
    '\uB69F',
    '\uAFB8',
    '\uF9CE',
    '\uBD83',
  ];
  final signalCount = signals.where(value.contains).length;
  if (signalCount >= 2) {
    return true;
  }
  final questionRuns = RegExp(r'\?{3,}').allMatches(value).length;
  return questionRuns >= 2 && signalCount >= 1;
}

bool _isBetterVoiceTranscriptCandidate(String candidate, String existing) {
  final next = _sanitizeVoiceTranscriptCandidate(candidate);
  if (next.isEmpty) {
    return false;
  }
  final current = _sanitizeVoiceTranscriptCandidate(existing);
  if (current.isEmpty) {
    return true;
  }
  final nextCompact = _compactVoiceTranscript(next);
  final currentCompact = _compactVoiceTranscript(current);
  if (nextCompact.isEmpty) {
    return false;
  }
  if (currentCompact.isEmpty) {
    return true;
  }
  if (nextCompact == currentCompact) {
    return false;
  }
  if (currentCompact.contains(nextCompact) &&
      currentCompact.length >= nextCompact.length) {
    return false;
  }
  if (nextCompact.contains(currentCompact) &&
      nextCompact.length > currentCompact.length) {
    return true;
  }
  return nextCompact.length > currentCompact.length;
}

String _compactVoiceTranscript(String value) {
  return value
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '')
      .toLowerCase();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.room, required this.user, super.key});

  final ChatRoom room;
  final AppUser user;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _searchController = TextEditingController();
  final _optimisticMessages = <String, ChatMessage>{};
  final _voiceTranscriptRecoveryQueued = <String>{};
  ChatMessage? _replyTo;
  String? _lastMarkedMessageId;
  var _searching = false;
  var _searchQuery = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    final roomProfile = contactProfileForLabel(widget.room.title);
    return Scaffold(
      backgroundColor: _kChatBackground,
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: _kDivider, width: 0.7)),
        title: Row(
          children: [
            _InitialAvatar(
              label: roomProfile.displayName,
              size: 34,
              avatarAsset: widget.room.type == RoomType.direct
                  ? roomProfile.avatarAsset
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomProfile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    switch (widget.room.type) {
                      RoomType.group => '\uADF8\uB8F9 \uB300\uD654',
                      RoomType.open => '\uC624\uD508\uCC44\uD305',
                      RoomType.direct => '1:1 \uB300\uD654',
                    },
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
            tooltip: '\uC74C\uC131 \uD1B5\uD654',
            onPressed: () => _showUnavailable('\uC74C\uC131 \uD1B5\uD654'),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: '\uC601\uC0C1 \uD1B5\uD654',
            onPressed: () => _showUnavailable('\uC601\uC0C1 \uD1B5\uD654'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          PopupMenuButton<Object>(
            tooltip: '\uB354 \uBCF4\uAE30',
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
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'search',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search_rounded),
                  title: Text('\uB300\uD654 \uAC80\uC0C9'),
                ),
              ),
              PopupMenuItem(
                value: 'info',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('\uB300\uD654 \uC815\uBCF4'),
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
                    message:
                        '\uBA54\uC2DC\uC9C0 \uB0B4\uC6A9\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0\uC744 \uD655\uC778\uD558\uACE0 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.',
                    detail: snapshot.error.toString(),
                    onRetry: () => setState(() {}),
                  );
                }
                final messages = snapshot.data ?? const <ChatMessage>[];
                final mergedMessages = _messagesWithOptimistic(messages);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    mergedMessages.isEmpty) {
                  return const _ChatConnectionState(
                    message:
                        '\uBA54\uC2DC\uC9C0\uB97C \uBD88\uB7EC\uC624\uB294 \uC911\uC785\uB2C8\uB2E4.',
                    progress: true,
                  );
                }
                if (mergedMessages.isEmpty) {
                  return const _EmptyChat();
                }
                if (messages.isNotEmpty) {
                  _markRead(messages);
                }
                final visibleMessages = _visibleMessages(mergedMessages);
                _recoverMissingVoiceTranscripts(visibleMessages);
                if (visibleMessages.isEmpty) {
                  return _searchQuery.trim().isEmpty
                      ? const _EmptyChat()
                      : const _SearchEmpty();
                }
                final pinnedMessages =
                    mergedMessages
                        .where((message) => message.isPinned)
                        .toList(growable: false)
                      ..sort(
                        (a, b) => (b.pinnedAt ?? b.createdAt).compareTo(
                          a.pinnedAt ?? a.createdAt,
                        ),
                      );
                return Column(
                  children: [
                    if (pinnedMessages.isNotEmpty &&
                        _searchQuery.trim().isEmpty)
                      _PinnedMessageBanner(
                        message: pinnedMessages.first,
                        count: pinnedMessages.length,
                        onShowActions: () =>
                            _showPinnedBannerActions(pinnedMessages),
                      ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                          final message =
                              visibleMessages[visibleMessages.length -
                                  1 -
                                  index];
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
                            onFinalizeCalendarProposal:
                                (proposal, candidateId) =>
                                    _finalizeCalendarProposal(
                                      proposal,
                                      candidateId,
                                    ),
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
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          MessageComposer(
            roomId: widget.room.id,
            currentUserId: widget.user.uid,
            sendMode: SendMode.instant,
            replyTo: _replyTo,
            onCancelReply: () => setState(() => _replyTo = null),
            onOptimisticVoiceMessage: _addOptimisticMessage,
            onRemoveOptimisticVoiceMessage: _removeOptimisticMessage,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label \uAE30\uB2A5\uC740 \uC544\uC9C1 \uC900\uBE44 \uC911\uC785\uB2C8\uB2E4.',
        ),
      ),
    );
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

  List<ChatMessage> _messagesWithOptimistic(List<ChatMessage> serverMessages) {
    if (_optimisticMessages.isEmpty) {
      return serverMessages;
    }
    final serverById = {
      for (final message in serverMessages) message.id: message,
    };
    final serverIds = serverById.keys.toSet();
    final deliveredIds = _optimisticMessages.keys
        .where((id) {
          final serverMessage = serverById[id];
          if (serverMessage == null) {
            return false;
          }
          final optimisticMessage = _optimisticMessages[id];
          if (optimisticMessage != null &&
              _shouldKeepOptimisticVoiceText(
                serverMessage,
                optimisticMessage,
              )) {
            return false;
          }
          return serverMessage.deliveryStatus != MessageDeliveryStatus.sending;
        })
        .toList(growable: false);
    if (deliveredIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          for (final id in deliveredIds) {
            _optimisticMessages.remove(id);
          }
        });
      });
    }
    final mergedMessages = serverMessages
        .map((message) {
          final optimisticMessage = _optimisticMessages[message.id];
          if (optimisticMessage != null &&
              _shouldKeepOptimisticVoiceText(message, optimisticMessage)) {
            return message.copyWith(
              text: _meaningfulVoiceText(optimisticMessage),
              transcript: _meaningfulVoiceText(optimisticMessage),
              sttStatus: SttStatus.completed,
            );
          }
          if (message.deliveryStatus == MessageDeliveryStatus.sending) {
            return _optimisticMessages[message.id] ?? message;
          }
          return message;
        })
        .toList(growable: true);
    final pendingMessages = _optimisticMessages.values
        .where((message) => !serverIds.contains(message.id))
        .toList(growable: false);
    if (pendingMessages.isEmpty) {
      return mergedMessages;
    }
    return <ChatMessage>[...mergedMessages, ...pendingMessages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  bool _shouldKeepOptimisticVoiceText(
    ChatMessage serverMessage,
    ChatMessage optimisticMessage,
  ) {
    if (serverMessage.kind != MessageKind.voice ||
        optimisticMessage.kind != MessageKind.voice ||
        serverMessage.isDeleted) {
      return false;
    }
    return _meaningfulVoiceText(serverMessage).isEmpty &&
        _meaningfulVoiceText(optimisticMessage).isNotEmpty;
  }

  String _meaningfulVoiceText(ChatMessage message) {
    final voiceText = message.voiceTranscriptText.trim();
    if (voiceText.isNotEmpty) {
      return voiceText;
    }
    final transcript = _sanitizeVoiceTranscriptCandidate(message.transcript);
    if (transcript.isNotEmpty) {
      return transcript;
    }
    return _sanitizeVoiceTranscriptCandidate(message.text);
  }

  void _addOptimisticMessage(ChatMessage message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _optimisticMessages[message.id] = message;
    });
  }

  void _removeOptimisticMessage(String messageId) {
    if (!mounted || !_optimisticMessages.containsKey(messageId)) {
      return;
    }
    setState(() {
      _optimisticMessages.remove(messageId);
    });
  }

  void _recoverMissingVoiceTranscripts(List<ChatMessage> messages) {
    final candidates = messages
        .where(_shouldRecoverMissingVoiceTranscript)
        .where((message) => _voiceTranscriptRecoveryQueued.add(message.id))
        .take(3)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final backend = BackendScope.of(context);
      for (final message in candidates) {
        unawaited(
          backend
              .recoverClientVoiceMessageTranscript(
                roomId: widget.room.id,
                messageId: message.id,
              )
              .then((_) {
                debugPrint(
                  'voice_transcript_auto_recovery_completed '
                  'messageId=${message.id}',
                );
              })
              .catchError((Object error) {
                debugPrint(
                  'voice_transcript_auto_recovery_failed '
                  'messageId=${message.id} error=$error',
                );
              }),
        );
      }
    });
  }

  bool _shouldRecoverMissingVoiceTranscript(ChatMessage message) {
    final audioPath = message.audioPath ?? '';
    if (message.kind != MessageKind.voice ||
        message.isDeleted ||
        message.voiceTranscriptText.trim().isNotEmpty ||
        !audioPath.startsWith('voice_messages/') ||
        message.deliveryStatus != MessageDeliveryStatus.sent) {
      return false;
    }
    return message.sttStatus == SttStatus.processing ||
        message.sttStatus == SttStatus.pending ||
        message.sttStatus == SttStatus.failed ||
        message.sttStatus == SttStatus.completed ||
        message.sttStatus == SttStatus.none;
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
    final controller = TextEditingController(
      text: _messagePreviewText(message),
    );
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
                    '\uBA54\uC2DC\uC9C0 \uC218\uC815',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 2,
                    maxLines: 6,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '\uB0B4\uC6A9',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text.trim()),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('\uC800\uC7A5'),
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
      final message = error.toString();
      if (message.contains('unauthorized') ||
          message.contains('not authorized') ||
          message.contains('permission')) {
        _showError(
          '\uBA54\uC2DC\uC9C0\uB97C \uC218\uC815\uD560 \uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4. \uBCF8\uC778\uC774 \uBCF4\uB0B8 \uBA54\uC2DC\uC9C0\uB9CC \uC218\uC815\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
        );
        return;
      }
      _showError(
        '\uBA54\uC2DC\uC9C0\uB97C \uC218\uC815\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.',
      );
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await BackendScope.of(
        context,
      ).deleteMessage(roomId: widget.room.id, messageId: message.id);
    } catch (error) {
      final message = error.toString();
      if (message.contains('unauthorized') ||
          message.contains('not authorized') ||
          message.contains('permission')) {
        _showError(
          '\uBA54\uC2DC\uC9C0\uB97C \uC0AD\uC81C\uD560 \uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4. \uBCF8\uC778\uC774 \uBCF4\uB0B8 \uBA54\uC2DC\uC9C0\uB9CC \uC0AD\uC81C\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
        );
        return;
      }
      _showError(
        '\uBA54\uC2DC\uC9C0\uB97C \uC0AD\uC81C\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.',
      );
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
                      '\uC2E0\uACE0 \uC0AC\uC720',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final item in const [
                    ('spam', '\uC2A4\uD338 \uB610\uB294 \uAD11\uACE0'),
                    (
                      'abuse',
                      '\uAD34\uB86D\uD798 \uB610\uB294 \uD610\uC624 \uD45C\uD604',
                    ),
                    (
                      'unsafe',
                      '\uBD80\uC801\uC808\uD558\uAC70\uB098 \uC704\uD5D8\uD55C \uCF58\uD150\uCE20',
                    ),
                    ('other', '\uAE30\uD0C0'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\uC2E0\uACE0\uAC00 \uC811\uC218\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
            ),
          ),
        );
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

  Future<void> _showPinnedBannerActions(
    List<ChatMessage> pinnedMessages,
  ) async {
    if (pinnedMessages.isEmpty) {
      return;
    }
    final messages = pinnedMessages.toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4E4E7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  messages.length > 1
                      ? '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0 ${messages.length}\uAC1C'
                      : '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0',
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0\uB97C \uAE38\uAC8C \uB20C\uB7EC \uACE0\uC815\uC744 \uD574\uC81C\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: messages.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8FFF4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.push_pin_rounded,
                            color: _kPrimaryGreen,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          _pinnedMessagePreview(message),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          DateFormat('M/d HH:mm').format(message.createdAt),
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_unpinPinnedMessage(message));
                          },
                          child: const Text('\uACE0\uC815 \uD574\uC81C'),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(_unpinPinnedMessage(message));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _pinnedMessagePreview(ChatMessage message) {
    final preview = _messagePreviewText(message).trim();
    return preview.isEmpty ? '\uB0B4\uC6A9 \uC5C6\uC74C' : preview;
  }

  Future<void> _unpinPinnedMessage(ChatMessage message) async {
    try {
      await BackendScope.of(
        context,
      ).unpinMessage(roomId: widget.room.id, messageId: message.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0\uB97C \uD574\uC81C\uD588\uC2B5\uB2C8\uB2E4.',
            ),
          ),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0\uB97C \uD574\uC81C\uD588\uC2B5\uB2C8\uB2E4.',
              ),
            ),
          );
        }
      } else {
        await backend.pinMessage(roomId: widget.room.id, messageId: message.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '\uBA54\uC2DC\uC9C0\uB97C \uACE0\uC815\uD588\uC2B5\uB2C8\uB2E4.',
              ),
            ),
          );
        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\uC77C\uC815\uC774 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
            ),
          ),
        );
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
            hintText: '\uB300\uD654 \uAC80\uC0C9',
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
        '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
        style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PinnedMessageBanner extends StatelessWidget {
  const _PinnedMessageBanner({
    required this.message,
    required this.count,
    required this.onShowActions,
  });

  final ChatMessage message;
  final int count;
  final VoidCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final preview = _messagePreviewText(message).trim();
    return Semantics(
      button: true,
      label:
          '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4. \uAE38\uAC8C \uB204\uB974\uBA74 \uACE0\uC815 \uD574\uC81C \uBA54\uB274\uAC00 \uC5F4\uB9BD\uB2C8\uB2E4.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onShowActions,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FFF4),
            border: Border.all(color: const Color(0xFFBFEEDB)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _kPrimaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.push_pin_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      count > 1
                          ? '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0 $count\uAC1C'
                          : '\uACE0\uC815\uB41C \uBA54\uC2DC\uC9C0',
                      style: const TextStyle(
                        color: _kPrimaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.isEmpty ? '\uB0B4\uC6A9 \uC5C6\uC74C' : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.more_horiz_rounded,
                color: _kPrimaryGreen,
                size: 20,
              ),
            ],
          ),
        ),
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
                label: const Text('\uB2E4\uC2DC \uC2DC\uB3C4'),
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
    final isVoiceMessage =
        widget.message.kind == MessageKind.voice && !widget.message.isDeleted;
    final bodyText = proposal != null
        ? ''
        : widget.message.isDeleted
        ? widget.message.displayText
        : isVoiceMessage
        ? _voiceBubbleBodyText(widget.message)
        : widget.message.text.trim().isNotEmpty
        ? widget.message.text.trim()
        : widget.message.transcript.trim().isNotEmpty
        ? widget.message.transcript.trim()
        : '';
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
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
                leadingContent(_PinnedLabel(isMine: widget.isMine)),
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
                  widget.message.audioExpired &&
                  !widget.message.isDeleted) ...[
                const SizedBox(height: 6),
                leadingContent(
                  Text(
                    '\uC74C\uC131 \uD30C\uC77C \uBCF4\uC874\uAE30\uAC04\uC774 \uB9CC\uB8CC\uB418\uC5B4 \uC6D0\uBCF8 \uC74C\uC131\uC740 \uC7AC\uC0DD\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (bodyText.isNotEmpty) ...[
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
                  if (widget.message.deliveryStatus !=
                      MessageDeliveryStatus.sent) ...[
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
                      '\uC218\uC815\uB428(edited)',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.58),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (isVoiceMessage && widget.message.durationMs > 0) ...[
                    Text(
                      _durationLabel(widget.message.durationMs),
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.68),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ' \u00B7 ',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
    final bubbleTarget = GestureDetector(
      onLongPress: _showActions,
      child: bubble,
    );
    final messageContent = isVoiceMessage
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: widget.isMine
                ? [
                    _VoicePlaybackButton(
                      playing: _playing,
                      onPressed: !widget.message.hasPlayableAudio
                          ? null
                          : _togglePlayback,
                    ),
                    const SizedBox(width: 5),
                    Flexible(child: bubbleTarget),
                  ]
                : [
                    Flexible(child: bubbleTarget),
                    const SizedBox(width: 5),
                    _VoicePlaybackButton(
                      playing: _playing,
                      onPressed: !widget.message.hasPlayableAudio
                          ? null
                          : _togglePlayback,
                    ),
                  ],
          )
        : bubbleTarget;

    final roomProfile = contactProfileForLabel(widget.roomTitle);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: widget.isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMine) ...[
            _InitialAvatar(
              label: roomProfile.displayName,
              size: 28,
              avatarAsset: roomProfile.avatarAsset,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(child: messageContent),
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
                    title: const Text('\uB2F5\uC7A5'),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onReply();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_reaction_outlined),
                    title: const Text('\uBC18\uC751'),
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
                    title: Text(
                      widget.message.isPinned
                          ? '\uACE0\uC815 \uD574\uC81C'
                          : '\uBA54\uC2DC\uC9C0 \uACE0\uC815',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPin();
                    },
                  ),
                  if (widget.onEdit != null)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('\uC218\uC815'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onEdit!();
                      },
                    ),
                  if (widget.onDelete != null)
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: Text(
                        widget.message.isScheduled
                            ? '\uC608\uC57D \uCDE8\uC18C'
                            : '\uC0AD\uC81C',
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onDelete!();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('\uC601\uC5B4\uB85C \uBC88\uC5ED'),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onTranslate();
                    },
                  ),
                  if (widget.onSendNow != null)
                    ListTile(
                      leading: const Icon(Icons.send_time_extension_rounded),
                      title: const Text('\uC9C0\uAE08 \uBCF4\uB0B4\uAE30'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onSendNow!();
                      },
                    ),
                  if (widget.onReport != null)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('\uC2E0\uACE0'),
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
      final audioPath = widget.message.audioPath;
      if (audioPath != null && audioPath.startsWith('voice_drafts/')) {
        _showError(
          '\uC804\uC1A1 \uCC98\uB9AC \uC911\uC778 \uC784\uC2DC \uC74C\uC131 \uD30C\uC77C\uC785\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.',
        );
        return;
      }
      final uri = await BackendScope.of(context).audioUri(audioPath);
      if (uri == null) {
        _showError(
          '\uC7AC\uC0DD\uD560 \uC218 \uC788\uB294 \uC74C\uC131 \uD30C\uC77C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
        );
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
                  label: const Text('\uD22C\uD45C \uC800\uC7A5'),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(onCancel()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kMuted,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('\uD655\uC815'),
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
              label: const Text('\uB0B4 \uC77C\uC815\uC5D0 \uCD94\uAC00'),
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
                  DateFormat(
                    "M'\uC6D4' d'\uC77C' HH:mm",
                  ).format(candidate.startAt),
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${candidate.durationMinutes}\uBD84 \u00B7 $voteCount\uD45C',
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
              child: const Text('\uD655\uC815'),
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
        reply.preview.isEmpty
            ? '\uC6D0\uBCF8 \uBA54\uC2DC\uC9C0'
            : reply.preview,
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
          scheduledAt == null
              ? '\uC608\uC57D \uBA54\uC2DC\uC9C0'
              : '${_clockLabel(scheduledAt!)} \uC608\uC57D',
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
  const _PinnedLabel({required this.isMine});

  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : _kPrimaryGreen;
    final background = isMine
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFE8FFF4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin_rounded, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            '\uACE0\uC815',
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
    return const Text(
      '\uC6D0\uD558\uB294 \uBC18\uC751\uC744 \uC120\uD0DD\uD558\uC138\uC694.',
    );
  }
}

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _items = [
    '\u{1F44D}',
    '\u{1F602}',
    '\u{1F60D}',
    '\u{1F622}',
    '\u{1F525}',
  ];

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

class _VoicePlaybackButton extends StatelessWidget {
  const _VoicePlaybackButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: playing ? 'Pause' : 'Play',
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.42,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? _kPrimaryGreen : const Color(0xFFD9DED9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ),
      ),
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
              '\uC77C\uC815 \uC81C\uC548',
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
                labelText: '\uC81C\uBAA9',
                hintText: '\uBB34\uC2A8 \uC77C\uC815\uC778\uAC00\uC694?',
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
                labelText: '\uC0C1\uC138 \uB0B4\uC6A9',
                hintText:
                    '\uC7A5\uC18C, \uC900\uBE44\uBB3C, \uBA54\uBAA8\uB97C \uC785\uB825\uD558\uC138\uC694.',
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
                labelText: '\uC74C\uC131 \uBCC0\uD658 \uD14D\uC2A4\uD2B8',
                hintText:
                    '\uC74C\uC131\uC73C\uB85C \uB9CC\uB4E0 \uCD08\uC548\uC774\uBA74 \uC6D0\uBB38\uC774 \uB0A8\uC2B5\uB2C8\uB2E4.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '\uD6C4\uBCF4 \uC2DC\uAC04',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '\uD6C4\uBCF4 \uCD94\uAC00',
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
                '\uD6C4\uBCF4\uB294 2~5\uAC1C\uAE4C\uC9C0 \uAC00\uB2A5\uD558\uBA70 \uB0A0\uC9DC\uB294 YYYY-MM-DD, \uC2DC\uAC04\uC740 HH:MM \uD615\uC2DD\uC73C\uB85C \uC785\uB825\uD574 \uC8FC\uC138\uC694.',
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
              label: const Text('\uC81C\uC548 \uBCF4\uB0B4\uAE30'),
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
                  '\uD6C4\uBCF4 ${index + 1}',
                  style: const TextStyle(
                    color: _kInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '\uD6C4\uBCF4 \uC0AD\uC81C',
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
                    labelText: '\uB0A0\uC9DC',
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
                    labelText: '\uC2DC\uAC04',
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
              labelText: '\uAE30\uAC04',
              hintText: '\uBD84 \uB2E8\uC704',
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

class VoiceSttSession {
  VoiceSttSession({required this.startedAt});

  final DateTime startedAt;
  String lastInterimTranscript = '';
  String lastStableTranscript = '';
  DateTime? firstAudioSentAt;
  DateTime? firstSpeechAt;
  DateTime? firstPartialAt;
  DateTime? lastUpdateAt;
  String? errorCode;
  double maxInputRms = 0;
  int maxInputPeak = 0;

  String get transcript {
    return _mergeVoiceTranscriptParts(
      lastStableTranscript,
      lastInterimTranscript,
    );
  }

  bool get hasTranscript => transcript.isNotEmpty;

  void markAudioSent(DateTime sentAt) {
    firstAudioSentAt ??= sentAt;
  }

  void markSpeechDetected(DateTime detectedAt) {
    firstSpeechAt ??= detectedAt;
  }

  void observeAudioLevel(Pcm16AudioLevel level) {
    if (level.rms > maxInputRms) {
      maxInputRms = level.rms;
    }
    if (level.peak > maxInputPeak) {
      maxInputPeak = level.peak;
    }
  }

  void apply(VoiceSttSnapshot snapshot) {
    lastInterimTranscript = snapshot.lastInterimTranscript.trim();
    lastStableTranscript = snapshot.lastStableTranscript.trim();
    firstAudioSentAt = snapshot.firstAudioSentAt ?? firstAudioSentAt;
    firstSpeechAt = snapshot.firstSpeechAt ?? firstSpeechAt;
    firstPartialAt = snapshot.firstPartialAt ?? firstPartialAt;
    lastUpdateAt = snapshot.lastUpdateAt ?? lastUpdateAt;
    errorCode = snapshot.errorCode ?? errorCode;
  }

  void applyDeepgram(DeepgramLiveSnapshot snapshot) {
    if (snapshot.transcript.isNotEmpty) {
      lastInterimTranscript = snapshot.lastInterimTranscript.trim();
      lastStableTranscript = snapshot.lastStableTranscript.trim();
    }
    firstAudioSentAt = _earliestDate(
      firstAudioSentAt,
      snapshot.firstAudioSentAt,
    );
    firstSpeechAt = _earliestDate(firstSpeechAt, snapshot.firstSpeechAt);
    firstPartialAt = _earliestDate(firstPartialAt, snapshot.firstPartialAt);
    lastUpdateAt = snapshot.lastUpdateAt ?? lastUpdateAt;
    errorCode = snapshot.errorCode ?? errorCode;
  }

  VoiceSttSnapshot snapshot() {
    return VoiceSttSnapshot(
      lastInterimTranscript: lastInterimTranscript,
      lastStableTranscript: lastStableTranscript,
      startedAt: startedAt,
      firstAudioSentAt: firstAudioSentAt,
      firstSpeechAt: firstSpeechAt,
      firstPartialAt: firstPartialAt,
      lastUpdateAt: lastUpdateAt,
      errorCode: errorCode,
    );
  }
}

DateTime? _earliestDate(DateTime? current, DateTime? next) {
  if (current == null) {
    return next;
  }
  if (next == null) {
    return current;
  }
  return next.isBefore(current) ? next : current;
}

String _mergeVoiceTranscriptParts(String stable, String interim) {
  final left = stable.trim();
  final right = interim.trim();
  if (left.isEmpty) {
    return right;
  }
  if (right.isEmpty) {
    return left;
  }
  final normalizedLeft = _normalizeVoiceTranscriptForMerge(left);
  final normalizedRight = _normalizeVoiceTranscriptForMerge(right);
  if (normalizedLeft.contains(normalizedRight)) {
    return left;
  }
  if (normalizedRight.contains(normalizedLeft)) {
    return right;
  }
  final leftTokens = left.split(RegExp(r'\s+'));
  final rightTokens = right.split(RegExp(r'\s+'));
  final maxOverlap = leftTokens.length < rightTokens.length
      ? leftTokens.length
      : rightTokens.length;
  for (var size = maxOverlap; size > 0; size -= 1) {
    final leftSuffix = leftTokens.sublist(leftTokens.length - size).join(' ');
    final rightPrefix = rightTokens.sublist(0, size).join(' ');
    if (_normalizeVoiceTranscriptForMerge(leftSuffix) ==
        _normalizeVoiceTranscriptForMerge(rightPrefix)) {
      return [...leftTokens, ...rightTokens.sublist(size)].join(' ').trim();
    }
  }
  return '$left $right'.trim();
}

String _normalizeVoiceTranscriptForMerge(String value) {
  return value
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '')
      .toLowerCase();
}

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.roomId,
    required this.currentUserId,
    required this.sendMode,
    required this.replyTo,
    required this.onCancelReply,
    required this.onOptimisticVoiceMessage,
    required this.onRemoveOptimisticVoiceMessage,
    required this.onSent,
    super.key,
  });

  final String roomId;
  final String currentUserId;
  final SendMode sendMode;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;
  final ValueChanged<ChatMessage> onOptimisticVoiceMessage;
  final ValueChanged<String> onRemoveOptimisticVoiceMessage;
  final VoidCallback onSent;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  static const _debugVoiceChannel = MethodChannel('verbal/debug_voice');
  static const _voiceFinalTranscriptGrace = Duration(milliseconds: 1000);

  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  final _speechRecognizer = DeviceStreamingStt();
  final _pcmDeviceSpeechRecognizer = PcmDeviceStreamingStt();
  final _stopwatch = Stopwatch();
  Timer? _timer;
  VoiceSttSession? _voiceSttSession;
  DeepgramStreamingStt? _deepgramStreamingStt;
  DeepgramStreamingStt? _preconnectedDeepgramStt;
  Future<DeepgramStreamingStt?>? _deepgramPreconnectFuture;
  StreamSubscription<Uint8List>? _recordStreamSub;
  BytesBuilder? _recordStreamBytes;
  var _recordStreamByteCount = 0;
  String? _streamRecordingPath;
  Future<VoiceInlineSttResult?>? _speculativeVoiceSttFuture;
  DateTime? _speculativeVoiceSttStartedAt;
  Future<VoiceInlineSttResult?>? _speculativeVoiceSttFollowUpFuture;
  DateTime? _speculativeVoiceSttFollowUpStartedAt;
  Timer? _deepgramLiveRecoveryTimer;
  Timer? _deepgramPreconnectRetryTimer;
  var _deepgramLiveRecoveryInFlight = false;
  var _deepgramLiveRecoveryAttempts = 0;
  var _deepgramPreconnectGeneration = 0;
  DateTime? _deepgramStreamingDisabledUntil;
  var _recording = false;
  var _busy = false;
  var _deviceSttActive = false;
  var _pcmDeviceSttActive = false;
  var _deepgramSttActive = false;
  var _freeSttActive = false;
  var _liveTranscript = '';
  String? _busyLabel;

  String get _currentVoiceTranscript =>
      (_voiceSttSession?.transcript.trim().isNotEmpty == true
              ? _voiceSttSession!.transcript
              : _liveTranscript)
          .trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureDeepgramPreconnect();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _cancelDeepgramPreconnect();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ensureDeepgramPreconnect();
        }
      });
    }
  }

  @override
  void dispose() {
    _deepgramPreconnectGeneration += 1;
    _timer?.cancel();
    _deepgramLiveRecoveryTimer?.cancel();
    _deepgramPreconnectRetryTimer?.cancel();
    _textController.dispose();
    unawaited(_recordStreamSub?.cancel());
    unawaited(_deepgramStreamingStt?.cancel());
    unawaited(_preconnectedDeepgramStt?.cancel());
    unawaited(_speechRecognizer.cancel());
    unawaited(_pcmDeviceSpeechRecognizer.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  DeepgramStreamingStt _newDeepgramStreamingStt({String? provider}) {
    final realtimeProvider = provider ?? _primaryRealtimeSttProvider;
    return DeepgramStreamingStt(
      providerLabel: _realtimeProviderLogLabel(realtimeProvider),
      tokenProvider: () =>
          BackendScope.of(context).createDeepgramStreamingToken(
            language: 'ko-KR',
            provider: realtimeProvider,
          ),
    );
  }

  Future<DeepgramStreamingStt?> _ensureDeepgramPreconnect() {
    if (kIsWeb ||
        !_kUseRealtimeSttForKorean ||
        !DeepgramStreamingStt.enabled ||
        _deepgramStreamingTemporarilyDisabled ||
        _recording) {
      return Future<DeepgramStreamingStt?>.value(null);
    }
    final existing = _preconnectedDeepgramStt;
    if (existing != null && existing.isReady) {
      return Future<DeepgramStreamingStt?>.value(existing);
    }
    final pending = _deepgramPreconnectFuture;
    if (pending != null) {
      return pending;
    }
    final generation = ++_deepgramPreconnectGeneration;
    final primaryProvider = _primaryRealtimeSttProvider;
    final stt = _newDeepgramStreamingStt(provider: primaryProvider);
    late final Future<DeepgramStreamingStt?> future;
    future =
        (() async {
              final startedAt = DateTime.now();
              final started = await stt.start(startedAt: startedAt);
              if (!mounted || generation != _deepgramPreconnectGeneration) {
                await stt.cancel();
                return null;
              }
              if (!started) {
                final fallbackProvider = _fallbackRealtimeSttProvider;
                if (fallbackProvider != null &&
                    fallbackProvider != primaryProvider) {
                  await stt.cancel();
                  final fallbackStartedAt = DateTime.now();
                  final fallbackStt = _newDeepgramStreamingStt(
                    provider: fallbackProvider,
                  );
                  final fallbackStarted = await fallbackStt.start(
                    startedAt: fallbackStartedAt,
                  );
                  if (!mounted || generation != _deepgramPreconnectGeneration) {
                    await fallbackStt.cancel();
                    return null;
                  }
                  if (fallbackStarted) {
                    _preconnectedDeepgramStt = fallbackStt;
                    debugPrint(
                      'voice_stt_preconnect_fallback_ready '
                      'primary=${_realtimeProviderLogLabel(primaryProvider)} '
                      'provider=${_realtimeProviderLogLabel(fallbackProvider)} '
                      'connectMs=${DateTime.now().difference(fallbackStartedAt).inMilliseconds}',
                    );
                    return fallbackStt;
                  }
                  await fallbackStt.cancel();
                }
                debugPrint(
                  'voice_stt_preconnect_unavailable '
                  'provider=${_realtimeProviderLogLabel(primaryProvider)}',
                );
                _disableDeepgramStreamingTemporarily(
                  reason: 'preconnect_unavailable',
                );
                await stt.cancel();
                _scheduleDeepgramPreconnectRetry(generation);
                return null;
              }
              _preconnectedDeepgramStt = stt;
              debugPrint(
                'voice_stt_preconnect_ready '
                'provider=${_realtimeProviderLogLabel(primaryProvider)} '
                'connectMs=${DateTime.now().difference(startedAt).inMilliseconds}',
              );
              return stt;
            })()
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                'voice_stt_preconnect_failed '
                'provider=${_realtimeProviderLogLabel(primaryProvider)} '
                'error=$error',
              );
              debugPrintStack(stackTrace: stackTrace);
              _disableDeepgramStreamingTemporarily(reason: 'preconnect_failed');
              unawaited(stt.cancel());
              _scheduleDeepgramPreconnectRetry(generation);
              return null;
            })
            .whenComplete(() {
              if (_deepgramPreconnectFuture == future) {
                _deepgramPreconnectFuture = null;
              }
            });
    _deepgramPreconnectFuture = future;
    return future;
  }

  DeepgramStreamingStt _takeOrCreateDeepgramStt() {
    _deepgramPreconnectGeneration += 1;
    final prepared = _preconnectedDeepgramStt;
    _preconnectedDeepgramStt = null;
    if (prepared != null && prepared.isReady) {
      return prepared;
    }
    unawaited(prepared?.cancel());
    return _newDeepgramStreamingStt();
  }

  Future<void> _warmDeepgramBeforeRecording() async {
    if (kIsWeb ||
        !_kUseRealtimeSttForKorean ||
        !DeepgramStreamingStt.enabled ||
        _deepgramStreamingTemporarilyDisabled) {
      return;
    }
    final existing = _preconnectedDeepgramStt;
    if (existing != null && existing.isReady) {
      return;
    }
    final future = _deepgramPreconnectFuture ?? _ensureDeepgramPreconnect();
    final prepared = await future.timeout(
      const Duration(milliseconds: 1800),
      onTimeout: () => null,
    );
    if (prepared != null && prepared.isReady) {
      _preconnectedDeepgramStt = prepared;
    }
  }

  void _cancelDeepgramPreconnect() {
    _deepgramPreconnectGeneration += 1;
    _deepgramPreconnectFuture = null;
    _deepgramPreconnectRetryTimer?.cancel();
    _deepgramPreconnectRetryTimer = null;
    unawaited(_preconnectedDeepgramStt?.cancel());
    _preconnectedDeepgramStt = null;
  }

  void _scheduleDeepgramPreconnectRetry(int generation) {
    _deepgramPreconnectRetryTimer?.cancel();
    _deepgramPreconnectRetryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted &&
          generation == _deepgramPreconnectGeneration &&
          !_recording) {
        _ensureDeepgramPreconnect();
      }
    });
  }

  bool get _deepgramStreamingTemporarilyDisabled {
    final disabledUntil = _deepgramStreamingDisabledUntil;
    return disabledUntil != null && disabledUntil.isAfter(DateTime.now());
  }

  void _disableDeepgramStreamingTemporarily({required String reason}) {
    _deepgramStreamingDisabledUntil = DateTime.now().add(
      const Duration(minutes: 10),
    );
    debugPrint(
      'voice_stt_provider_disabled provider=$_realtimeSttProviderLogLabel '
      'reason=$reason disabledMinutes=10',
    );
  }

  void _scheduleNextDeepgramPreconnect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_recording) {
        _ensureDeepgramPreconnect();
      }
    });
  }

  void _cancelDeepgramLiveRecovery() {
    _deepgramLiveRecoveryTimer?.cancel();
    _deepgramLiveRecoveryTimer = null;
  }

  void _scheduleDeepgramLiveRecovery({required String reason}) {
    if (!_recording ||
        !_deepgramSttActive ||
        _voiceSttSession?.firstPartialAt != null ||
        _deepgramLiveRecoveryInFlight ||
        _deepgramLiveRecoveryAttempts >= 1) {
      return;
    }
    _deepgramLiveRecoveryTimer?.cancel();
    _deepgramLiveRecoveryTimer = Timer(const Duration(milliseconds: 3500), () {
      unawaited(_recoverDeepgramLiveStream(reason: reason));
    });
  }

  Future<void> _recoverDeepgramLiveStream({required String reason}) async {
    if (!mounted ||
        !_recording ||
        !_deepgramSttActive ||
        _deepgramLiveRecoveryInFlight ||
        _deepgramLiveRecoveryAttempts >= 1 ||
        _voiceSttSession?.firstPartialAt != null) {
      return;
    }
    final pcmBytes = _recordStreamBytes?.toBytes();
    if (pcmBytes == null || pcmBytes.length < 16000) {
      return;
    }
    _deepgramLiveRecoveryInFlight = true;
    _deepgramLiveRecoveryAttempts += 1;
    final previous = _deepgramStreamingStt;
    final replacement = _newDeepgramStreamingStt();
    final sessionStartedAt = _voiceSttSession?.startedAt ?? DateTime.now();
    final firstSpeechAt = _voiceSttSession?.firstSpeechAt;
    final startedAt = DateTime.now();
    try {
      final started = await replacement
          .start(
            startedAt: sessionStartedAt,
            onTranscript: _handleDeepgramTranscript,
            onSnapshot: _handleDeepgramSnapshot,
          )
          .timeout(const Duration(milliseconds: 3500), onTimeout: () => false);
      if (!mounted || !_recording || !started) {
        await replacement.cancel();
        return;
      }
      _deepgramStreamingStt = replacement;
      if (firstSpeechAt != null) {
        replacement.markSpeechDetected(firstSpeechAt);
      }
      const chunkSize = 6400;
      for (var offset = 0; offset < pcmBytes.length; offset += chunkSize) {
        final end = offset + chunkSize > pcmBytes.length
            ? pcmBytes.length
            : offset + chunkSize;
        replacement.sendAudio(Uint8List.sublistView(pcmBytes, offset, end));
      }
      unawaited(previous?.cancel());
      debugPrint(
        'voice_stt_live_recovery_started provider=$_realtimeSttProviderLogLabel '
        'reason=$reason '
        'bufferBytes=${pcmBytes.length} '
        'connectMs=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
    } catch (error) {
      debugPrint(
        'voice_stt_live_recovery_failed provider=$_realtimeSttProviderLogLabel '
        'reason=$reason error=$error',
      );
      await replacement.cancel();
    } finally {
      _deepgramLiveRecoveryInFlight = false;
    }
  }

  void _handleDeepgramTranscript(String transcript) {
    if (!mounted) {
      return;
    }
    if (transcript.trim().isNotEmpty) {
      _cancelDeepgramLiveRecovery();
    }
    setState(() {
      _liveTranscript = transcript.trim();
      _voiceSttSession?.lastStableTranscript = transcript.trim();
      _voiceSttSession?.firstPartialAt ??= DateTime.now();
      _voiceSttSession?.lastUpdateAt = DateTime.now();
    });
  }

  void _handleDeepgramSnapshot(DeepgramLiveSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    if (snapshot.transcript.trim().isNotEmpty) {
      _cancelDeepgramLiveRecovery();
    }
    setState(() {
      _voiceSttSession?.applyDeepgram(snapshot);
      _liveTranscript = snapshot.transcript;
    });
  }

  void _handlePcmDeviceTranscript(String transcript) {
    if (!mounted) {
      return;
    }
    setState(() {
      _liveTranscript = transcript.trim();
      _voiceSttSession?.lastStableTranscript = transcript.trim();
      _voiceSttSession?.firstPartialAt ??= DateTime.now();
      _voiceSttSession?.lastUpdateAt = DateTime.now();
    });
  }

  void _handlePcmDeviceSnapshot(VoiceSttSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceSttSession?.apply(snapshot);
      _liveTranscript = snapshot.transcript;
    });
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
                        '\uB179\uC74C \uC911 ${_durationLabel(_stopwatch.elapsedMilliseconds)}',
                        style: const TextStyle(
                          color: Color(0xFFD92D20),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _deepgramSttActive
                            ? 'Deepgram \uC2E4\uC2DC\uAC04'
                            : _deviceSttActive
                            ? '\uC2E4\uC2DC\uAC04 \uBCC0\uD658'
                            : '\uC11C\uBC84 \uBCF4\uC815 \uB300\uAE30',
                        style: TextStyle(
                          color:
                              (_deepgramSttActive || _deviceSttActive
                                      ? _kPrimaryGreen
                                      : _kMuted)
                                  .withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentVoiceTranscript.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF8F1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _currentVoiceTranscript,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              if (_busy) ...[
                _ComposerProgress(
                  label: _busyLabel ?? '\uCC98\uB9AC \uC911\uC785\uB2C8\uB2E4.',
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _showAttachmentSheet,
                    tooltip: '\uCCA8\uBD80',
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
                        onSubmitted: (_) => _sendComposer(),
                        decoration: const InputDecoration(
                          hintText: '\uBA54\uC2DC\uC9C0...',
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
                    tooltip: _recording
                        ? '\uB179\uC74C \uC911\uC9C0'
                        : '\uC74C\uC131 \uB179\uC74C',
                    onPressed: _busy ? null : _toggleRecording,
                    icon: _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    active: _recording,
                  ),
                  _ComposerIconButton(
                    tooltip: '\uC608\uC57D \uC804\uC1A1',
                    onPressed: _busy ? null : _showScheduleSheet,
                    icon: Icons.schedule_send_rounded,
                  ),
                  _ComposerIconButton(
                    tooltip: '\uC804\uC1A1',
                    onPressed: _busy ? null : _sendComposer,
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

  Future<void> _sendComposer() async {
    if (_recording) {
      debugPrint('voice_send_button_pressed whileRecording=true');
      await _stopRecording();
      return;
    }
    await _sendText();
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (_shouldWarnAboutLink(text)) {
      final confirmed = await _confirmLinkSend(text);
      if (confirmed != true || !mounted) {
        return;
      }
    }
    final backend = BackendScope.of(context);
    final replyToMessageId = widget.replyTo?.id;
    _textController.clear();
    widget.onSent();
    unawaited(
      backend
          .sendTextMessage(
            roomId: widget.roomId,
            text: text,
            replyToMessageId: replyToMessageId,
          )
          .catchError((Object error, StackTrace stackTrace) {
            if (!mounted) {
              return;
            }
            if (_textController.text.trim().isEmpty) {
              _textController.text = text;
            }
            _showError(error.toString());
          }),
    );
  }

  bool _shouldWarnAboutLink(String value) {
    final lower = value.toLowerCase();
    return RegExp(
          r'(https?:\/\/|www\.|[a-z0-9-]+\.[a-z]{2,})',
        ).hasMatch(lower) ||
        lower.contains('bit.ly') ||
        lower.contains('tinyurl') ||
        lower.contains('t.me/') ||
        lower.contains('open.kakao');
  }

  Future<bool?> _confirmLinkSend(String text) {
    unawaited(AppTelemetry.logEvent('suspicious_link_warning_shown'));
    final preview = text.length > 120 ? '${text.substring(0, 120)}...' : text;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '링크를 보내시겠어요?',
                  style: TextStyle(
                    color: _kInk,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '피싱이나 사칭 링크일 수 있으니 상대방에게 보낼 주소를 한 번 더 확인해 주세요.',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F5F4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('보내기'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                      '\uCCA8\uBD80 \uBCF4\uB0B4\uAE30',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('\uC0AC\uC9C4'),
                    subtitle: const Text(
                      '\uAE30\uAE30\uC5D0\uC11C \uC774\uBBF8\uC9C0\uB97C \uC120\uD0DD\uD569\uB2C8\uB2E4.',
                    ),
                    onTap: () => _pickAndCloseAttachment(
                      context,
                      AttachmentPickKind.image,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: const Text('\uD30C\uC77C'),
                    subtitle: const Text(
                      '\uBB38\uC11C \uB610\uB294 \uD30C\uC77C\uC744 \uC120\uD0DD\uD569\uB2C8\uB2E4.',
                    ),
                    onTap: () => _pickAndCloseAttachment(
                      context,
                      AttachmentPickKind.file,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('\uC704\uCE58'),
                    subtitle: const Text(
                      '\uD604\uC7AC \uC704\uCE58\uB97C \uACF5\uC720\uD569\uB2C8\uB2E4.',
                    ),
                    onTap: () => _pickAndCloseLocation(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('\uC77C\uC815 \uC81C\uC548'),
                    subtitle: const Text(
                      '\uD6C4\uBCF4 \uC2DC\uAC04\uC744 \uD22C\uD45C \uCE74\uB4DC\uB85C \uBCF4\uB0C5\uB2C8\uB2E4.',
                    ),
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
    await _run(
      () async {
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
      },
      busyLabel:
          '\uCCA8\uBD80 \uD30C\uC77C\uC744 \uBCF4\uB0B4\uB294 \uC911\uC785\uB2C8\uB2E4.',
    );
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
    await _run(
      () async {
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
      },
      busyLabel:
          '\uC77C\uC815 \uC81C\uC548\uC744 \uBCF4\uB0B4\uB294 \uC911\uC785\uB2C8\uB2E4.',
    );
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
              ? '\uC774\uBBF8\uC9C0\uB294 10MB \uC774\uD558 \uD30C\uC77C\uB9CC \uBCF4\uB0BC \uC218 \uC788\uC2B5\uB2C8\uB2E4.'
              : '\uD30C\uC77C\uC740 50MB \uC774\uD558 \uD30C\uC77C\uB9CC \uBCF4\uB0BC \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
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
      _showError(
        '\uC608\uC57D\uD560 \uBA54\uC2DC\uC9C0 \uB0B4\uC6A9\uC744 \uBA3C\uC800 \uC785\uB825\uD574 \uC8FC\uC138\uC694.',
      );
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
                      ? '\uB0A0\uC9DC\uB294 YYYY-MM-DD, \uC2DC\uAC04\uC740 HH:MM \uD615\uC2DD\uC73C\uB85C \uC785\uB825\uD574 \uC8FC\uC138\uC694.'
                      : null
                : isFuture
                ? null
                : '\uD604\uC7AC\uBCF4\uB2E4 \uBBF8\uB798\uC758 \uB0A0\uC9DC\uC640 \uC2DC\uAC04\uC744 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.';
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
                      '\uC608\uC57D \uC804\uC1A1',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '\uBCF4\uB0BC \uB0A0\uC9DC\uC640 \uC2DC\uAC04\uC744 \uC9C1\uC811 \uC785\uB825\uD574 \uC8FC\uC138\uC694.',
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
                        labelText: '\uB0A0\uC9DC',
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
                        labelText: '\uC2DC\uAC04',
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
                        '${_scheduleLabel(scheduledAt)}\uC5D0 \uC804\uC1A1\uD569\uB2C8\uB2E4.',
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
                      label: const Text('\uC608\uC57D\uD558\uAE30'),
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
    await _run(
      () async {
        await BackendScope.of(context).scheduleTextMessage(
          roomId: widget.roomId,
          text: text,
          scheduledAt: selected!,
          replyToMessageId: widget.replyTo?.id,
        );
        _textController.clear();
        widget.onSent();
      },
      busyLabel:
          '\uC608\uC57D \uBA54\uC2DC\uC9C0\uB97C \uC800\uC7A5\uD558\uB294 \uC911\uC785\uB2C8\uB2E4.',
    );
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    await _startStreamingRecording();
  }

  Future<void> _startStreamingRecording() async {
    await _run(() async {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        throw StateError('마이크 권한이 필요합니다.');
      }
      _deviceSttActive = false;
      _pcmDeviceSttActive = false;
      _deepgramSttActive = false;
      _liveTranscript = '';
      _voiceSttSession = null;
      _deepgramLiveRecoveryAttempts = 0;
      _deepgramLiveRecoveryInFlight = false;
      _cancelDeepgramLiveRecovery();
      final pcmSupported =
          !kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
      if (!_kPreferDeviceSttPrimary && pcmSupported) {
        await _warmDeepgramBeforeRecording();
      }
      debugPrint(
        'voice_recording_start '
        'deepgramEnabled=${DeepgramStreamingStt.enabled} '
        'realtimeSttKo=$_kUseRealtimeSttForKorean '
        'realtimeProvider=${_kRealtimeSttProvider.isEmpty ? 'deepgram' : _kRealtimeSttProvider} '
        'deviceSttPrimary=$_kPreferDeviceSttPrimary '
        'pcmDeviceEnabled=${PcmDeviceStreamingStt.enabled} '
        'pcmSupported=$pcmSupported',
      );
      if (!kIsWeb &&
          _kUseRealtimeSttForKorean &&
          DeepgramStreamingStt.enabled &&
          !_kPreferDeviceSttPrimary &&
          !_deepgramStreamingTemporarilyDisabled &&
          pcmSupported) {
        final primaryProvider = _primaryRealtimeSttProvider;
        final deepgramStt = _takeOrCreateDeepgramStt();
        var activeRealtimeProviderLabel = deepgramStt.providerLabel;
        final bufferedChunks = <Uint8List>[];
        var bufferedBytes = 0;
        var deepgramReady = false;
        var pcmDeviceReady = false;
        const maxBufferedBytes = 16000 * 2 * 12;
        void enqueueDeepgramChunk(Uint8List chunk) {
          final activeDeepgramStt = _deepgramStreamingStt ?? deepgramStt;
          if (deepgramReady && activeDeepgramStt.isReady) {
            _voiceSttSession?.markAudioSent(DateTime.now());
            activeDeepgramStt.sendAudio(chunk);
            return;
          }
          bufferedChunks.add(chunk);
          bufferedBytes += chunk.length;
          while (bufferedBytes > maxBufferedBytes &&
              bufferedChunks.isNotEmpty) {
            bufferedBytes -= bufferedChunks.removeAt(0).length;
          }
        }

        try {
          final path = await _recordingPath(AudioEncoder.wav);
          final stream = await _recorder.startStream(_pcmStreamRecordConfig());
          final recordingStartedAt = DateTime.now();
          _voiceSttSession = VoiceSttSession(startedAt: recordingStartedAt);
          _recordStreamBytes = BytesBuilder(copy: false);
          _recordStreamByteCount = 0;
          _speculativeVoiceSttFuture = null;
          _speculativeVoiceSttStartedAt = null;
          _speculativeVoiceSttFollowUpFuture = null;
          _speculativeVoiceSttFollowUpStartedAt = null;
          _streamRecordingPath = path;
          _deepgramStreamingStt = deepgramStt;
          _deepgramSttActive = true;
          if (_kAllowDeviceSttDuringVoiceRecording) {
            unawaited(
              _startDeviceStreamingStt(
                providerLabel: 'device_streaming_parallel',
              ),
            );
          }
          if (PcmDeviceStreamingStt.enabled) {
            pcmDeviceReady = await _pcmDeviceSpeechRecognizer
                .start(
                  startedAt: recordingStartedAt,
                  onTranscript: _handlePcmDeviceTranscript,
                  onSnapshot: _handlePcmDeviceSnapshot,
                )
                .timeout(
                  const Duration(milliseconds: 450),
                  onTimeout: () {
                    debugPrint(
                      'voice_stt_provider_unavailable provider=pcm_device timeout=true',
                    );
                    return false;
                  },
                );
            _pcmDeviceSttActive = pcmDeviceReady;
            if (pcmDeviceReady) {
              debugPrint('voice_stt_provider_started provider=pcm_device');
            }
          }
          _recordStreamSub = stream.listen(
            (chunk) {
              final chunkReceivedAt = DateTime.now();
              final level = measurePcm16AudioLevel(chunk);
              final liveSttChunk = _normalizeLiveSttChunk(chunk, level);
              _voiceSttSession?.observeAudioLevel(level);
              final hadSpeechBefore = _voiceSttSession?.firstSpeechAt != null;
              if (!hadSpeechBefore && level.looksLikeSpeech) {
                _voiceSttSession?.markSpeechDetected(chunkReceivedAt);
                deepgramStt.markSpeechDetected(chunkReceivedAt);
                _scheduleDeepgramLiveRecovery(
                  reason: 'no_partial_after_speech',
                );
                debugPrint(
                  'voice_speech_detected provider=$activeRealtimeProviderLabel '
                  'recordStartToFirstSpeechMs=${chunkReceivedAt.difference(recordingStartedAt).inMilliseconds} '
                  'rms=${level.rms.toStringAsFixed(1)} '
                  'peak=${level.peak}',
                );
              }
              _recordStreamBytes?.add(chunk);
              _recordStreamByteCount += chunk.length;
              _maybeStartSpeculativeVoiceStt(
                providerLabel: activeRealtimeProviderLabel,
                reason: 'deepgram_stream',
              );
              if (pcmDeviceReady) {
                _voiceSttSession?.markAudioSent(DateTime.now());
                _pcmDeviceSpeechRecognizer.sendAudio(liveSttChunk);
              }
              enqueueDeepgramChunk(liveSttChunk);
            },
            onError: (Object error) {
              debugPrint('Voice stream recording failed: $error');
            },
          );
          debugPrint(
            'voice_stt_provider_starting provider=${activeRealtimeProviderLabel}_buffered',
          );
          _stopwatch
            ..reset()
            ..start();
          _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) {
              setState(() {});
            }
          });
          setState(() => _recording = true);
          unawaited(
            (() async {
              final connectStartedAt = DateTime.now();
              final wasPreconnected = deepgramStt.isReady;
              final started = wasPreconnected
                  ? deepgramStt.attachSession(
                      startedAt: recordingStartedAt,
                      onTranscript: _handleDeepgramTranscript,
                      onSnapshot: _handleDeepgramSnapshot,
                    )
                  : await deepgramStt
                        .start(
                          startedAt: recordingStartedAt,
                          onTranscript: _handleDeepgramTranscript,
                          onSnapshot: _handleDeepgramSnapshot,
                        )
                        .timeout(
                          const Duration(seconds: 9),
                          onTimeout: () => false,
                        );
              if (!mounted ||
                  _deepgramStreamingStt != deepgramStt ||
                  _streamRecordingPath != path) {
                if (started) {
                  await deepgramStt.cancel();
                }
                return;
              }
              if (!started) {
                final fallbackProvider = _fallbackRealtimeSttProvider;
                if (fallbackProvider != null &&
                    fallbackProvider != primaryProvider) {
                  await deepgramStt.cancel();
                  final fallbackStartedAt = DateTime.now();
                  final fallbackStt = _newDeepgramStreamingStt(
                    provider: fallbackProvider,
                  );
                  final fallbackStarted = await fallbackStt
                      .start(
                        startedAt: recordingStartedAt,
                        onTranscript: _handleDeepgramTranscript,
                        onSnapshot: _handleDeepgramSnapshot,
                      )
                      .timeout(
                        const Duration(seconds: 4),
                        onTimeout: () => false,
                      );
                  if (!mounted || _streamRecordingPath != path || !_recording) {
                    await fallbackStt.cancel();
                    return;
                  }
                  if (fallbackStarted) {
                    _deepgramStreamingStt = fallbackStt;
                    activeRealtimeProviderLabel = fallbackStt.providerLabel;
                    final firstSpeechAt = _voiceSttSession?.firstSpeechAt;
                    if (firstSpeechAt != null) {
                      fallbackStt.markSpeechDetected(firstSpeechAt);
                    }
                    deepgramReady = true;
                    for (final bufferedChunk in bufferedChunks) {
                      _voiceSttSession?.markAudioSent(DateTime.now());
                      fallbackStt.sendAudio(bufferedChunk);
                    }
                    debugPrint(
                      'voice_stt_provider_fallback_started '
                      'primary=${_realtimeProviderLogLabel(primaryProvider)} '
                      'provider=${fallbackStt.providerLabel} '
                      'connectMs=${DateTime.now().difference(fallbackStartedAt).inMilliseconds} '
                      'bufferedBytes=$bufferedBytes '
                      'recordingMs=${_stopwatch.elapsedMilliseconds}',
                    );
                    bufferedChunks.clear();
                    bufferedBytes = 0;
                    return;
                  }
                  await fallbackStt.cancel();
                }
                debugPrint(
                  'voice_stt_provider_unavailable provider=$activeRealtimeProviderLabel',
                );
                _disableDeepgramStreamingTemporarily(
                  reason: 'recording_start_unavailable',
                );
                return;
              }
              final firstSpeechAt = _voiceSttSession?.firstSpeechAt;
              if (firstSpeechAt != null) {
                deepgramStt.markSpeechDetected(firstSpeechAt);
              }
              deepgramReady = true;
              for (final bufferedChunk in bufferedChunks) {
                _voiceSttSession?.markAudioSent(DateTime.now());
                deepgramStt.sendAudio(bufferedChunk);
              }
              debugPrint(
                'voice_stt_provider_started provider=$activeRealtimeProviderLabel '
                'preconnected=$wasPreconnected '
                'connectMs=${DateTime.now().difference(connectStartedAt).inMilliseconds} '
                'bufferedBytes=$bufferedBytes '
                'recordingMs=${_stopwatch.elapsedMilliseconds}',
              );
              bufferedChunks.clear();
              bufferedBytes = 0;
            })(),
          );
          return;
        } catch (error) {
          debugPrint('Deepgram streaming STT unavailable: $error');
          _disableDeepgramStreamingTemporarily(
            reason: 'recording_start_failed',
          );
          await _recordStreamSub?.cancel();
          _recordStreamSub = null;
          _recordStreamBytes = null;
          _recordStreamByteCount = 0;
          _streamRecordingPath = null;
          _deepgramStreamingStt = null;
          _deepgramSttActive = false;
          _pcmDeviceSttActive = false;
          await _pcmDeviceSpeechRecognizer.cancel();
          await _recorder.cancel();
        } finally {
          if (!_deepgramSttActive) {
            await deepgramStt.cancel();
          }
        }
      }
      if (!kIsWeb &&
          !_kPreferDeviceSttPrimary &&
          PcmDeviceStreamingStt.enabled &&
          pcmSupported) {
        try {
          final path = await _recordingPath(AudioEncoder.wav);
          final stream = await _recorder.startStream(_pcmStreamRecordConfig());
          final recordingStartedAt = DateTime.now();
          _voiceSttSession = VoiceSttSession(startedAt: recordingStartedAt);
          _recordStreamBytes = BytesBuilder(copy: false);
          _recordStreamByteCount = 0;
          _speculativeVoiceSttFuture = null;
          _speculativeVoiceSttStartedAt = null;
          _speculativeVoiceSttFollowUpFuture = null;
          _speculativeVoiceSttFollowUpStartedAt = null;
          _streamRecordingPath = path;
          final pcmDeviceReady = await _pcmDeviceSpeechRecognizer
              .start(
                startedAt: recordingStartedAt,
                onTranscript: _handlePcmDeviceTranscript,
                onSnapshot: _handlePcmDeviceSnapshot,
              )
              .timeout(
                const Duration(milliseconds: 450),
                onTimeout: () {
                  debugPrint(
                    'voice_stt_provider_unavailable provider=pcm_device_primary timeout=true',
                  );
                  return false;
                },
              );
          if (!pcmDeviceReady) {
            await stream.drain<void>().timeout(
              const Duration(milliseconds: 100),
              onTimeout: () {},
            );
            await _recorder.cancel();
            _recordStreamBytes = null;
            _recordStreamByteCount = 0;
            _streamRecordingPath = null;
            throw StateError('PCM device STT is unavailable.');
          }
          _pcmDeviceSttActive = true;
          if (_kAllowDeviceSttDuringVoiceRecording) {
            unawaited(
              _startDeviceStreamingStt(
                providerLabel: 'device_streaming_parallel',
              ),
            );
          }
          _recordStreamSub = stream.listen(
            (chunk) {
              final chunkReceivedAt = DateTime.now();
              final level = measurePcm16AudioLevel(chunk);
              final liveSttChunk = _normalizeLiveSttChunk(chunk, level);
              _voiceSttSession?.observeAudioLevel(level);
              final hadSpeechBefore = _voiceSttSession?.firstSpeechAt != null;
              if (!hadSpeechBefore && level.looksLikeSpeech) {
                _voiceSttSession?.markSpeechDetected(chunkReceivedAt);
                debugPrint(
                  'voice_speech_detected provider=pcm_device_primary '
                  'recordStartToFirstSpeechMs=${chunkReceivedAt.difference(recordingStartedAt).inMilliseconds} '
                  'rms=${level.rms.toStringAsFixed(1)} '
                  'peak=${level.peak}',
                );
              }
              _recordStreamBytes?.add(chunk);
              _recordStreamByteCount += chunk.length;
              _maybeStartSpeculativeVoiceStt(
                providerLabel: 'pcm_device_primary',
                reason: 'pcm_stream',
              );
              _voiceSttSession?.markAudioSent(DateTime.now());
              _pcmDeviceSpeechRecognizer.sendAudio(liveSttChunk);
            },
            onError: (Object error) {
              debugPrint('Voice PCM recording failed: $error');
            },
          );
          debugPrint('voice_stt_provider_started provider=pcm_device_primary');
          _stopwatch
            ..reset()
            ..start();
          _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) {
              setState(() {});
            }
          });
          setState(() => _recording = true);
          return;
        } catch (error) {
          debugPrint('PCM device STT recording unavailable: $error');
          await _recordStreamSub?.cancel();
          _recordStreamSub = null;
          _recordStreamBytes = null;
          _recordStreamByteCount = 0;
          _streamRecordingPath = null;
          _pcmDeviceSttActive = false;
          await _pcmDeviceSpeechRecognizer.cancel();
          await _recorder.cancel();
        }
      }
      if (_kPreferDeviceSttPrimary || _kAllowDeviceSttDuringVoiceRecording) {
        await _startDeviceStreamingStt(
          providerLabel: _kPreferDeviceSttPrimary
              ? 'device_streaming_primary'
              : 'device_streaming',
        );
      }
      final encoder = await _preferredEncoder();
      if (!_deviceSttActive && !_deepgramSttActive) {
        debugPrint(
          'voice_stt_provider_started provider=server_fallback encoder=$encoder',
        );
      }
      final path = await _recordingPath(encoder);
      try {
        await _recorder.start(_voiceRecordConfig(encoder), path: path);
      } catch (_) {
        await _speechRecognizer.cancel();
        rethrow;
      }
      _voiceSttSession = VoiceSttSession(startedAt: DateTime.now());
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

  Future<bool> _startDeviceStreamingStt({required String providerLabel}) async {
    if (!DeviceStreamingStt.enabled || _deviceSttActive) {
      return _deviceSttActive;
    }
    try {
      await _speechRecognizer.start(
        onTranscript: (transcript) {
          if (!mounted) {
            return;
          }
          final next = transcript.trim();
          setState(() {
            _liveTranscript = next;
            _voiceSttSession?.lastStableTranscript = next;
            _voiceSttSession?.firstPartialAt ??= DateTime.now();
            _voiceSttSession?.lastUpdateAt = DateTime.now();
          });
        },
        onSnapshot: (snapshot) {
          if (mounted) {
            setState(() {
              _voiceSttSession?.apply(snapshot);
              _liveTranscript = snapshot.transcript;
            });
          }
        },
      );
      _deviceSttActive = true;
      debugPrint('voice_stt_provider_started provider=$providerLabel');
      return true;
    } catch (error) {
      _deviceSttActive = false;
      debugPrint(
        'voice_stt_provider_unavailable provider=$providerLabel error=$error',
      );
      await _speechRecognizer.cancel();
      return false;
    }
  }

  // ignore: unused_element
  Future<void> _startRecordingLegacy() async {
    await _run(() async {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        throw StateError(
          '\uB9C8\uC774\uD06C \uAD8C\uD55C\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
        );
      }
      _freeSttActive = false;
      _liveTranscript = '';
      if (BrowserSpeechRecognizer.enabled) {
        try {
          await _speechRecognizer.start(
            onTranscript: (transcript) {
              if (mounted) {
                setState(() => _liveTranscript = transcript);
              }
            },
          );
          _freeSttActive = true;
        } catch (_) {
          _freeSttActive = false;
          await _speechRecognizer.cancel();
        }
      }
      final encoder = await _preferredEncoder();
      final path = await _recordingPath(encoder);
      try {
        await _recorder.start(_voiceRecordConfig(encoder), path: path);
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
        : const [AudioEncoder.wav, AudioEncoder.aacLc];
    for (final candidate in candidates) {
      if (await _recorder.isEncoderSupported(candidate)) {
        return candidate;
      }
    }
    return AudioEncoder.wav;
  }

  RecordConfig _voiceRecordConfig(AudioEncoder encoder) {
    return RecordConfig(
      encoder: encoder,
      bitRate: 64000,
      sampleRate: 16000,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(audioSource: _androidVoiceAudioSource),
    );
  }

  RecordConfig _pcmStreamRecordConfig() {
    return RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      bitRate: 256000,
      sampleRate: 16000,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(audioSource: _androidVoiceAudioSource),
    );
  }

  Future<String> _recordingPath(AudioEncoder encoder) async {
    if (kIsWeb) {
      return '';
    }
    final tempDir = await getTemporaryDirectory();
    final extension = encoder == AudioEncoder.wav ? 'wav' : 'm4a';
    return '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  MessageReply? _replyPreviewFor(ChatMessage? message) {
    if (message == null) {
      return null;
    }
    return MessageReply(
      messageId: message.id,
      senderId: message.senderId,
      preview: _replyPreviewText(message),
    );
  }

  String _replyPreviewText(ChatMessage message) {
    if (message.kind != MessageKind.voice) {
      return message.displayText;
    }
    final voiceText = message.voiceTranscriptText.trim();
    if (voiceText.isNotEmpty) {
      return voiceText;
    }
    if (message.sttStatus == SttStatus.processing ||
        message.sttStatus == SttStatus.pending ||
        message.deliveryStatus == MessageDeliveryStatus.sending) {
      return '\uC74C\uC131 \uBCC0\uD658 \uC911...';
    }
    return '\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328';
  }

  void _emitOptimisticVoiceMessage({
    required String messageId,
    required String audioFilePath,
    required int durationMs,
    required String? transcript,
    required DateTime createdAt,
  }) {
    final stableTranscript = transcript?.trim() ?? '';
    widget.onOptimisticVoiceMessage(
      ChatMessage(
        id: messageId,
        senderId: widget.currentUserId,
        kind: MessageKind.voice,
        text: stableTranscript,
        transcript: stableTranscript,
        audioPath: audioFilePath,
        durationMs: durationMs,
        sttStatus: stableTranscript.isNotEmpty
            ? SttStatus.completed
            : SttStatus.processing,
        sendMode: SendMode.instant,
        createdAt: createdAt,
        replyTo: _replyPreviewFor(widget.replyTo),
        deliveryStatus: MessageDeliveryStatus.sending,
      ),
    );
  }

  bool _shouldForceServerSttCorrection({
    required String transcript,
    required int durationMs,
    required VoiceSttSnapshot snapshot,
  }) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return true;
    }
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    final lastTranscriptMs = snapshot.recordStartToLastTranscriptMs;
    final transcriptStoppedEarly =
        lastTranscriptMs != null && durationMs - lastTranscriptMs > 1200;
    if (durationMs >= 2500 && compact.length <= 4) {
      return true;
    }
    if (durationMs >= 3000 && transcriptStoppedEarly && compact.length <= 30) {
      return true;
    }
    if (durationMs >= 6000 && compact.length <= 24) {
      return true;
    }
    if (durationMs >= 4000 && compact.length <= 8 && transcriptStoppedEarly) {
      return true;
    }
    return false;
  }

  Uint8List _normalizeLiveSttChunk(Uint8List chunk, Pcm16AudioLevel level) {
    final speechAlreadyDetected = _voiceSttSession?.firstSpeechAt != null;
    final weakSpeechCandidate = level.rms >= 30 && level.peak >= 220;
    if (!level.looksLikeSpeech &&
        !speechAlreadyDetected &&
        !weakSpeechCandidate) {
      return chunk;
    }
    return normalizePcm16ForSpeech(
      chunk,
      targetRms: 3200,
      minRms: 30,
      maxGain: 48,
    );
  }

  Uint8List _normalizeFinalVoicePcm({
    required String messageId,
    required Uint8List pcmBytes,
  }) {
    final before = measurePcm16AudioLevel(pcmBytes);
    final normalized = normalizePcm16ForSpeech(
      pcmBytes,
      targetRms: 2800,
      minRms: 45,
      maxGain: 35,
    );
    final after = identical(normalized, pcmBytes)
        ? before
        : measurePcm16AudioLevel(normalized);
    debugPrint(
      'voice_record_stream_normalized messageId=$messageId '
      'rawRms=${before.rms.toStringAsFixed(1)} '
      'rawPeak=${before.peak} '
      'normalizedRms=${after.rms.toStringAsFixed(1)} '
      'normalizedPeak=${after.peak} '
      'changed=${!identical(normalized, pcmBytes)}',
    );
    return normalized;
  }

  void _maybeStartSpeculativeVoiceStt({
    required String providerLabel,
    required String reason,
  }) {
    if (!_kSpeculativeVoiceSttEnabled || !mounted || !_recording) {
      return;
    }
    final session = _voiceSttSession;
    final firstSpeechAt = session?.firstSpeechAt;
    final streamBytes = _recordStreamBytes;
    if (session == null ||
        firstSpeechAt == null ||
        streamBytes == null ||
        session.hasTranscript) {
      return;
    }
    final now = DateTime.now();
    final recordingMs = now.difference(session.startedAt).inMilliseconds;
    final speechMs = now.difference(firstSpeechAt).inMilliseconds;
    final isInitialAttempt = _speculativeVoiceSttFuture == null;
    final isFollowUpAttempt =
        !isInitialAttempt && _speculativeVoiceSttFollowUpFuture == null;
    if (!isInitialAttempt && !isFollowUpAttempt) {
      return;
    }
    final minRecordingMs = isInitialAttempt
        ? _kSpeculativeVoiceSttMinRecordingMs
        : _kSpeculativeVoiceSttFollowUpMinRecordingMs;
    final minSpeechMs = isInitialAttempt
        ? _kSpeculativeVoiceSttMinSpeechMs
        : _kSpeculativeVoiceSttFollowUpMinSpeechMs;
    final minBytes = isInitialAttempt
        ? _kSpeculativeVoiceSttMinBytes
        : _kSpeculativeVoiceSttFollowUpMinBytes;
    if (recordingMs < minRecordingMs ||
        speechMs < minSpeechMs ||
        _recordStreamByteCount < minBytes) {
      return;
    }
    final pcmSnapshot = streamBytes.toBytes();
    if (pcmSnapshot.length < minBytes) {
      return;
    }
    final normalizedPcm = normalizePcm16ForSpeech(
      pcmSnapshot,
      targetRms: 2800,
      minRms: 45,
      maxGain: 35,
    );
    final wavBytes = buildPcm16WavBytes(pcmBytes: normalizedPcm);
    final startedAt = DateTime.now();
    final attemptLabel = isInitialAttempt ? 'initial' : 'follow_up';
    if (isInitialAttempt) {
      _speculativeVoiceSttStartedAt = startedAt;
    } else {
      _speculativeVoiceSttFollowUpStartedAt = startedAt;
    }
    debugPrint(
      'voice_speculative_stt_started '
      'provider=$providerLabel '
      'reason=$reason '
      'attempt=$attemptLabel '
      'recordingMs=$recordingMs '
      'speechMs=$speechMs '
      'pcmBytes=${pcmSnapshot.length} '
      'wavBytes=${wavBytes.length}',
    );
    final future = BackendScope.of(context)
        .transcribeVoiceAudioDraft(
          roomId: widget.roomId,
          audioBytes: wavBytes,
          contentType: 'audio/wav',
          durationMs: recordingMs,
          language: 'ko-KR',
        )
        .then((result) {
          final transcript = _sanitizeVoiceTranscriptCandidate(
            result?.transcript ?? '',
          );
          debugPrint(
            'voice_speculative_stt_result '
            'provider=$providerLabel '
            'reason=$reason '
            'attempt=$attemptLabel '
            'clientMs=${DateTime.now().difference(startedAt).inMilliseconds} '
            'serverTotalMs=${result?.totalMs ?? -1} '
            'serverSttMs=${result?.sttMs ?? -1} '
            'transcriptLength=${transcript.length}',
          );
          if (transcript.isNotEmpty && mounted && _recording) {
            setState(() {
              _liveTranscript = transcript;
              _voiceSttSession?.lastStableTranscript = transcript;
              _voiceSttSession?.firstPartialAt ??= DateTime.now();
              _voiceSttSession?.lastUpdateAt = DateTime.now();
            });
          }
          return result;
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'voice_speculative_stt_failed '
            'provider=$providerLabel reason=$reason '
            'attempt=$attemptLabel error=$error',
          );
          debugPrintStack(stackTrace: stackTrace);
          return null;
        });
    if (isInitialAttempt) {
      _speculativeVoiceSttFuture = future;
    } else {
      _speculativeVoiceSttFollowUpFuture = future;
    }
  }

  String _clientVoiceMessageId() {
    return 'client_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _updateVoiceTranscriptWithRetry({
    required MessengerBackend backend,
    required String roomId,
    required String messageId,
    required String transcript,
    Future<void>? waitForPendingCreate,
  }) async {
    if (waitForPendingCreate != null) {
      try {
        await waitForPendingCreate.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint(
              'voice_send_late_transcript_wait_pending_timeout '
              'messageId=$messageId',
            );
          },
        );
      } catch (error) {
        debugPrint(
          'voice_send_late_transcript_pending_not_ready '
          'messageId=$messageId error=$error',
        );
      }
    }
    for (var attempt = 0; attempt < 10; attempt += 1) {
      try {
        await backend.updateClientVoiceTranscript(
          roomId: roomId,
          messageId: messageId,
          transcript: transcript,
        );
        return;
      } catch (error) {
        if (attempt == 9) {
          debugPrint('Failed to update late voice transcript: $error');
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  Future<void> _stopRecording() async {
    await _stopStreamingRecording();
  }

  Future<void> _stopStreamingRecording() async {
    final wasDeviceSttActive = _deviceSttActive;
    final wasPcmDeviceSttActive = _pcmDeviceSttActive;
    final wasDeepgramSttActive = _deepgramSttActive;
    final wasStreamRecordingActive =
        _recordStreamBytes != null && _streamRecordingPath != null;
    final deepgramStt = _deepgramStreamingStt;
    final speculativeVoiceSttFuture = _speculativeVoiceSttFuture;
    final speculativeVoiceSttStartedAt = _speculativeVoiceSttStartedAt;
    final speculativeVoiceSttFollowUpFuture =
        _speculativeVoiceSttFollowUpFuture;
    final speculativeVoiceSttFollowUpStartedAt =
        _speculativeVoiceSttFollowUpStartedAt;
    final sendTappedAt = DateTime.now();
    final sttSnapshotAtSend =
        _voiceSttSession?.snapshot() ?? _speechRecognizer.snapshot();
    _timer?.cancel();
    _cancelDeepgramLiveRecovery();
    final durationMs = _stopwatch.elapsedMilliseconds;
    final messageId = _clientVoiceMessageId();
    var latestTranscript = _sanitizeVoiceTranscriptCandidate(
      sttSnapshotAtSend.transcript,
    );
    DateTime? transcriptAvailableAt = latestTranscript.isNotEmpty
        ? sendTappedAt
        : null;
    final canCreateOptimistic = durationMs >= 500;
    final backend = BackendScope.of(context);
    var backendStarted = false;
    Future<void>? pendingCreateFuture;
    final fastFinalCompleter = Completer<void>();
    var optimisticBubbleEmitted = false;
    var sendTapToPendingBubbleMs = -1;
    void markOptimisticBubbleVisible() {
      if (optimisticBubbleEmitted) {
        return;
      }
      optimisticBubbleEmitted = true;
      widget.onSent();
      sendTapToPendingBubbleMs = DateTime.now()
          .difference(sendTappedAt)
          .inMilliseconds;
      debugPrint(
        'voice_send_optimistic_visible messageId=$messageId '
        'sendTapToPendingBubbleMs=$sendTapToPendingBubbleMs '
        'hasTranscript=${latestTranscript.isNotEmpty}',
      );
    }

    void acceptLateTranscript(String transcript, {String audioFilePath = ''}) {
      final next = _sanitizeVoiceTranscriptCandidate(transcript);
      if (!_isBetterVoiceTranscriptCandidate(next, latestTranscript)) {
        debugPrint(
          'voice_send_late_transcript_ignored messageId=$messageId '
          'incomingLength=${next.length} '
          'existingLength=${latestTranscript.length}',
        );
        return;
      }
      final hadTranscriptBeforeLateUpdate = latestTranscript.isNotEmpty;
      latestTranscript = next;
      transcriptAvailableAt ??= DateTime.now();
      debugPrint(
        'voice_send_late_transcript messageId=$messageId '
        'sendTapToLateTranscriptMs=${DateTime.now().difference(sendTappedAt).inMilliseconds} '
        'hadTranscriptBeforeLateUpdate=$hadTranscriptBeforeLateUpdate '
        'length=${next.length}',
      );
      if (!fastFinalCompleter.isCompleted) {
        fastFinalCompleter.complete();
      }
      if (canCreateOptimistic) {
        _emitOptimisticVoiceMessage(
          messageId: messageId,
          audioFilePath: audioFilePath,
          durationMs: durationMs,
          transcript: next,
          createdAt: sendTappedAt,
        );
        markOptimisticBubbleVisible();
      }
      if (backendStarted) {
        unawaited(
          _updateVoiceTranscriptWithRetry(
            backend: backend,
            roomId: widget.roomId,
            messageId: messageId,
            transcript: next,
            waitForPendingCreate: pendingCreateFuture,
          ),
        );
      }
    }

    void observeSpeculativeVoiceStt(
      Future<VoiceInlineSttResult?>? future, {
      required String attempt,
      required DateTime? startedAt,
    }) {
      if (future == null) {
        return;
      }
      unawaited(
        future
            .then((result) {
              final transcript = _sanitizeVoiceTranscriptCandidate(
                result?.transcript ?? '',
              );
              debugPrint(
                'voice_send_speculative_stt_observed '
                'messageId=$messageId '
                'attempt=$attempt '
                'sendTapMs=${DateTime.now().difference(sendTappedAt).inMilliseconds} '
                'speculativeAgeMs=${startedAt == null ? -1 : DateTime.now().difference(startedAt).inMilliseconds} '
                'transcriptLength=${transcript.length}',
              );
              if (transcript.isNotEmpty) {
                acceptLateTranscript(transcript);
              }
            })
            .catchError((Object error) {
              debugPrint(
                'voice_send_speculative_stt_observe_failed '
                'messageId=$messageId attempt=$attempt error=$error',
              );
            }),
      );
    }

    observeSpeculativeVoiceStt(
      speculativeVoiceSttFuture,
      attempt: 'initial',
      startedAt: speculativeVoiceSttStartedAt,
    );
    observeSpeculativeVoiceStt(
      speculativeVoiceSttFollowUpFuture,
      attempt: 'follow_up',
      startedAt: speculativeVoiceSttFollowUpStartedAt,
    );

    void emitOptimisticBubble({
      String audioFilePath = '',
      int? durationOverrideMs,
    }) {
      if (!canCreateOptimistic) {
        return;
      }
      _emitOptimisticVoiceMessage(
        messageId: messageId,
        audioFilePath: audioFilePath,
        durationMs: durationOverrideMs ?? durationMs,
        transcript: latestTranscript.isNotEmpty ? latestTranscript : null,
        createdAt: sendTappedAt,
      );
      markOptimisticBubbleVisible();
    }

    void startPendingCreate() {
      if (!canCreateOptimistic || pendingCreateFuture != null) {
        return;
      }
      final transcriptAtCreate = latestTranscript.isNotEmpty
          ? latestTranscript
          : null;
      final pendingCreateStartedAt = DateTime.now();
      backendStarted = true;
      pendingCreateFuture = backend
          .createPendingVoiceMessage(
            roomId: widget.roomId,
            messageId: messageId,
            durationMs: durationMs,
            sendMode: SendMode.instant,
            transcriptOverride: transcriptAtCreate,
            replyToMessageId: widget.replyTo?.id,
          )
          .then((_) {
            debugPrint(
              'voice_send_server_pending_ready messageId=$messageId '
              'createMs=${DateTime.now().difference(pendingCreateStartedAt).inMilliseconds} '
              'transcriptAtCreate=${transcriptAtCreate?.isNotEmpty == true}',
            );
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('Failed to create early pending voice message: $error');
            debugPrintStack(stackTrace: stackTrace);
          });
    }

    Future<void> persistLatestTranscript({required String reason}) async {
      final transcript = _sanitizeVoiceTranscriptCandidate(latestTranscript);
      if (transcript.isEmpty || !canCreateOptimistic) {
        return;
      }
      await _updateVoiceTranscriptWithRetry(
        backend: backend,
        roomId: widget.roomId,
        messageId: messageId,
        transcript: transcript,
        waitForPendingCreate: pendingCreateFuture,
      );
      debugPrint(
        'voice_send_transcript_persisted messageId=$messageId '
        'reason=$reason length=${transcript.length}',
      );
    }

    Future<void> runInlineSttFromWavBytes({
      required Uint8List wavBytes,
      required String audioFilePath,
      required String reason,
    }) async {
      if (!canCreateOptimistic || latestTranscript.isNotEmpty) {
        return;
      }
      final waitForPending = pendingCreateFuture;
      if (waitForPending != null) {
        try {
          await waitForPending.timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint(
                'voice_send_inline_bytes_wait_pending_timeout '
                'messageId=$messageId reason=$reason',
              );
            },
          );
        } catch (error) {
          debugPrint(
            'voice_send_inline_bytes_pending_not_ready '
            'messageId=$messageId reason=$reason error=$error',
          );
        }
      }
      final startedAt = DateTime.now();
      try {
        final result = await backend.transcribeClientVoiceMessageInline(
          roomId: widget.roomId,
          messageId: messageId,
          audioBytes: wavBytes,
          contentType: 'audio/wav',
          durationMs: durationMs,
          language: 'ko-KR',
        );
        final transcript = _sanitizeVoiceTranscriptCandidate(
          result?.transcript ?? '',
        );
        debugPrint(
          'voice_send_inline_bytes_completed messageId=$messageId '
          'reason=$reason '
          'clientMs=${DateTime.now().difference(startedAt).inMilliseconds} '
          'serverTotalMs=${result?.totalMs ?? -1} '
          'serverSttMs=${result?.sttMs ?? -1} '
          'transcriptLength=${transcript.length}',
        );
        if (transcript.isNotEmpty) {
          acceptLateTranscript(transcript, audioFilePath: audioFilePath);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'voice_send_inline_bytes_failed '
          'messageId=$messageId reason=$reason error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    Future<void> runDraftSttFromWavBytes({
      required Uint8List wavBytes,
      required String audioFilePath,
      required String reason,
      required int snapshotDurationMs,
    }) async {
      if (!canCreateOptimistic || latestTranscript.isNotEmpty) {
        return;
      }
      final startedAt = DateTime.now();
      debugPrint(
        'voice_send_draft_stt_started messageId=$messageId '
        'reason=$reason bytes=${wavBytes.length} '
        'durationMs=$snapshotDurationMs',
      );
      try {
        final result = await backend.transcribeVoiceAudioDraft(
          roomId: widget.roomId,
          audioBytes: wavBytes,
          contentType: 'audio/wav',
          durationMs: snapshotDurationMs,
          language: 'ko-KR',
        );
        final transcript = _sanitizeVoiceTranscriptCandidate(
          result?.transcript ?? '',
        );
        debugPrint(
          'voice_send_draft_stt_completed messageId=$messageId '
          'reason=$reason '
          'clientMs=${DateTime.now().difference(startedAt).inMilliseconds} '
          'serverTotalMs=${result?.totalMs ?? -1} '
          'serverSttMs=${result?.sttMs ?? -1} '
          'transcriptLength=${transcript.length}',
        );
        if (transcript.isNotEmpty) {
          acceptLateTranscript(transcript, audioFilePath: audioFilePath);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'voice_send_draft_stt_failed '
          'messageId=$messageId reason=$reason error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    void detachStreamRecorderState({required String reason}) {
      final subscription = _recordStreamSub;
      _recordStreamSub = null;
      if (subscription != null) {
        unawaited(
          subscription
              .cancel()
              .timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {
                  debugPrint(
                    'voice_record_stream_cancel_timeout reason=$reason',
                  );
                },
              )
              .catchError((Object error) {
                debugPrint(
                  'voice_record_stream_cancel_failed reason=$reason error=$error',
                );
              }),
        );
      }
      unawaited(
        _recorder
            .cancel()
            .timeout(
              const Duration(milliseconds: 500),
              onTimeout: () {
                debugPrint('voice_record_cancel_timeout streamMode=true');
              },
            )
            .catchError((Object error) {
              debugPrint(
                'voice_record_cancel_failed streamMode=true error=$error',
              );
            }),
      );
      _recordStreamBytes = null;
      _recordStreamByteCount = 0;
      _streamRecordingPath = null;
      _deepgramStreamingStt = null;
    }

    Uint8List? streamPcmSnapshot;
    String? streamWavPathSnapshot;
    Uint8List? normalizedStreamPcmSnapshot;
    Uint8List? streamWavBytesSnapshot;
    var streamSnapshotInvalid = false;
    var sendSnapshotDraftStarted = false;
    if (wasStreamRecordingActive) {
      streamPcmSnapshot = _recordStreamBytes?.toBytes();
      streamWavPathSnapshot = _streamRecordingPath;
      final minExpectedBytes = (durationMs * 16000 * 2 * 0.18 / 1000).round();
      streamSnapshotInvalid =
          streamPcmSnapshot == null ||
          streamPcmSnapshot.isEmpty ||
          streamWavPathSnapshot == null ||
          streamPcmSnapshot.length < minExpectedBytes;
      if (!streamSnapshotInvalid) {
        normalizedStreamPcmSnapshot = _normalizeFinalVoicePcm(
          messageId: '${messageId}_snapshot',
          pcmBytes: streamPcmSnapshot,
        );
        streamWavBytesSnapshot = buildPcm16WavBytes(
          pcmBytes: normalizedStreamPcmSnapshot,
        );
        if (canCreateOptimistic && latestTranscript.isEmpty) {
          sendSnapshotDraftStarted = true;
          unawaited(
            runDraftSttFromWavBytes(
              wavBytes: streamWavBytesSnapshot,
              audioFilePath: streamWavPathSnapshot,
              reason: 'send_snapshot',
              snapshotDurationMs: durationMs,
            ),
          );
        }
      }
    }

    if (wasDeviceSttActive) {
      unawaited(
        _speechRecognizer.stop(
          waitForFinal: false,
          onFinalTranscript: acceptLateTranscript,
        ),
      );
    }
    if (wasPcmDeviceSttActive) {
      unawaited(
        _pcmDeviceSpeechRecognizer.stop(
          timeout: _voiceFinalTranscriptGrace,
          onFinalTranscript: acceptLateTranscript,
        ),
      );
    }
    if (wasDeepgramSttActive && deepgramStt != null) {
      unawaited(
        deepgramStt.stop(
          timeout: _voiceFinalTranscriptGrace,
          onFinalTranscript: acceptLateTranscript,
        ),
      );
    }
    // Keep the user-facing send path below one second, but give late live-STT
    // results a final chance before showing the bubble without transcript.
    final shouldWaitForLiveFinal = latestTranscript.isEmpty;
    final fastFinalWaitMs = shouldWaitForLiveFinal
        ? _kVoiceTranscriptWaitWhenEmpty.inMilliseconds
        : 0;
    final fastFinalWaitStartedAt = DateTime.now();
    if (canCreateOptimistic &&
        latestTranscript.isEmpty &&
        fastFinalWaitMs > 0) {
      await fastFinalCompleter.future.timeout(
        Duration(milliseconds: fastFinalWaitMs),
        onTimeout: () {},
      );
    }
    final fastFinalWaitedMs = DateTime.now()
        .difference(fastFinalWaitStartedAt)
        .inMilliseconds;
    if (wasStreamRecordingActive) {
      final minExpectedBytes = (durationMs * 16000 * 2 * 0.18 / 1000).round();
      if (canCreateOptimistic && streamSnapshotInvalid) {
        debugPrint(
          'voice_send_invalid_stream_snapshot messageId=$messageId '
          'bytes=${streamPcmSnapshot?.length ?? 0} '
          'minExpectedBytes=$minExpectedBytes '
          'hasPath=${streamWavPathSnapshot != null}',
        );
        _stopwatch.stop();
        detachStreamRecorderState(reason: 'invalid_snapshot');
        if (wasDeviceSttActive) {
          unawaited(_speechRecognizer.cancel());
        }
        if (wasPcmDeviceSttActive) {
          unawaited(_pcmDeviceSpeechRecognizer.cancel());
        }
        if (wasDeepgramSttActive) {
          unawaited(deepgramStt?.cancel());
        }
        if (mounted) {
          setState(() {
            _recording = false;
            _deviceSttActive = false;
            _pcmDeviceSttActive = false;
            _deepgramSttActive = false;
          });
        }
        _showError(
          '\uB179\uC74C \uC624\uB514\uC624\uAC00 \uC815\uC0C1\uC801\uC73C\uB85C \uCEA1\uCC98\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.',
        );
        _scheduleNextDeepgramPreconnect();
        return;
      }
    }
    if (canCreateOptimistic) {
      final forceServerSttCorrection =
          _kForceServerSttCorrection ||
          _shouldForceServerSttCorrection(
            transcript: latestTranscript,
            durationMs: durationMs,
            snapshot: sttSnapshotAtSend,
          );
      emitOptimisticBubble();
      final realtimeProviderLabel =
          deepgramStt?.providerLabel ?? _realtimeSttProviderLogLabel;
      final sttProviderLabel = wasDeepgramSttActive && wasDeviceSttActive
          ? '$realtimeProviderLabel+device_streaming'
          : wasDeepgramSttActive && wasPcmDeviceSttActive
          ? '$realtimeProviderLabel+pcm_device'
          : wasPcmDeviceSttActive
          ? 'pcm_device'
          : wasDeepgramSttActive
          ? realtimeProviderLabel
          : wasDeviceSttActive
          ? 'device_streaming'
          : 'server_fallback';
      final sendTapToTranscriptAvailableMs = transcriptAvailableAt == null
          ? -1
          : transcriptAvailableAt!.difference(sendTappedAt).inMilliseconds;
      debugPrint(
        'voice_send_client_timing messageId=$messageId '
        'sendTapToPendingBubbleMs=$sendTapToPendingBubbleMs '
        'sendTapToTranscriptAvailableMs=$sendTapToTranscriptAvailableMs '
        'fastFinalWaitMs=$fastFinalWaitMs '
        'fastFinalWaitedMs=$fastFinalWaitedMs '
        'sttStopMode=fast_final_grace '
        'sttProvider=$sttProviderLabel '
        'recordStartToFirstAudioSentMs=${sttSnapshotAtSend.recordStartToFirstAudioSentMs ?? -1} '
        'recordStartToFirstSpeechMs=${sttSnapshotAtSend.recordStartToFirstSpeechMs ?? -1} '
        'recordStartToFirstPartialMs=${sttSnapshotAtSend.recordStartToFirstPartialMs ?? -1} '
        'firstAudioSentToFirstPartialMs=${sttSnapshotAtSend.firstAudioSentToFirstPartialMs ?? -1} '
        'speechStartToFirstPartialMs=${sttSnapshotAtSend.speechStartToFirstPartialMs ?? -1} '
        'recordStartToLastTranscriptMs=${sttSnapshotAtSend.recordStartToLastTranscriptMs ?? -1} '
        'maxInputRms=${_voiceSttSession?.maxInputRms.toStringAsFixed(1) ?? '0.0'} '
        'maxInputPeak=${_voiceSttSession?.maxInputPeak ?? 0} '
        'finalTranscriptReadyBeforeSend=${latestTranscript.isNotEmpty} '
        'forceServerSttCorrection=$forceServerSttCorrection',
      );
      if (latestTranscript.isEmpty) {
        debugPrint(
          'voice_send_transcript_missing_at_send messageId=$messageId '
          'provider=$sttProviderLabel '
          'durationMs=$durationMs '
          'fastFinalWaitMs=$fastFinalWaitMs '
          'sttError=${sttSnapshotAtSend.errorCode ?? 'none'}',
        );
      }
      startPendingCreate();
    }
    final forceServerSttCorrection =
        _kForceServerSttCorrection ||
        _shouldForceServerSttCorrection(
          transcript: latestTranscript,
          durationMs: durationMs,
          snapshot: sttSnapshotAtSend,
        );
    if (wasStreamRecordingActive &&
        canCreateOptimistic &&
        streamPcmSnapshot != null &&
        streamWavPathSnapshot != null) {
      final pcmBytes = streamPcmSnapshot;
      final wavPath = streamWavPathSnapshot;
      unawaited(
        (() async {
          final streamStopStartedAt = DateTime.now();
          try {
            final normalizedPcm =
                normalizedStreamPcmSnapshot ??
                _normalizeFinalVoicePcm(
                  messageId: messageId,
                  pcmBytes: pcmBytes,
                );
            final wavBytes =
                streamWavBytesSnapshot ??
                buildPcm16WavBytes(pcmBytes: normalizedPcm);
            final startedInlineFromBytes =
                latestTranscript.isEmpty && !sendSnapshotDraftStarted;
            if (startedInlineFromBytes) {
              unawaited(
                runInlineSttFromWavBytes(
                  wavBytes: wavBytes,
                  audioFilePath: wavPath,
                  reason: 'stream_snapshot',
                ),
              );
            }
            await writePcm16WavFile(path: wavPath, pcmBytes: normalizedPcm);
            debugPrint(
              'voice_record_stream_stopped messageId=$messageId '
              'bytes=${normalizedPcm.length} '
              'stopMs=${DateTime.now().difference(streamStopStartedAt).inMilliseconds}',
            );
            await backend.sendInstantVoiceMessage(
              roomId: widget.roomId,
              audioFilePath: wavPath,
              durationMs: durationMs,
              sendMode: SendMode.instant,
              transcriptOverride: latestTranscript.isNotEmpty
                  ? latestTranscript
                  : null,
              replyToMessageId: widget.replyTo?.id,
              clientMessageId: messageId,
              pendingAlreadyCreated: pendingCreateFuture != null,
              forceServerSttCorrection: forceServerSttCorrection,
              skipInlineStt: startedInlineFromBytes,
            );
            await persistLatestTranscript(reason: 'stream_finalize_started');
          } catch (error, stackTrace) {
            debugPrint('Failed to finalize streaming voice message: $error');
            debugPrintStack(stackTrace: stackTrace);
            widget.onRemoveOptimisticVoiceMessage(messageId);
            if (mounted) {
              _showError(_composerErrorMessage(error));
            }
          }
        })(),
      );
      _stopwatch.stop();
      detachStreamRecorderState(reason: 'snapshot_finalizing');
      if (mounted) {
        setState(() {
          _recording = false;
          _deviceSttActive = false;
          _pcmDeviceSttActive = false;
          _deepgramSttActive = false;
        });
      }
      _scheduleNextDeepgramPreconnect();
      return;
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _deviceSttActive = false;
        _pcmDeviceSttActive = false;
        _deepgramSttActive = false;
      });
    }
    String? path;
    try {
      if (wasStreamRecordingActive) {
        final streamStopStartedAt = DateTime.now();
        final subscription = _recordStreamSub;
        _recordStreamSub = null;
        if (subscription != null) {
          unawaited(
            subscription
                .cancel()
                .timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () {
                    debugPrint(
                      'voice_record_stream_cancel_timeout reason=stop_recording',
                    );
                  },
                )
                .catchError((Object error) {
                  debugPrint(
                    'voice_record_stream_cancel_failed reason=stop_recording '
                    'error=$error',
                  );
                }),
          );
        }
        final bytes = _recordStreamBytes?.toBytes();
        final streamPath = _streamRecordingPath;
        if (bytes != null && bytes.isNotEmpty && streamPath != null) {
          final minExpectedBytes = (durationMs * 16000 * 2 * 0.18 / 1000)
              .round();
          if (bytes.length < minExpectedBytes) {
            throw StateError(
              '\uB179\uC74C \uC624\uB514\uC624\uAC00 \uC815\uC0C1\uC801\uC73C\uB85C \uCEA1\uCC98\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.',
            );
          }
          final normalizedPcm = _normalizeFinalVoicePcm(
            messageId: messageId,
            pcmBytes: bytes,
          );
          await writePcm16WavFile(path: streamPath, pcmBytes: normalizedPcm);
          path = streamPath;
          debugPrint(
            'voice_record_stream_stopped messageId=$messageId '
            'bytes=${normalizedPcm.length} '
            'stopMs=${DateTime.now().difference(streamStopStartedAt).inMilliseconds}',
          );
        } else {
          throw StateError(
            '\uB179\uC74C \uC624\uB514\uC624\uAC00 \uC815\uC0C1\uC801\uC73C\uB85C \uCEA1\uCC98\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.',
          );
        }
        unawaited(
          _recorder
              .cancel()
              .timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {
                  debugPrint('voice_record_cancel_timeout streamMode=true');
                },
              )
              .catchError((Object error) {
                debugPrint(
                  'voice_record_cancel_failed streamMode=true error=$error',
                );
              }),
        );
      } else {
        path = await _stopRecorderForVoiceSend(streamMode: false);
      }
    } catch (error) {
      if (wasDeviceSttActive) {
        await _speechRecognizer.cancel();
      }
      if (wasDeepgramSttActive) {
        await deepgramStt?.cancel();
      }
      widget.onRemoveOptimisticVoiceMessage(messageId);
      _showError(_composerErrorMessage(error));
      _scheduleNextDeepgramPreconnect();
      return;
    } finally {
      _stopwatch.stop();
      await _cancelRecordStreamSubscription(reason: 'finally');
      _recordStreamBytes = null;
      _recordStreamByteCount = 0;
      _streamRecordingPath = null;
      _deepgramStreamingStt = null;
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _deviceSttActive = false;
        _pcmDeviceSttActive = false;
        _deepgramSttActive = false;
      });
    }
    final debugDraft = await _consumeDebugVoiceDraft();
    final effectivePath = debugDraft?.audioFilePath ?? path;
    final effectiveDurationMs = debugDraft?.durationMs ?? durationMs;
    final debugTranscript = debugDraft?.transcript.trim();
    if (debugTranscript?.isNotEmpty == true) {
      acceptLateTranscript(
        debugTranscript!,
        audioFilePath: effectivePath ?? '',
      );
    }
    if (effectivePath == null || effectiveDurationMs < 500) {
      if (wasDeviceSttActive) {
        await _speechRecognizer.cancel();
      }
      widget.onRemoveOptimisticVoiceMessage(messageId);
      _showError(
        '\uB179\uC74C \uC2DC\uAC04\uC774 \uB108\uBB34 \uC9E7\uC2B5\uB2C8\uB2E4.',
      );
      _scheduleNextDeepgramPreconnect();
      return;
    }
    final audioFilePath = effectivePath;

    if (canCreateOptimistic) {
      emitOptimisticBubble(
        audioFilePath: audioFilePath,
        durationOverrideMs: effectiveDurationMs,
      );
    }
    startPendingCreate();
    unawaited(
      (() async {
        try {
          await backend.sendInstantVoiceMessage(
            roomId: widget.roomId,
            audioFilePath: audioFilePath,
            durationMs: effectiveDurationMs,
            sendMode: SendMode.instant,
            transcriptOverride: latestTranscript.isNotEmpty
                ? latestTranscript
                : null,
            replyToMessageId: widget.replyTo?.id,
            clientMessageId: messageId,
            pendingAlreadyCreated: pendingCreateFuture != null,
            forceServerSttCorrection:
                _kForceServerSttCorrection ||
                _shouldForceServerSttCorrection(
                  transcript: latestTranscript,
                  durationMs: effectiveDurationMs,
                  snapshot: sttSnapshotAtSend,
                ),
          );
          await persistLatestTranscript(reason: 'file_finalize_started');
        } catch (error, stackTrace) {
          debugPrint('Failed to send optimistic voice message: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (mounted) {
            _showError(_composerErrorMessage(error));
          }
        }
      })(),
    );
    _scheduleNextDeepgramPreconnect();
    /*
    var sttStopRequested = false;
    await _run(() async {
      final backend = BackendScope.of(context);
      final initialTranscript = debugTranscript?.isNotEmpty == true
          ? debugTranscript
          : sttSnapshotAtSend.transcript.trim();
      final transcriptOverride = initialTranscript;
      const fastFinalWaitMs = 0;
      final transcriptReadyBeforeSend = transcriptOverride?.isNotEmpty == true;

      final messageId = await backend.sendInstantVoiceMessage(
        roomId: widget.roomId,
        audioFilePath: audioFilePath,
        durationMs: effectiveDurationMs,
        sendMode: SendMode.instant,
        transcriptOverride: transcriptReadyBeforeSend
            ? transcriptOverride
            : null,
        replyToMessageId: widget.replyTo?.id,
      );
      _emitOptimisticVoiceMessage(
        messageId: messageId,
        audioFilePath: audioFilePath,
        durationMs: effectiveDurationMs,
        transcript: transcriptReadyBeforeSend ? transcriptOverride : null,
        createdAt: DateTime.now(),
      );
      final sendTapToPendingBubbleMs = DateTime.now()
          .difference(sendTappedAt)
          .inMilliseconds;
      debugPrint(
        'voice_send_client_timing messageId=$messageId '
        'sendTapToPendingBubbleMs=$sendTapToPendingBubbleMs '
        'sendTapToTranscriptAvailableMs=${transcriptReadyBeforeSend ? 0 : -1} '
        'fastFinalWaitMs=$fastFinalWaitMs '
        'sttStopMode=non_blocking '
        'recordStartToFirstPartialMs=${sttSnapshotAtSend.recordStartToFirstPartialMs ?? -1} '
        'recordStartToLastTranscriptMs=${sttSnapshotAtSend.recordStartToLastTranscriptMs ?? -1} '
        'finalTranscriptReadyBeforeSend=$transcriptReadyBeforeSend',
      );
      if (wasDeviceSttActive) {
        sttStopRequested = true;
        unawaited(
          _speechRecognizer.stop(
            waitForFinal: false,
            onFinalTranscript: (transcript) {
              final current = transcriptOverride?.trim() ?? '';
              final next = transcript.trim();
              if (next.isEmpty || next == current) {
                return;
              }
              _emitOptimisticVoiceMessage(
                messageId: messageId,
                audioFilePath: audioFilePath,
                durationMs: effectiveDurationMs,
                transcript: next,
                createdAt: sendTappedAt,
              );
              unawaited(
                backend.updateClientVoiceTranscript(
                  roomId: widget.roomId,
                  messageId: messageId,
                  transcript: next,
                ),
              );
            },
          ),
        );
      }
      widget.onSent();
    }, busyLabel: '\uC74C\uC131 \uBA54\uC2DC\uC9C0\uB97C \uBCF4\uB0B4\uB294 \uC911\uC785\uB2C8\uB2E4.');
    if (wasDeviceSttActive && !sttStopRequested) {
      await _speechRecognizer.cancel();
    }
    */
  }

  Future<String?> _stopRecorderForVoiceSend({required bool streamMode}) async {
    if (!streamMode) {
      return _recorder.stop();
    }
    return _recorder.stop().timeout(
      const Duration(milliseconds: 700),
      onTimeout: () {
        debugPrint('voice_record_stop_timeout streamMode=true');
        unawaited(
          _recorder.cancel().catchError((Object error) {
            debugPrint('voice_record_cancel_after_timeout_failed: $error');
          }),
        );
        return null;
      },
    );
  }

  Future<void> _cancelRecordStreamSubscription({required String reason}) async {
    final subscription = _recordStreamSub;
    _recordStreamSub = null;
    if (subscription == null) {
      return;
    }
    await subscription.cancel().timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {
        debugPrint('voice_record_stream_cancel_timeout reason=$reason');
      },
    );
  }

  // ignore: unused_element
  Future<void> _stopRecordingLegacy() async {
    final wasFreeSttActive = _freeSttActive;
    _timer?.cancel();
    final durationMs = _stopwatch.elapsedMilliseconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      if (wasFreeSttActive) {
        await _speechRecognizer.cancel();
      }
      rethrow;
    } finally {
      _stopwatch.stop();
    }
    if (mounted) {
      setState(() => _recording = false);
    }
    String? manualTranscript;
    if (wasFreeSttActive) {
      try {
        manualTranscript = await _speechRecognizer.stop();
      } catch (_) {
        await _speechRecognizer.cancel();
      }
    }
    final liveTranscript = manualTranscript?.trim().isNotEmpty == true
        ? manualTranscript
        : _liveTranscript.trim();
    setState(() {
      _recording = false;
      _freeSttActive = false;
    });
    final debugDraft = await _consumeDebugVoiceDraft();
    final effectivePath = debugDraft?.audioFilePath ?? path;
    final effectiveDurationMs = debugDraft?.durationMs ?? durationMs;
    final debugTranscript = debugDraft?.transcript.trim();
    if (effectivePath == null || effectiveDurationMs < 500) {
      _showError(
        '\uB179\uC74C \uC2DC\uAC04\uC774 \uB108\uBB34 \uC9E7\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    final audioFilePath = effectivePath;

    await _run(
      () async {
        final backend = BackendScope.of(context);
        final transcriptOverride = debugTranscript?.isNotEmpty == true
            ? debugTranscript
            : liveTranscript?.trim();

        await backend.sendInstantVoiceMessage(
          roomId: widget.roomId,
          audioFilePath: audioFilePath,
          durationMs: effectiveDurationMs,
          sendMode: SendMode.instant,
          transcriptOverride: transcriptOverride?.isNotEmpty == true
              ? transcriptOverride
              : null,
          replyToMessageId: widget.replyTo?.id,
        );
        widget.onSent();
      },
      busyLabel:
          '\uC74C\uC131 \uBA54\uC2DC\uC9C0\uB97C \uBCF4\uB0B4\uB294 \uC911\uC785\uB2C8\uB2E4.',
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
      _showError(_composerErrorMessage(error));
    } finally {
      if (mounted && keepBusy) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<_DebugVoiceDraft?> _consumeDebugVoiceDraft() async {
    if (!kDebugMode) {
      return null;
    }
    try {
      final result = await _debugVoiceChannel.invokeMapMethod<String, Object?>(
        'consumeNextVoiceDraft',
      );
      if (result == null) {
        return null;
      }
      final audioFilePath = (result['audioFilePath'] as String?)?.trim();
      final durationMs = (result['durationMs'] as num?)?.toInt();
      if (audioFilePath == null ||
          audioFilePath.isEmpty ||
          durationMs == null ||
          durationMs <= 0) {
        return null;
      }
      return _DebugVoiceDraft(
        audioFilePath: audioFilePath,
        durationMs: durationMs,
        transcript: (result['transcript'] as String? ?? '').trim(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
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

  String _composerErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('Speech-to-text failed') ||
        raw.contains(
          '\uC74C\uC131 \uC778\uC2DD\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4',
        )) {
      return '\uC74C\uC131 \uC778\uC2DD\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.';
    }
    if (raw.contains('firebase_storage/unauthorized') ||
        raw.contains('voice_audio_access_denied')) {
      return '\uC74C\uC131 \uD30C\uC77C\uC744 \uBD88\uB7EC\uC62C \uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB85C\uADF8\uC778\uD55C \uB4A4 \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.';
    }
    if (raw.contains('normal capture') ||
        raw.contains('invalid stream snapshot') ||
        raw.contains('stream snapshot')) {
      return '\uB179\uC74C \uC624\uB514\uC624\uAC00 \uC815\uC0C1\uC801\uC73C\uB85C \uCEA1\uCC98\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.';
    }
    final firstLine = raw
        .split('\n')
        .first
        .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '')
        .replaceFirst('Bad state: ', '')
        .trim();
    if (firstLine.isEmpty) {
      return '\uCC98\uB9AC \uC911 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.';
    }
    return firstLine.length > 140
        ? '${firstLine.substring(0, 140)}...'
        : firstLine;
  }
}

class _DebugVoiceDraft {
  const _DebugVoiceDraft({
    required this.audioFilePath,
    required this.durationMs,
    required this.transcript,
  });

  final String audioFilePath;
  final int durationMs;
  final String transcript;
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
              message.displayText.isEmpty
                  ? '\uC6D0\uBCF8 \uBA54\uC2DC\uC9C0'
                  : message.displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: '\uB2F5\uC7A5 \uCDE8\uC18C',
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
        '\uC544\uC9C1 \uBA54\uC2DC\uC9C0\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
        style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
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
  final period = value.hour < 12 ? '\uC624\uC804' : '\uC624\uD6C4';
  final rawHour = value.hour % 12;
  final hour = rawHour == 0 ? 12 : rawHour;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$period $hour:$minute';
}

String _scheduleLabel(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day ${_clockLabel(value)}';
}

String _proposalStatusLabel(CalendarProposal proposal) {
  if (proposal.isFinalized && proposal.finalCandidate != null) {
    return '\uD655\uC815\uB428';
  }
  if (proposal.isCancelled) {
    return '\uCDE8\uC18C\uB428';
  }
  return '\uC77C\uC815 \uD22C\uD45C \uC911';
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
