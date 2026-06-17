import 'dart:typed_data';

Future<void> writePcm16WavFile({
  required String path,
  required Uint8List pcmBytes,
  int sampleRate = 16000,
  int channels = 1,
}) {
  throw UnsupportedError('PCM WAV writing is only available on IO platforms.');
}

Uint8List buildPcm16WavBytes({
  required Uint8List pcmBytes,
  int sampleRate = 16000,
  int channels = 1,
}) {
  throw UnsupportedError('PCM WAV writing is only available on IO platforms.');
}
