import 'package:flutter/foundation.dart';

import 'messenger_backend.dart';

class DeepgramLiveSnapshot {
  const DeepgramLiveSnapshot({
    required this.lastInterimTranscript,
    required this.lastStableTranscript,
    required this.startedAt,
    required this.firstAudioSentAt,
    required this.firstSpeechAt,
    required this.firstPartialAt,
    required this.lastUpdateAt,
    required this.errorCode,
  });

  final String lastInterimTranscript;
  final String lastStableTranscript;
  final DateTime? startedAt;
  final DateTime? firstAudioSentAt;
  final DateTime? firstSpeechAt;
  final DateTime? firstPartialAt;
  final DateTime? lastUpdateAt;
  final String? errorCode;

  String get transcript {
    final stable = lastStableTranscript.trim();
    final interim = lastInterimTranscript.trim();
    if (stable.isEmpty) {
      return interim;
    }
    if (interim.isEmpty) {
      return stable;
    }
    final normalizedStable = stable.replaceAll(RegExp(r'\s+'), '');
    final normalizedInterim = interim.replaceAll(RegExp(r'\s+'), '');
    if (normalizedStable.contains(normalizedInterim)) {
      return stable;
    }
    return '$stable $interim'.trim();
  }
}

class DeepgramStreamingStt {
  DeepgramStreamingStt({
    required this.tokenProvider,
    this.providerLabel = 'deepgram_streaming',
  });

  static bool get enabled => false;

  final Future<DeepgramStreamingToken?> Function() tokenProvider;
  final String providerLabel;

  bool get isReady => false;

  Future<bool> start({
    ValueChanged<String>? onTranscript,
    ValueChanged<DeepgramLiveSnapshot>? onSnapshot,
    DateTime? startedAt,
  }) async {
    return false;
  }

  bool attachSession({
    required DateTime startedAt,
    ValueChanged<String>? onTranscript,
    ValueChanged<DeepgramLiveSnapshot>? onSnapshot,
  }) {
    return false;
  }

  void sendAudio(Uint8List chunk) {}

  void markSpeechDetected(DateTime detectedAt) {}

  void sendKeepAlive() {}

  Future<String?> stop({
    Duration timeout = const Duration(milliseconds: 400),
    ValueChanged<String>? onFinalTranscript,
  }) async {
    return null;
  }

  Future<void> cancel() async {}
}
