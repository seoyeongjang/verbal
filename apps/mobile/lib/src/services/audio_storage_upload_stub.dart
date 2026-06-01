import 'package:firebase_storage/firebase_storage.dart';

Future<void> uploadAudioFile({
  required Reference ref,
  required String audioFilePath,
  required SettableMetadata metadata,
}) {
  throw UnsupportedError(
    '웹/데스크톱 Firebase 음성 업로드는 아직 지원하지 않습니다. 로컬 테스트는 데모 모드를 사용하세요.',
  );
}
