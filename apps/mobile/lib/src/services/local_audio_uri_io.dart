import 'dart:io';

Future<Uri?> localAudioUri(String? audioPath) async {
  if (audioPath == null || audioPath.isEmpty) {
    return null;
  }
  if (audioPath.startsWith('file:')) {
    return Uri.tryParse(audioPath);
  }
  final file = File(audioPath);
  if (await file.exists()) {
    return file.uri;
  }
  return null;
}
