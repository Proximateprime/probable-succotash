import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

import '../models/session_model.dart';
import '../utils/coverage_geometry.dart';

class MapService {
  static final MapService _instance = MapService._internal();

  factory MapService() {
    return _instance;
  }

  MapService._internal();

  final Logger _logger = Logger();

  Future<bool> requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        return result == LocationPermission.whileInUse ||
            result == LocationPermission.always;
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      _logger.e('Request location permission error: $e');
      return false;
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      _logger.e('Get current position error: $e');
      return null;
    }
  }

  Stream<Position> getPositionStream({
    int intervalSeconds = 3,
    int distanceFilterMeters = 0,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilterMeters,
        // Keep the stream alive continuously; intervalSeconds is handled by
        // upstream filtering and platform cadence defaults.
      ),
    );
  }

  List<List<double>> generateCoveragePolygon(
    List<TrackingPath> paths,
    double swathWidthFeet,
  ) {
    return buildCoveragePolygon([
      for (final path in paths) GeoPoint(path.latitude, path.longitude),
    ], swathWidthFeet);
  }

  double calculateDistanceMiles(List<TrackingPath> paths) {
    return pathDistanceMiles([
      for (final path in paths) GeoPoint(path.latitude, path.longitude),
    ]);
  }
}
