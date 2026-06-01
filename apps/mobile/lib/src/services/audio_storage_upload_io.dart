import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

Future<void> uploadAudioFile({
  required Reference ref,
  required String audioFilePath,
  required SettableMetadata metadata,
}) async {
  await ref.putFile(File(audioFilePath), metadata);
}
