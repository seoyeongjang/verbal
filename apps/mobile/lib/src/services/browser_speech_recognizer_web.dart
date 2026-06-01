import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class BrowserSpeechRecognizer {
  BrowserSpeechRecognizer();

  static const enabled = bool.fromEnvironment('VOICE_MESSENGER_BROWSER_STT');

  _SpeechRecognition? _recognition;
  Completer<String?>? _stopCompleter;
  var _finalTranscript = '';
  var _interimTranscript = '';

  bool get isAvailable =>
      enabled &&
      (globalContext.has('SpeechRecognition') ||
          globalContext.has('webkitSpeechRecognition'));

  Future<void> start({String language = 'ko-KR'}) async {
    if (!enabled) {
      return;
    }
    if (!isAvailable) {
      throw StateError('이 브라우저는 무료 음성 인식을 지원하지 않습니다. Chrome 또는 Edge를 사용하세요.');
    }
    await cancel();

    _finalTranscript = '';
    _interimTranscript = '';
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

  Future<String?> stop() async {
    if (!enabled) {
      return null;
    }
    final recognition = _recognition;
    final completer = _stopCompleter;
    if (recognition == null || completer == null) {
      return _currentTranscript();
    }
    recognition.stop();
    return completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: _currentTranscript,
    );
  }

  Future<void> cancel() async {
    final recognition = _recognition;
    _recognition = null;
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
  }

  void _handleError(JSAny event) {
    final eventObject = event as JSObject;
    final code = (eventObject['error'] as JSString?)?.toDart ?? 'unknown';
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
    if (completer != null && !completer.isCompleted) {
      completer.complete(transcript);
    }
  }

  void _completeWithError(Object error) {
    final completer = _stopCompleter;
    _stopCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }
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
