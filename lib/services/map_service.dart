import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;
import '../models/session_model.dart';

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
        timeLimit: Duration(seconds: intervalSeconds),
      ),
    );
  }

  List<List<double>> generateCoveragePolygon(
    List<TrackingPath> paths,
    double swathWidthFeet,
  ) {
    if (paths.length < 2) return [];

    final swathHalfMeters = math.max(0.5, (swathWidthFeet * 0.3048) / 2);

    final leftSide = <List<double>>[];
    final rightSide = <List<double>>[];

    for (int i = 0; i < paths.length; i++) {
      final current = paths[i];
      final previous = i > 0 ? paths[i - 1] : current;
      final next = i < paths.length - 1 ? paths[i + 1] : current;

      var direction = _segmentVectorMeters(
        previous.latitude,
        previous.longitude,
        next.latitude,
        next.longitude,
        current.latitude,
      );

      if (direction.$3 < 0.01 && i > 0) {
        direction = _segmentVectorMeters(
          previous.latitude,
          previous.longitude,
          current.latitude,
          current.longitude,
          current.latitude,
        );
      }

      if (direction.$3 < 0.01 && i < paths.length - 1) {
        direction = _segmentVectorMeters(
          current.latitude,
          current.longitude,
          next.latitude,
          next.longitude,
          current.latitude,
        );
      }

      if (direction.$3 < 0.01) {
        continue;
      }

      final unitX = direction.$1 / direction.$3;
      final unitY = direction.$2 / direction.$3;
      final leftX = -unitY * swathHalfMeters;
      final leftY = unitX * swathHalfMeters;
      final rightX = unitY * swathHalfMeters;
      final rightY = -unitX * swathHalfMeters;

      final leftPoint = _offsetPointMeters(
        current.latitude,
        current.longitude,
        leftX,
        leftY,
      );
      final rightPoint = _offsetPointMeters(
        current.latitude,
        current.longitude,
        rightX,
        rightY,
      );

      leftSide.add([leftPoint[0], leftPoint[1]]);
      rightSide.add([rightPoint[0], rightPoint[1]]);
    }

    final polygon = [...leftSide, ...rightSide.reversed];
    if (polygon.isNotEmpty) {
      polygon.add(polygon.first);
    }

    return polygon;
  }

  double calculateDistanceMiles(List<TrackingPath> paths) {
    if (paths.length < 2) return 0.0;

    double totalMeters = 0.0;
    for (int i = 0; i < paths.length - 1; i++) {
      final dist = Geolocator.distanceBetween(
        paths[i].latitude,
        paths[i].longitude,
        paths[i + 1].latitude,
        paths[i + 1].longitude,
      );
      totalMeters += dist;
    }

    return totalMeters / 1609.34;
  }

  (double, double, double) _segmentVectorMeters(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
    double referenceLat,
  ) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng =
        math.max(1e-6, 111320.0 * math.cos(referenceLat * math.pi / 180));
    final dx = (toLon - fromLon) * metersPerDegLng;
    final dy = (toLat - fromLat) * metersPerDegLat;
    final length = math.sqrt((dx * dx) + (dy * dy));
    return (dx, dy, length);
  }

  List<double> _offsetPointMeters(
    double lat,
    double lon,
    double dxMeters,
    double dyMeters,
  ) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng =
        math.max(1e-6, 111320.0 * math.cos(lat * math.pi / 180));
    return [
      lat + (dyMeters / metersPerDegLat),
      lon + (dxMeters / metersPerDegLng),
    ];
  }
}
