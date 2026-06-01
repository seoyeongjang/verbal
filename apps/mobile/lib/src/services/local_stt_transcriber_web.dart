import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class LocalSttTranscriber {
  const LocalSttTranscriber({required this.endpoint});

  final String endpoint;

  Future<String> transcribe({
    required String audioFilePath,
    required int durationMs,
    required String language,
  }) async {
    final audio = await _readBlobUrl(audioFilePath);
    final response = await web.window
        .fetch(
          endpoint.toJS,
          web.RequestInit(
            method: 'POST',
            headers:
                {'Content-Type': 'application/json'}.jsify()!
                    as web.HeadersInit,
            body: jsonEncode({
              'audioBase64': base64Encode(audio.bytes),
              'mimeType': audio.mimeType,
              'filename': audio.filename,
              'language': language,
              'durationMs': durationMs,
            }).toJS,
          ),
        )
        .toDart;
    final body = (await response.text().toDart).toDart;
    if (!response.ok) {
      throw StateError(_errorMessage(body, response.status));
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['transcript'] as String? ?? '').trim();
  }

  Future<_AudioPayload> _readBlobUrl(String audioFilePath) async {
    if (audioFilePath.trim().isEmpty) {
      throw StateError('브라우저 녹음 파일 URL이 비어 있습니다.');
    }
    final response = await web.window.fetch(audioFilePath.toJS).toDart;
    if (!response.ok) {
      throw StateError('브라우저 녹음 파일을 읽을 수 없습니다: HTTP ${response.status}');
    }
    final headerMimeType = response.headers.get('content-type');
    final buffer = (await response.arrayBuffer().toDart).toDart;
    final bytes = buffer.asUint8List();
    final mimeType = _mimeType(bytes, headerMimeType);
    return _AudioPayload(
      bytes: bytes,
      mimeType: mimeType,
      filename: _filename(mimeType),
    );
  }

  String _mimeType(Uint8List bytes, String? headerMimeType) {
    final normalizedHeader = headerMimeType?.trim().toLowerCase();
    if (normalizedHeader != null && normalizedHeader.startsWith('audio/')) {
      return normalizedHeader;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      return 'audio/wav';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'audio/webm';
    }
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'audio/mp4';
    }
    return 'audio/wav';
  }

  String _filename(String mimeType) {
    if (mimeType.contains('webm')) {
      return 'recording.webm';
    }
    if (mimeType.contains('mp4') ||
        mimeType.contains('aac') ||
        mimeType.contains('m4a')) {
      return 'recording.m4a';
    }
    return 'recording.wav';
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

class _AudioPayload {
  const _AudioPayload({
    required this.bytes,
    required this.mimeType,
    required this.filename,
  });

  final Uint8List bytes;
  final String mimeType;
  final String filename;
}
