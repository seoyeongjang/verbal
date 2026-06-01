import 'location_picker_method_channel.dart'
    if (dart.library.html) 'location_picker_web.dart'
    as platform;
import 'location_picker_types.dart';

export 'location_picker_types.dart';

class LocationPicker {
  const LocationPicker._();

  static LocationPickHandler? debugPick;

  static Future<PickedLocation?> pickCurrent() {
    final override = debugPick;
    if (override != null) {
      return override();
    }
    return platform.pickCurrentLocation();
  }
}
