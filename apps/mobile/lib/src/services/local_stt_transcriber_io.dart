import 'dart:convert';
import 'dart:io';

class LocalSttTranscriber {
  const LocalSttTranscriber({required this.endpoint});

  final String endpoint;

  Future<String> transcribe({
    required String audioFilePath,
    required int durationMs,
    required String language,
  }) async {
    final bytes = await File(audioFilePath).readAsBytes();
    final uri = Uri.parse(endpoint);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'audioBase64': base64Encode(bytes),
          'mimeType': _mimeType(audioFilePath),
          'filename': _filename(audioFilePath),
          'language': language,
          'durationMs': durationMs,
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_errorMessage(body, response.statusCode));
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      return (data['transcript'] as String? ?? '').trim();
    } finally {
      client.close(force: true);
    }
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.webm')) {
      return 'audio/webm';
    }
    return 'audio/mp4';
  }

  String _filename(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.isEmpty ? 'recording.wav' : name;
  }

  String _errorMessage(String body, int statusCode) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['error'] as String? ?? '로컬 STT 요청 실패: HTTP $statusCode';
    } catch (_) {
      return '로컬 STT 요청 실패: HTTP $statusCode';
    }
  }
}
