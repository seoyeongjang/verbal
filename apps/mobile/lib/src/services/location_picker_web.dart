import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'location_picker_types.dart';

Future<PickedLocation?> pickCurrentLocation() async {
  final completer = Completer<PickedLocation?>();

  void complete(PickedLocation? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void fail(web.GeolocationPositionError error) {
    if (!completer.isCompleted) {
      completer.completeError(StateError(error.message));
    }
  }

  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      final coords = position.coords;
      complete(
        PickedLocation(
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracyMeters: coords.accuracy,
        ),
      );
    }).toJS,
    fail.toJS,
    web.PositionOptions(
      enableHighAccuracy: true,
      timeout: 12000,
      maximumAge: 30000,
    ),
  );

  return completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw StateError('Location request timed out.'),
  );
}
