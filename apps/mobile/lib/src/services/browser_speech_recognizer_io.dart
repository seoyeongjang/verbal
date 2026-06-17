import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceSttSnapshot {
  const VoiceSttSnapshot({
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
    return '$lastStableTranscript $lastInterimTranscript'.trim();
  }

  bool get hasTranscript => transcript.isNotEmpty;

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

class DeviceStreamingStt {
  DeviceStreamingStt() {
    _installHandler();
  }

  static const _channel = MethodChannel('verbal/free_speech_recognizer');

  static bool get enabled =>
      const bool.fromEnvironment('VERBAL_FREE_STT', defaultValue: true);

  static DeviceStreamingStt? _active;
  static var _handlerInstalled = false;

  ValueChanged<String>? _onTranscript;
  ValueChanged<VoiceSttSnapshot>? _onSnapshot;
  var _lastTranscript = '';
  var _lastErrorCode = '';
  DateTime? _startedAt;
  DateTime? _firstPartialAt;
  DateTime? _lastUpdateAt;
  var _started = false;

  bool get isAvailable =>
      enabled && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start({
    String language = 'ko-KR',
    ValueChanged<String>? onTranscript,
    ValueChanged<VoiceSttSnapshot>? onSnapshot,
  }) async {
    if (!enabled || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await cancel();
    _active = this;
    _onTranscript = onTranscript;
    _onSnapshot = onSnapshot;
    _lastTranscript = '';
    _lastErrorCode = '';
    _startedAt = DateTime.now();
    _firstPartialAt = null;
    _lastUpdateAt = null;
    final started = await _channel.invokeMethod<bool>('start', {
      'language': language,
    });
    if (started != true) {
      _active = null;
      throw StateError('기기 무료 STT를 사용할 수 없습니다.');
    }
    _started = true;
  }

  VoiceSttSnapshot snapshot() {
    return VoiceSttSnapshot(
      lastInterimTranscript: '',
      lastStableTranscript: _lastTranscript.trim(),
      startedAt: _startedAt,
      firstAudioSentAt: null,
      firstSpeechAt: null,
      firstPartialAt: _firstPartialAt,
      lastUpdateAt: _lastUpdateAt,
      errorCode: _lastErrorCode.isEmpty ? null : _lastErrorCode,
    );
  }

  Future<String?> stop({
    bool waitForFinal = true,
    Duration timeout = const Duration(seconds: 3),
    ValueChanged<String>? onFinalTranscript,
  }) async {
    if (!_started) {
      return _currentTranscript();
    }
    _started = false;
    final stopFuture = _channel
        .invokeMethod<String?>('stop')
        .timeout(timeout, onTimeout: _currentTranscript);

    if (!waitForFinal) {
      unawaited(
        stopFuture
            .then((transcript) {
              final previous = _currentTranscript() ?? '';
              _applyTranscript(transcript ?? previous);
              final current = _currentTranscript() ?? '';
              if (current.isNotEmpty && current != previous) {
                onFinalTranscript?.call(current);
              }
            })
            .catchError((Object error) {
              debugPrint('Device STT stop failed: $error');
            })
            .whenComplete(() {
              _onTranscript = null;
              _onSnapshot = null;
              if (_active == this) {
                _active = null;
              }
            }),
      );
      return _currentTranscript();
    }

    final transcript = await stopFuture;
    _applyTranscript(transcript ?? _lastTranscript);
    _onTranscript = null;
    _onSnapshot = null;
    if (_active == this) {
      _active = null;
    }
    return _currentTranscript();
  }

  Future<void> cancel() async {
    if (!_started) {
      _onTranscript = null;
      _onSnapshot = null;
      if (_active == this) {
        _active = null;
      }
      return;
    }
    _started = false;
    try {
      await _channel.invokeMethod<void>('cancel');
    } finally {
      _onTranscript = null;
      _onSnapshot = null;
      if (_active == this) {
        _active = null;
      }
    }
  }

  static void _installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final recognizer = _active;
      if (recognizer == null) {
        return;
      }
      switch (call.method) {
        case 'onTranscript':
          final args = call.arguments as Map?;
          final transcript = (args?['transcript'] as String? ?? '').trim();
          recognizer._applyTranscript(transcript);
          break;
        case 'onError':
          final args = call.arguments as Map?;
          final code = args?['code']?.toString() ?? 'unknown';
          recognizer._lastErrorCode = code;
          debugPrint('Free STT error: $code');
          break;
      }
    });
  }

  void _applyTranscript(String transcript) {
    final next = transcript.trim();
    if (next.isEmpty) {
      return;
    }
    _lastTranscript = next;
    final now = DateTime.now();
    _firstPartialAt ??= now;
    _lastUpdateAt = now;
    if (kDebugMode) {
      final firstMs = snapshot().recordStartToFirstPartialMs ?? -1;
      final lastMs = snapshot().recordStartToLastTranscriptMs ?? -1;
      debugPrint(
        'voice_stt_transcript_update length=${next.length} '
        'recordStartToFirstPartialMs=$firstMs '
        'recordStartToLastTranscriptMs=$lastMs',
      );
    }
    _onTranscript?.call(next);
    _onSnapshot?.call(snapshot());
  }

  String? _currentTranscript() {
    final transcript = _lastTranscript.trim();
    return transcript.isEmpty ? null : transcript;
  }
}

class BrowserSpeechRecognizer extends DeviceStreamingStt {
  BrowserSpeechRecognizer() : super();

  static bool get enabled => DeviceStreamingStt.enabled;
}

class PcmDeviceStreamingStt {
  PcmDeviceStreamingStt() {
    _installHandler();
  }

  static const _channel = MethodChannel('verbal/pcm_speech_recognizer');

  static bool get enabled =>
      const bool.fromEnvironment('VERBAL_PCM_DEVICE_STT', defaultValue: true);

  static PcmDeviceStreamingStt? _active;
  static var _handlerInstalled = false;

  ValueChanged<String>? _onTranscript;
  ValueChanged<VoiceSttSnapshot>? _onSnapshot;
  var _lastTranscript = '';
  var _lastErrorCode = '';
  DateTime? _startedAt;
  DateTime? _firstAudioSentAt;
  DateTime? _firstPartialAt;
  DateTime? _lastUpdateAt;
  var _started = false;

  bool get isAvailable =>
      enabled && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> start({
    String language = 'ko-KR',
    ValueChanged<String>? onTranscript,
    ValueChanged<VoiceSttSnapshot>? onSnapshot,
    DateTime? startedAt,
  }) async {
    if (!enabled || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    await cancel();
    _active = this;
    _onTranscript = onTranscript;
    _onSnapshot = onSnapshot;
    _lastTranscript = '';
    _lastErrorCode = '';
    _startedAt = startedAt ?? DateTime.now();
    _firstAudioSentAt = null;
    _firstPartialAt = null;
    _lastUpdateAt = null;
    final started = await _channel.invokeMethod<bool>('start', {
      'language': language,
    });
    if (started != true) {
      _active = null;
      return false;
    }
    _started = true;
    return true;
  }

  void sendAudio(Uint8List chunk) {
    if (!_started || chunk.isEmpty) {
      return;
    }
    _firstAudioSentAt ??= DateTime.now();
    unawaited(
      _channel.invokeMethod<bool>('writeAudio', chunk).catchError((
        Object error,
      ) {
        _lastErrorCode = error.toString();
        debugPrint('PCM device STT write failed: $error');
        return false;
      }),
    );
  }

  VoiceSttSnapshot snapshot() {
    return VoiceSttSnapshot(
      lastInterimTranscript: '',
      lastStableTranscript: _lastTranscript.trim(),
      startedAt: _startedAt,
      firstAudioSentAt: _firstAudioSentAt,
      firstSpeechAt: _firstAudioSentAt,
      firstPartialAt: _firstPartialAt,
      lastUpdateAt: _lastUpdateAt,
      errorCode: _lastErrorCode.isEmpty ? null : _lastErrorCode,
    );
  }

  Future<String?> stop({
    Duration timeout = const Duration(milliseconds: 2200),
    ValueChanged<String>? onFinalTranscript,
  }) async {
    if (!_started) {
      return _currentTranscript();
    }
    _started = false;
    final previous = _currentTranscript() ?? '';
    final transcript = await _channel
        .invokeMethod<String?>('stop')
        .timeout(timeout, onTimeout: _currentTranscript)
        .catchError((Object error) {
          _lastErrorCode = error.toString();
          debugPrint('PCM device STT stop failed: $error');
          return _currentTranscript();
        });
    _applyTranscript(transcript ?? previous);
    final current = _currentTranscript() ?? '';
    if (current.isNotEmpty && current != previous) {
      onFinalTranscript?.call(current);
    }
    _onTranscript = null;
    _onSnapshot = null;
    if (_active == this) {
      _active = null;
    }
    return current.isEmpty ? null : current;
  }

  Future<void> cancel() async {
    if (!_started) {
      _onTranscript = null;
      _onSnapshot = null;
      if (_active == this) {
        _active = null;
      }
      return;
    }
    _started = false;
    try {
      await _channel.invokeMethod<void>('cancel');
    } finally {
      _onTranscript = null;
      _onSnapshot = null;
      if (_active == this) {
        _active = null;
      }
    }
  }

  static void _installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final recognizer = _active;
      if (recognizer == null) {
        return;
      }
      switch (call.method) {
        case 'onTranscript':
          final args = call.arguments as Map?;
          final transcript = (args?['transcript'] as String? ?? '').trim();
          recognizer._applyTranscript(transcript);
          break;
        case 'onError':
          final args = call.arguments as Map?;
          final code = args?['code']?.toString() ?? 'unknown';
          recognizer._lastErrorCode = code;
          debugPrint('PCM device STT error: $code');
          break;
      }
    });
  }

  void _applyTranscript(String transcript) {
    final next = transcript.trim();
    if (next.isEmpty) {
      return;
    }
    _lastTranscript = next;
    final now = DateTime.now();
    _firstPartialAt ??= now;
    _lastUpdateAt = now;
    if (kDebugMode) {
      final snapshot = this.snapshot();
      debugPrint(
        'voice_stt_transcript_update provider=pcm_device '
        'length=${next.length} '
        'recordStartToFirstAudioSentMs=${snapshot.recordStartToFirstAudioSentMs ?? -1} '
        'recordStartToFirstPartialMs=${snapshot.recordStartToFirstPartialMs ?? -1} '
        'firstAudioSentToFirstPartialMs=${snapshot.firstAudioSentToFirstPartialMs ?? -1} '
        'recordStartToLastTranscriptMs=${snapshot.recordStartToLastTranscriptMs ?? -1}',
      );
    }
    _onTranscript?.call(next);
    _onSnapshot?.call(snapshot());
  }

  String? _currentTranscript() {
    final transcript = _lastTranscript.trim();
    return transcript.isEmpty ? null : transcript;
  }
}
