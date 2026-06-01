class LocalSttTranscriber {
  const LocalSttTranscriber({required this.endpoint});

  final String endpoint;

  Future<String> transcribe({
    required String audioFilePath,
    required int durationMs,
    required String language,
  }) {
    throw UnsupportedError('이 플랫폼에서는 로컬 STT 테스트 모드를 지원하지 않습니다.');
  }
}
