import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'location_picker_types.dart';

const _channel = MethodChannel('verbal/location');

Future<PickedLocation?> pickCurrentLocation() async {
  final status = await Permission.locationWhenInUse.request();
  if (!status.isGranted) {
    throw StateError('Location permission is required.');
  }
  final result = await _channel.invokeMapMethod<String, Object?>(
    'currentLocation',
  );
  if (result == null) {
    return null;
  }
  final latitude = (result['latitude'] as num?)?.toDouble();
  final longitude = (result['longitude'] as num?)?.toDouble();
  if (latitude == null || longitude == null) {
    throw StateError('Location result was invalid.');
  }
  return PickedLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: (result['accuracy'] as num?)?.toDouble(),
  );
}
