import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
  DeviceStreamingStt();

  static const enabled = bool.fromEnvironment('VERBAL_BROWSER_STT');

  _SpeechRecognition? _recognition;
  Completer<String?>? _stopCompleter;
  void Function(String transcript)? _onTranscript;
  void Function(VoiceSttSnapshot snapshot)? _onSnapshot;
  var _finalTranscript = '';
  var _interimTranscript = '';
  var _lastErrorCode = '';
  DateTime? _startedAt;
  DateTime? _firstPartialAt;
  DateTime? _lastUpdateAt;

  bool get isAvailable =>
      enabled &&
      (globalContext.has('SpeechRecognition') ||
          globalContext.has('webkitSpeechRecognition'));

  Future<void> start({
    String language = 'ko-KR',
    void Function(String transcript)? onTranscript,
    void Function(VoiceSttSnapshot snapshot)? onSnapshot,
  }) async {
    if (!enabled) {
      return;
    }
    if (!isAvailable) {
      throw StateError('브라우저 무료 STT를 지원하지 않습니다. Chrome 또는 Edge를 사용해 주세요.');
    }
    await cancel();

    _finalTranscript = '';
    _interimTranscript = '';
    _lastErrorCode = '';
    _startedAt = DateTime.now();
    _firstPartialAt = null;
    _lastUpdateAt = null;
    _onTranscript = onTranscript;
    _onSnapshot = onSnapshot;
    _stopCompleter = Completer<String?>();

    final constructor =
        (globalContext['SpeechRecognition'] ??
                globalContext['webkitSpeechRecognition'])
            as JSFunction;
    final recognition = constructor.callAsConstructor<_SpeechRecognition>();
    recognition.lang = language;
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;
    recognition.onresult = _handleResult.toJS;
    recognition.onerror = _handleError.toJS;
    recognition.onend = _handleEnd.toJS;
    _recognition = recognition;
    recognition.start();
  }

  VoiceSttSnapshot snapshot() {
    return VoiceSttSnapshot(
      lastInterimTranscript: _interimTranscript.trim(),
      lastStableTranscript: _finalTranscript.trim(),
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
    void Function(String transcript)? onFinalTranscript,
  }) async {
    if (!enabled) {
      return null;
    }
    final recognition = _recognition;
    final completer = _stopCompleter;
    if (recognition == null || completer == null) {
      return _currentTranscript();
    }
    recognition.stop();
    final stopFuture = completer.future.timeout(
      timeout,
      onTimeout: _currentTranscript,
    );
    if (!waitForFinal) {
      unawaited(
        stopFuture.then((transcript) {
          final current = transcript?.trim() ?? '';
          if (current.isNotEmpty) {
            onFinalTranscript?.call(current);
          }
        }),
      );
      return _currentTranscript();
    }
    return stopFuture;
  }

  Future<void> cancel() async {
    final recognition = _recognition;
    _recognition = null;
    _onTranscript = null;
    _onSnapshot = null;
    if (recognition != null) {
      recognition.onresult = null;
      recognition.onerror = null;
      recognition.onend = null;
      recognition.abort();
    }
    _completeIfNeeded(_currentTranscript());
  }

  void _handleResult(JSAny event) {
    final eventObject = event as JSObject;
    final results = eventObject['results'] as JSObject?;
    if (results == null) {
      return;
    }

    final resultIndex =
        (eventObject['resultIndex'] as JSNumber?)?.toDartInt ?? 0;
    final length = (results['length'] as JSNumber?)?.toDartInt ?? 0;
    final interim = StringBuffer();

    for (var index = resultIndex; index < length; index += 1) {
      final result = results.getProperty<JSObject?>(index.toJS);
      if (result == null) {
        continue;
      }
      final alternative = result.getProperty<JSObject?>(0.toJS);
      final transcript =
          (alternative?['transcript'] as JSString?)?.toDart.trim() ?? '';
      if (transcript.isEmpty) {
        continue;
      }
      final isFinal = (result['isFinal'] as JSBoolean?)?.toDart ?? false;
      if (isFinal) {
        _finalTranscript = '$_finalTranscript $transcript'.trim();
      } else {
        interim.write(' $transcript');
      }
    }

    _interimTranscript = interim.toString().trim();
    final current = _currentTranscript();
    if (current != null) {
      final now = DateTime.now();
      _firstPartialAt ??= now;
      _lastUpdateAt = now;
      _onTranscript?.call(current);
      _onSnapshot?.call(snapshot());
    }
  }

  void _handleError(JSAny event) {
    final eventObject = event as JSObject;
    final code = (eventObject['error'] as JSString?)?.toDart ?? 'unknown';
    _lastErrorCode = code;
    _completeWithError(StateError('브라우저 음성 인식 실패: $code'));
  }

  void _handleEnd(JSAny event) {
    _recognition = null;
    _completeIfNeeded(_currentTranscript());
  }

  String? _currentTranscript() {
    final combined = '$_finalTranscript $_interimTranscript'.trim();
    return combined.isEmpty ? null : combined;
  }

  void _completeIfNeeded(String? transcript) {
    final completer = _stopCompleter;
    _stopCompleter = null;
    _onTranscript = null;
    _onSnapshot = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(transcript);
    }
  }

  void _completeWithError(Object error) {
    final completer = _stopCompleter;
    _stopCompleter = null;
    _onTranscript = null;
    _onSnapshot = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }
}

class BrowserSpeechRecognizer extends DeviceStreamingStt {
  BrowserSpeechRecognizer() : super();

  static const enabled = DeviceStreamingStt.enabled;
}

class PcmDeviceStreamingStt {
  const PcmDeviceStreamingStt();

  static const enabled = false;

  bool get isAvailable => false;

  Future<bool> start({
    String language = 'ko-KR',
    void Function(String transcript)? onTranscript,
    void Function(VoiceSttSnapshot snapshot)? onSnapshot,
    DateTime? startedAt,
  }) async => false;

  void sendAudio(Object chunk) {}

  VoiceSttSnapshot snapshot() {
    return const VoiceSttSnapshot(
      lastInterimTranscript: '',
      lastStableTranscript: '',
      startedAt: null,
      firstAudioSentAt: null,
      firstSpeechAt: null,
      firstPartialAt: null,
      lastUpdateAt: null,
      errorCode: null,
    );
  }

  Future<String?> stop({
    Duration timeout = const Duration(milliseconds: 900),
    void Function(String transcript)? onFinalTranscript,
  }) async => null;

  Future<void> cancel() async {}
}

extension type _SpeechRecognition._(JSObject _) implements JSObject {
  external set lang(String value);
  external set continuous(bool value);
  external set interimResults(bool value);
  external set maxAlternatives(int value);
  external set onresult(JSFunction? value);
  external set onerror(JSFunction? value);
  external set onend(JSFunction? value);
  external void start();
  external void stop();
  external void abort();
}
