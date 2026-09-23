import 'package:covertrack/models/session_model.dart';
import 'package:covertrack/services/map_service.dart';
import 'package:covertrack/utils/coverage_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapService coverage math', () {
    final service = MapService();

    test('delegates polygon and distance to the pure helpers', () {
      final paths = [
        _path(40, -75),
        _path(40, -74.999),
        _path(40.001, -74.999),
      ];
      final points = [
        for (final path in paths) GeoPoint(path.latitude, path.longitude),
      ];

      expect(
        service.generateCoveragePolygon(paths, 8),
        buildCoveragePolygon(points, 8),
      );
      expect(service.calculateDistanceMiles(paths), pathDistanceMiles(points));
    });

    test('returns an empty polygon and zero miles without a segment', () {
      expect(service.generateCoveragePolygon(const [], 5), isEmpty);
      expect(service.calculateDistanceMiles(const []), 0);
      expect(service.generateCoveragePolygon([_path(40, -75)], 5), isEmpty);
      expect(service.calculateDistanceMiles([_path(40, -75)]), 0);
    });
  });
}

TrackingPath _path(double latitude, double longitude) {
  return TrackingPath(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2024, 6, 1),
  );
}
