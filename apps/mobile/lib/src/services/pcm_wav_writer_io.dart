import 'dart:io';
import 'dart:typed_data';

Future<void> writePcm16WavFile({
  required String path,
  required Uint8List pcmBytes,
  int sampleRate = 16000,
  int channels = 1,
}) async {
  await File(path).writeAsBytes(
    buildPcm16WavBytes(
      pcmBytes: pcmBytes,
      sampleRate: sampleRate,
      channels: channels,
    ),
    flush: true,
  );
}

Uint8List buildPcm16WavBytes({
  required Uint8List pcmBytes,
  int sampleRate = 16000,
  int channels = 1,
}) {
  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;
  final dataSize = pcmBytes.length;
  final fileSize = 36 + dataSize;
  final bytes = BytesBuilder(copy: false)
    ..add(_ascii('RIFF'))
    ..add(_u32(fileSize))
    ..add(_ascii('WAVE'))
    ..add(_ascii('fmt '))
    ..add(_u32(16))
    ..add(_u16(1))
    ..add(_u16(channels))
    ..add(_u32(sampleRate))
    ..add(_u32(byteRate))
    ..add(_u16(blockAlign))
    ..add(_u16(16))
    ..add(_ascii('data'))
    ..add(_u32(dataSize))
    ..add(pcmBytes);
  return bytes.toBytes();
}

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

Uint8List _u16(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

Uint8List _u32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}
