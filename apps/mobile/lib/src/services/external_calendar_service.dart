import 'package:flutter/services.dart';

import '../models/messenger_models.dart';

enum ExternalCalendarTarget { google, apple }

class ExternalCalendarService {
  ExternalCalendarService._();

  static const _channel = MethodChannel('voice_messenger/external_calendar');

  static Future<bool> addEvent(
    CalendarEvent event, {
    required ExternalCalendarTarget target,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('addEvent', {
        'target': target.name,
        'title': event.title,
        'startAtMillis': event.startAt.millisecondsSinceEpoch,
        'endAtMillis': event.endAt.millisecondsSinceEpoch,
        'description': _descriptionFor(event),
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static String _descriptionFor(CalendarEvent event) {
    final details = event.details.trim();
    if (details.isNotEmpty) {
      return details;
    }
    final transcript = event.transcript.trim();
    if (transcript.isNotEmpty) {
      return transcript;
    }
    return 'Voice Messenger 일정';
  }
}
