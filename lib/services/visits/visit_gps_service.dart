import 'package:geolocator/geolocator.dart';
import 'package:sello/shared/models/customer_visit.dart';

/// Captures a single GPS reading for Start / Complete Visit.
///
/// Never tracks continuously. Failures / slow fixes return null so visits
/// are never blocked. Web browsers often ignore [LocationSettings.timeLimit],
/// so we also wrap with Dart [Future.timeout].
abstract final class VisitGpsService {
  static Future<VisitGpsPoint?> captureOnce({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _capture(timeout: timeout).timeout(
        timeout,
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Prefer this on Complete Visit — GPS is nice-to-have, not worth stalling.
  static Future<VisitGpsPoint?> captureOnceQuick() {
    return captureOnce(timeout: const Duration(seconds: 2));
  }

  static Future<VisitGpsPoint?> _capture({required Duration timeout}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: timeout,
      ),
    );

    return VisitGpsPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}
