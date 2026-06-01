Future<Uri?> localAudioUri(String? audioPath) async {
  if (audioPath == null || audioPath.isEmpty) {
    return null;
  }
  if (audioPath.startsWith('blob:') ||
      audioPath.startsWith('data:') ||
      audioPath.startsWith('http://') ||
      audioPath.startsWith('https://')) {
    return Uri.tryParse(audioPath);
  }
  return null;
}
