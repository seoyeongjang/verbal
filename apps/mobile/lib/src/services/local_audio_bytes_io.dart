import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalAudioBytesForInlineStt(
  String path, {
  required int maxBytes,
}) async {
  if (path.trim().isEmpty) {
    return null;
  }
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  final length = await file.length();
  if (length <= 0 || length > maxBytes) {
    return null;
  }
  return file.readAsBytes();
}
