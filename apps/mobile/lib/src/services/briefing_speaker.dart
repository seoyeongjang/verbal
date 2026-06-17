import 'package:flutter/services.dart';

class BriefingSpeaker {
  BriefingSpeaker._();

  static const _channel = MethodChannel('verbal/briefing_tts');

  static Future<bool> speak(String text, {String language = 'ko-KR'}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('speak', {
        'text': normalized,
        'language': language,
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
