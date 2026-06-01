typedef LocationPickHandler = Future<PickedLocation?> Function();

class PickedLocation {
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  String get mapUrl => 'https://maps.google.com/?q=$latitude,$longitude';

  String get label {
    final accuracy = accuracyMeters;
    if (accuracy == null || accuracy <= 0) {
      return 'Current location';
    }
    return 'Current location (${accuracy.round()}m)';
  }
}
