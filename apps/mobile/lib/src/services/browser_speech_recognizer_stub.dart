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

  int? get recordStartToFirstPartialMs => null;

  int? get recordStartToFirstAudioSentMs => null;

  int? get recordStartToFirstSpeechMs => null;

  int? get firstAudioSentToFirstPartialMs => null;

  int? get speechStartToFirstPartialMs => null;

  int? get recordStartToLastTranscriptMs => null;
}

class DeviceStreamingStt {
  const DeviceStreamingStt();

  static const enabled = bool.fromEnvironment('VERBAL_BROWSER_STT');

  bool get isAvailable => false;

  Future<void> start({
    String language = 'ko-KR',
    void Function(String transcript)? onTranscript,
    void Function(VoiceSttSnapshot snapshot)? onSnapshot,
  }) async {}

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
    bool waitForFinal = true,
    Duration timeout = const Duration(seconds: 3),
    void Function(String transcript)? onFinalTranscript,
  }) async => null;

  Future<void> cancel() async {}
}

class BrowserSpeechRecognizer extends DeviceStreamingStt {
  const BrowserSpeechRecognizer() : super();

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
