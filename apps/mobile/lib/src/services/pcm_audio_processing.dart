import 'dart:math' as math;
import 'dart:typed_data';

class Pcm16AudioLevel {
  const Pcm16AudioLevel({required this.rms, required this.peak});

  final double rms;
  final int peak;

  bool get looksLikeSpeech => rms >= 45 && peak >= 360;
}

Pcm16AudioLevel measurePcm16AudioLevel(Uint8List pcmBytes) {
  if (pcmBytes.length < 2) {
    return const Pcm16AudioLevel(rms: 0, peak: 0);
  }
  final byteData = ByteData.sublistView(pcmBytes);
  final sampleCount = pcmBytes.length ~/ 2;
  if (sampleCount == 0) {
    return const Pcm16AudioLevel(rms: 0, peak: 0);
  }
  var sumSquares = 0.0;
  var peak = 0;
  for (var i = 0; i < sampleCount; i += 1) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    final absSample = sample.abs();
    if (absSample > peak) {
      peak = absSample;
    }
    sumSquares += sample * sample;
  }
  return Pcm16AudioLevel(
    rms: math.sqrt(sumSquares / sampleCount),
    peak: peak,
  );
}

Uint8List normalizePcm16ForSpeech(
  Uint8List pcmBytes, {
  int targetRms = 2800,
  int minRms = 80,
  int peakLimit = 30000,
  double maxGain = 10,
}) {
  if (pcmBytes.length < 2) {
    return pcmBytes;
  }
  final byteData = ByteData.sublistView(pcmBytes);
  final sampleCount = pcmBytes.length ~/ 2;
  var sumSquares = 0.0;
  var peak = 0;
  for (var i = 0; i < sampleCount; i += 1) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    final absSample = sample.abs();
    if (absSample > peak) {
      peak = absSample;
    }
    sumSquares += sample * sample;
  }
  if (sampleCount == 0 || peak == 0) {
    return pcmBytes;
  }
  final rms = math.sqrt(sumSquares / sampleCount);
  if (rms < minRms || rms >= targetRms) {
    return pcmBytes;
  }
  final rmsGain = targetRms / rms;
  final peakGain = peakLimit / peak;
  final gain = math.min(math.min(rmsGain, peakGain), maxGain);
  if (gain <= 1.05) {
    return pcmBytes;
  }

  final output = Uint8List.fromList(pcmBytes);
  final outputData = ByteData.sublistView(output);
  for (var i = 0; i < sampleCount; i += 1) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    final normalized = (sample * gain).round().clamp(-32768, 32767).toInt();
    outputData.setInt16(i * 2, normalized, Endian.little);
  }
  return output;
}
