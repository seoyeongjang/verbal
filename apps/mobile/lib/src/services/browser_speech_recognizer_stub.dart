class BrowserSpeechRecognizer {
  const BrowserSpeechRecognizer();

  static const enabled = bool.fromEnvironment('VOICE_MESSENGER_BROWSER_STT');

  bool get isAvailable => false;

  Future<void> start({String language = 'ko-KR'}) async {}

  Future<String?> stop() async => null;

  Future<void> cancel() async {}
}
