import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'messenger_backend.dart';

class DeepgramLiveSnapshot {
  const DeepgramLiveSnapshot({
    required this.lastInterimTranscript,
    required this.lastStableTranscript,
    required this.startedAt,
    required this.firstAudioSentAt,
    required this.firstSpeechAt,
    required this.firstPartialAt,
    required this.lastUpdateAt,
    required this.errorCode,
  });

  final String lastInterimTranscript;
  final String lastStableTranscript;
  final DateTime? startedAt;
  final DateTime? firstAudioSentAt;
  final DateTime? firstSpeechAt;
  final DateTime? firstPartialAt;
  final DateTime? lastUpdateAt;
  final String? errorCode;

  String get transcript {
    return _mergeStreamingTranscripts(
      lastStableTranscript,
      lastInterimTranscript,
    );
  }

  int? get recordStartToFirstPartialMs {
    final start = startedAt;
    final first = firstPartialAt;
    if (start == null || first == null) {
      return null;
    }
    return first.difference(start).inMilliseconds;
  }

  int? get recordStartToFirstAudioSentMs {
    final start = startedAt;
    final firstAudio = firstAudioSentAt;
    if (start == null || firstAudio == null) {
      return null;
    }
    return firstAudio.difference(start).inMilliseconds;
  }

  int? get recordStartToFirstSpeechMs {
    final start = startedAt;
    final firstSpeech = firstSpeechAt;
    if (start == null || firstSpeech == null) {
      return null;
    }
    return firstSpeech.difference(start).inMilliseconds;
  }

  int? get firstAudioSentToFirstPartialMs {
    final firstAudio = firstAudioSentAt;
    final first = firstPartialAt;
    if (firstAudio == null || first == null) {
      return null;
    }
    return first.difference(firstAudio).inMilliseconds;
  }

  int? get speechStartToFirstPartialMs {
    final speech = firstSpeechAt;
    final first = firstPartialAt;
    if (speech == null || first == null) {
      return null;
    }
    return first.difference(speech).inMilliseconds;
  }

  int? get recordStartToLastTranscriptMs {
    final start = startedAt;
    final last = lastUpdateAt;
    if (start == null || last == null) {
      return null;
    }
    return last.difference(start).inMilliseconds;
  }
}

String _mergeStreamingTranscripts(String stable, String interim) {
  final left = stable.trim();
  final right = interim.trim();
  if (left.isEmpty) {
    return right;
  }
  if (right.isEmpty) {
    return left;
  }

  final normalizedLeft = _normalizeTranscriptForMerge(left);
  final normalizedRight = _normalizeTranscriptForMerge(right);
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
    if (_normalizeTranscriptForMerge(leftSuffix) ==
        _normalizeTranscriptForMerge(rightPrefix)) {
      return [...leftTokens, ...rightTokens.sublist(size)].join(' ').trim();
    }
  }
  return '$left $right'.trim();
}

String _normalizeTranscriptForMerge(String value) {
  return value
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '')
      .toLowerCase();
}

class DeepgramStreamingStt {
  DeepgramStreamingStt({
    required this.tokenProvider,
    this.providerLabel = 'deepgram_streaming',
  });

  static bool get enabled => const bool.fromEnvironment(
    'VERBAL_DEEPGRAM_STREAMING_STT',
    defaultValue: true,
  );

  final Future<DeepgramStreamingToken?> Function() tokenProvider;
  final String providerLabel;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  ValueChanged<String>? _onTranscript;
  ValueChanged<DeepgramLiveSnapshot>? _onSnapshot;
  Completer<String?>? _stopCompleter;
  Timer? _keepAliveTimer;
  DateTime? _startedAt;
  DateTime? _firstAudioSentAt;
  DateTime? _firstSpeechAt;
  DateTime? _firstPartialAt;
  DateTime? _lastUpdateAt;
  var _lastInterimTranscript = '';
  var _lastStableTranscript = '';
  String? _errorCode;
  var _started = false;
  var _finalizeRequested = false;
  var _sentAudioBytes = 0;
  var _emptyFinalCount = 0;

  bool get isReady =>
      _started && _socket?.readyState == WebSocket.open && !_finalizeRequested;

  Future<bool> start({
    ValueChanged<String>? onTranscript,
    ValueChanged<DeepgramLiveSnapshot>? onSnapshot,
    DateTime? startedAt,
  }) async {
    if (!enabled) {
      return false;
    }
    await cancel();
    final token = await tokenProvider().timeout(
      const Duration(milliseconds: 5000),
      onTimeout: () => null,
    );
    if (token == null) {
      return false;
    }
    try {
      final socket = await WebSocket.connect(
        token.url,
        headers: {'Authorization': 'Bearer ${token.accessToken}'},
      ).timeout(const Duration(milliseconds: 3500));
      socket.pingInterval = const Duration(seconds: 8);
      _socket = socket;
      unawaited(
        socket.done.catchError((Object error) {
          if (_socket == socket) {
            _errorCode = error.toString();
            debugPrint('deepgram_stream_socket_done_error error=$_errorCode');
            _finishStop();
          }
          return null;
        }),
      );
      _configureSession(
        onTranscript: onTranscript,
        onSnapshot: onSnapshot,
        startedAt: startedAt ?? DateTime.now(),
      );
      _socketSub = socket.listen(
        _handleMessage,
        onError: (Object error) {
          _errorCode = error.toString();
          debugPrint('deepgram_stream_error error=$_errorCode');
          _finishStop();
        },
        onDone: _finishStop,
        cancelOnError: true,
      );
      _startKeepAlive();
      return true;
    } catch (error) {
      _errorCode = error.toString();
      debugPrint('deepgram_stream_start_failed error=$_errorCode');
      await cancel();
      return false;
    }
  }

  bool attachSession({
    required DateTime startedAt,
    ValueChanged<String>? onTranscript,
    ValueChanged<DeepgramLiveSnapshot>? onSnapshot,
  }) {
    if (!isReady) {
      return false;
    }
    _configureSession(
      onTranscript: onTranscript,
      onSnapshot: onSnapshot,
      startedAt: startedAt,
    );
    return true;
  }

  void sendAudio(Uint8List chunk) {
    if (!_started || chunk.isEmpty) {
      return;
    }
    _firstAudioSentAt ??= DateTime.now();
    _sentAudioBytes += chunk.length;
    _sendSocket(chunk, context: 'audio');
  }

  void markSpeechDetected(DateTime detectedAt) {
    if (!_started) {
      return;
    }
    _firstSpeechAt ??= detectedAt;
  }

  void sendKeepAlive() {
    if (!_started || _finalizeRequested) {
      return;
    }
    _sendSocket(jsonEncode({'type': 'KeepAlive'}), context: 'keepalive');
  }

  Future<String?> stop({
    Duration timeout = const Duration(milliseconds: 1000),
    ValueChanged<String>? onFinalTranscript,
  }) async {
    if (!_started) {
      return _currentTranscript();
    }
    final previous = _currentTranscript();
    _finalizeRequested = true;
    final completer = Completer<String?>();
    _stopCompleter = completer;
    final stopStartedAt = DateTime.now();
    final finalizeSent = _sendSocket(
      jsonEncode({'type': 'Finalize'}),
      context: 'finalize',
    );
    _started = false;
    if (!finalizeSent) {
      _finishStop();
    }
    final transcript = await completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint(
          'deepgram_stream_stop_timeout bytes=$_sentAudioBytes '
          'emptyFinalCount=$_emptyFinalCount '
          'hasTranscript=${_currentTranscript()?.isNotEmpty == true}',
        );
        return _currentTranscript();
      },
    );
    final current = transcript?.trim() ?? '';
    debugPrint(
      'deepgram_stream_stop_result bytes=$_sentAudioBytes '
      'transcriptLength=${current.length} '
      'stopWaitMs=${DateTime.now().difference(stopStartedAt).inMilliseconds} '
      'error=${_errorCode ?? 'none'}',
    );
    if (current.isNotEmpty && current != (previous ?? '')) {
      onFinalTranscript?.call(current);
    }
    await _closeSocket();
    return current.isEmpty ? null : current;
  }

  Future<void> cancel() async {
    _started = false;
    await _closeSocket();
    _resetCallbacks();
  }

  void _configureSession({
    required DateTime startedAt,
    ValueChanged<String>? onTranscript,
    ValueChanged<DeepgramLiveSnapshot>? onSnapshot,
  }) {
    _onTranscript = onTranscript;
    _onSnapshot = onSnapshot;
    _startedAt = startedAt;
    _firstAudioSentAt = null;
    _firstSpeechAt = null;
    _firstPartialAt = null;
    _lastUpdateAt = null;
    _lastInterimTranscript = '';
    _lastStableTranscript = '';
    _errorCode = null;
    _finalizeRequested = false;
    _sentAudioBytes = 0;
    _emptyFinalCount = 0;
    _started = true;
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      sendKeepAlive();
    });
  }

  bool _sendSocket(dynamic value, {required String context}) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return false;
    }
    try {
      socket.add(value);
      return true;
    } catch (error) {
      _errorCode = error.toString();
      debugPrint('deepgram_stream_${context}_send_failed error=$_errorCode');
      _finishStop();
      return false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final text = message is String
          ? message
          : message is List<int>
          ? utf8.decode(message)
          : '';
      if (text.isEmpty) {
        return;
      }
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) {
        return;
      }
      if (data['type'] == 'Error') {
        _errorCode = (data['message'] ?? data['err_code'] ?? 'deepgram_error')
            .toString();
        debugPrint('deepgram_stream_api_error error=$_errorCode');
        if (_finalizeRequested) {
          _finishStop();
        }
        return;
      }
      if (data['type'] != 'Results') {
        return;
      }
      final channel = data['channel'];
      if (channel is! Map<String, dynamic>) {
        return;
      }
      final alternatives = channel['alternatives'];
      if (alternatives is! List || alternatives.isEmpty) {
        return;
      }
      final first = alternatives.first;
      if (first is! Map<String, dynamic>) {
        return;
      }
      final transcript = (first['transcript'] as String? ?? '').trim();
      final isFinal = data['is_final'] == true || data['speech_final'] == true;
      if (transcript.isEmpty) {
        if (isFinal) {
          _emptyFinalCount += 1;
          if (kDebugMode) {
            debugPrint(
              'deepgram_stream_empty_final provider=$providerLabel '
              'finalizeRequested=$_finalizeRequested '
              'emptyFinalCount=$_emptyFinalCount '
              'hasTranscript=${_currentTranscript()?.isNotEmpty == true} '
              'bytes=$_sentAudioBytes',
            );
          }
          if (_finalizeRequested && _currentTranscript()?.isNotEmpty == true) {
            _finishStop();
          }
        }
        return;
      }
      if (isFinal) {
        if (_lastStableTranscript.isEmpty) {
          _lastStableTranscript = transcript;
        } else if (!_lastStableTranscript.endsWith(transcript)) {
          _lastStableTranscript = '$_lastStableTranscript $transcript'.trim();
        }
        _lastInterimTranscript = '';
      } else {
        _lastInterimTranscript = transcript;
      }
      final now = DateTime.now();
      _firstPartialAt ??= now;
      _lastUpdateAt = now;
      final current = _currentTranscript();
      if (current != null) {
        _onTranscript?.call(current);
      }
      _onSnapshot?.call(_snapshot());
      if (kDebugMode) {
        final snapshot = _snapshot();
        debugPrint(
          'voice_stt_transcript_update provider=$providerLabel '
          'length=${current?.length ?? 0} '
          'isFinal=$isFinal '
          'recordStartToFirstAudioSentMs=${snapshot.recordStartToFirstAudioSentMs ?? -1} '
          'recordStartToFirstSpeechMs=${snapshot.recordStartToFirstSpeechMs ?? -1} '
          'recordStartToFirstPartialMs=${snapshot.recordStartToFirstPartialMs ?? -1} '
          'firstAudioSentToFirstPartialMs=${snapshot.firstAudioSentToFirstPartialMs ?? -1} '
          'speechStartToFirstPartialMs=${snapshot.speechStartToFirstPartialMs ?? -1} '
          'recordStartToLastTranscriptMs=${snapshot.recordStartToLastTranscriptMs ?? -1}',
        );
      }
      if (_finalizeRequested && isFinal) {
        _finishStop();
      }
    } catch (error) {
      _errorCode = error.toString();
      debugPrint('deepgram_stream_parse_failed error=$_errorCode');
      if (_finalizeRequested) {
        _finishStop();
      }
    }
  }

  DeepgramLiveSnapshot _snapshot() {
    return DeepgramLiveSnapshot(
      lastInterimTranscript: _lastInterimTranscript,
      lastStableTranscript: _lastStableTranscript,
      startedAt: _startedAt,
      firstAudioSentAt: _firstAudioSentAt,
      firstSpeechAt: _firstSpeechAt,
      firstPartialAt: _firstPartialAt,
      lastUpdateAt: _lastUpdateAt,
      errorCode: _errorCode,
    );
  }

  String? _currentTranscript() {
    final transcript = _snapshot().transcript;
    return transcript.isEmpty ? null : transcript;
  }

  void _finishStop() {
    final completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(_currentTranscript());
    }
  }

  Future<void> _closeSocket() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    try {
      await _socketSub?.cancel();
    } catch (error) {
      _errorCode ??= error.toString();
      debugPrint('deepgram_stream_subscription_cancel_failed error=$error');
    }
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (error) {
      _errorCode ??= error.toString();
      debugPrint('deepgram_stream_socket_close_failed error=$error');
    }
    _socket = null;
  }

  void _resetCallbacks() {
    _onTranscript = null;
    _onSnapshot = null;
    _stopCompleter = null;
    _finalizeRequested = false;
  }
}
