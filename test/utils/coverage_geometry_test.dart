import 'dart:math' as math;

import 'package:covertrack/utils/coverage_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// One degree of arc on a sphere of radius 6378137 m.
const equatorDegreeMeters = 111319.49079327357;

const _metersPerDegreeLatitude = 111320.0;

void main() {
  group('distanceMeters', () {
    test('is zero when both points are the same', () {
      const point = GeoPoint(40.0, -75.0);
      expect(distanceMeters(point, point), 0);
    });

    test('matches one degree of longitude and latitude on the equator', () {
      expect(
        distanceMeters(const GeoPoint(0, 0), const GeoPoint(0, 1)),
        closeTo(equatorDegreeMeters, 1e-4),
      );
      expect(
        distanceMeters(const GeoPoint(0, 0), const GeoPoint(1, 0)),
        closeTo(equatorDegreeMeters, 1e-4),
      );
    });

    test('measures a short north-south step near 40N', () {
      const start = GeoPoint(40.0, -75.0);
      const end = GeoPoint(40.0 + (0.005 / _metersPerDegreeLatitude), -75.0);
      expect(distanceMeters(start, end), closeTo(0.004999977186841367, 1e-9));
    });
  });

  group('pathDistanceMiles', () {
    test('is zero without a segment', () {
      expect(pathDistanceMiles(const []), 0);
      expect(pathDistanceMiles(const [GeoPoint(40, -75)]), 0);
      expect(
        pathDistanceMiles(const [GeoPoint(40, -75), GeoPoint(40, -75)]),
        0,
      );
    });

    test('converts a one-degree equator segment with 1609.34 m per mile', () {
      expect(
        pathDistanceMiles(const [GeoPoint(0, 0), GeoPoint(0, 1)]),
        closeTo(equatorDegreeMeters / 1609.34, 1e-9),
      );
    });

    test('sums each leg of a bent path', () {
      const legEastMeters = 852.756772883449;
      const legNorthMeters = 111.31949079301413;
      expect(
        pathDistanceMiles(const [
          GeoPoint(40, -75),
          GeoPoint(40, -74.99),
          GeoPoint(40.001, -74.99),
        ]),
        closeTo((legEastMeters + legNorthMeters) / 1609.34, 1e-9),
      );
    });
  });

  group('buildCoveragePolygon', () {
    const swathFeet = 10.0;
    const fullSwathMeters = swathFeet * 0.3048;
    const halfSwathMeters = fullSwathMeters / 2;

    test('returns an empty ring when the path cannot be buffered', () {
      expect(buildCoveragePolygon(const [], swathFeet), isEmpty);
      expect(
        buildCoveragePolygon(const [GeoPoint(40, -75)], swathFeet),
        isEmpty,
      );

      const jitter = GeoPoint(
        40.0 + (0.005 / _metersPerDegreeLatitude),
        -75.0,
      );
      expect(
        buildCoveragePolygon([const GeoPoint(40, -75), jitter], swathFeet),
        isEmpty,
      );
    });

    test('buffers an eastbound path by half the swath on each side', () {
      const start = GeoPoint(40.0, -75.0);
      const end = GeoPoint(40.0, -74.999);
      final polygon = buildCoveragePolygon(const [start, end], swathFeet);

      expect(polygon, hasLength(5));
      expect(polygon.first, polygon.last);

      const latShift = halfSwathMeters / _metersPerDegreeLatitude;
      expect(polygon[0][0], closeTo(start.latitude + latShift, 1e-12));
      expect(polygon[0][1], closeTo(start.longitude, 1e-12));
      expect(polygon[1][0], closeTo(end.latitude + latShift, 1e-12));
      expect(polygon[1][1], closeTo(end.longitude, 1e-12));
      expect(polygon[3][0], closeTo(start.latitude - latShift, 1e-12));
      expect(polygon[3][1], closeTo(start.longitude, 1e-12));

      final width = distanceMeters(
        GeoPoint(polygon[0][0], polygon[0][1]),
        GeoPoint(polygon[3][0], polygon[3][1]),
      );
      expect(width, closeTo(fullSwathMeters, 0.01));
    });

    test('buffers a northbound path to the west and east', () {
      const start = GeoPoint(40.0, -75.0);
      const end = GeoPoint(40.001, -75.0);
      final polygon = buildCoveragePolygon(const [start, end], swathFeet);

      final metersPerDegreeLongitude =
          _metersPerDegreeLatitude * math.cos(start.latitude * math.pi / 180);
      final lonShift = halfSwathMeters / metersPerDegreeLongitude;

      expect(polygon, hasLength(5));
      expect(polygon.first, polygon.last);
      expect(polygon[0][0], closeTo(start.latitude, 1e-12));
      expect(polygon[0][1], closeTo(start.longitude - lonShift, 1e-12));
      expect(polygon[3][0], closeTo(start.latitude, 1e-12));
      expect(polygon[3][1], closeTo(start.longitude + lonShift, 1e-12));
    });

    test('offsets the ends of a bent path from their adjacent segments', () {
      const start = GeoPoint(40.0, -75.0);
      const corner = GeoPoint(40.0, -74.999);
      const end = GeoPoint(40.001, -74.999);
      final polygon = buildCoveragePolygon(const [
        start,
        corner,
        end,
      ], swathFeet);

      expect(polygon, hasLength(7));
      expect(polygon.first, polygon.last);
      for (final vertex in polygon) {
        expect(vertex[0].isFinite, isTrue);
        expect(vertex[1].isFinite, isTrue);
      }

      const latShift = halfSwathMeters / _metersPerDegreeLatitude;
      expect(polygon[0][0], closeTo(start.latitude + latShift, 1e-12));
      expect(polygon[0][1], closeTo(start.longitude, 1e-12));

      final metersPerDegreeLongitude =
          _metersPerDegreeLatitude * math.cos(end.latitude * math.pi / 180);
      final lonShift = halfSwathMeters / metersPerDegreeLongitude;
      expect(polygon[2][0], closeTo(end.latitude, 1e-12));
      expect(polygon[2][1], closeTo(end.longitude - lonShift, 1e-12));
    });

    test('keeps the turnaround point when the path doubles back', () {
      const start = GeoPoint(40.0, -75.0);
      const turn = GeoPoint(40.0, -74.999);
      final polygon = buildCoveragePolygon(const [
        start,
        turn,
        start,
      ], swathFeet);

      expect(polygon, hasLength(7));
      expect(polygon.first, polygon.last);
    });

    test('uses a 0.5 m half-width floor for a narrow swath', () {
      final polygon = buildCoveragePolygon(const [
        GeoPoint(40.0, -75.0),
        GeoPoint(40.0, -74.999),
      ], 0.1);

      const floorHalfMeters = 0.5;
      expect(
        polygon[0][0] - 40.0,
        closeTo(floorHalfMeters / _metersPerDegreeLatitude, 1e-12),
      );
      expect(
        40.0 - polygon[3][0],
        closeTo(floorHalfMeters / _metersPerDegreeLatitude, 1e-12),
      );
      expect(
        distanceMeters(
          GeoPoint(polygon[0][0], polygon[0][1]),
          GeoPoint(polygon[3][0], polygon[3][1]),
        ),
        closeTo(1.0, 0.01),
      );
    });
  });

  group('expandRingOutwardMeters', () {
    test('returns the same list when the buffer is not positive', () {
      final ring = _squareRing();
      expect(identical(expandRingOutwardMeters(ring, 0), ring), isTrue);
      expect(identical(expandRingOutwardMeters(ring, -2), ring), isTrue);
    });

    test('keeps an empty ring empty', () {
      expect(expandRingOutwardMeters(const [], 4), isEmpty);
    });

    test('moves each vertex farther from the centroid and closes the ring', () {
      const latitude = 39.5;
      const longitude = -104.9;
      const radiusMeters = 40.0;
      const bufferMeters = 10.0;
      final buffered = expandRingOutwardMeters(
        _squareRing(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters,
        ),
        bufferMeters,
      );

      expect(buffered, hasLength(5));
      expect(buffered.first.latitude, buffered.last.latitude);
      expect(buffered.first.longitude, buffered.last.longitude);
      for (final point in buffered.take(4)) {
        expect(
          _radialMeters(point, latitude, longitude),
          closeTo(radiusMeters + bufferMeters, 1e-6),
        );
      }
    });

    test('drops an exact closing vertex before expanding', () {
      final buffered = expandRingOutwardMeters(_squareRing(close: true), 10);
      expect(buffered, hasLength(5));
    });

    test(
      'closing tolerance decides whether a near-duplicate vertex counts',
      () {
        final ring = _squareRing(close: true, closeSlopDegrees: 1e-9);

        expect(expandRingOutwardMeters(ring, 10), hasLength(5));
        expect(
          expandRingOutwardMeters(ring, 10, closingToleranceDegrees: 1e-10),
          hasLength(6),
        );
      },
    );

    test('leaves a vertex that sits on the centroid unmoved', () {
      const latitude = 39.5;
      const longitude = -104.9;
      const dLat = 40 / _metersPerDegreeLatitude;
      final buffered = expandRingOutwardMeters(const [
        GeoPoint(latitude, longitude),
        GeoPoint(latitude + dLat, longitude),
        GeoPoint(latitude - dLat, longitude),
      ], 10);

      expect(buffered, hasLength(4));
      expect(buffered.first.latitude, latitude);
      expect(buffered.first.longitude, longitude);
      expect(
        (buffered[1].latitude - latitude) * _metersPerDegreeLatitude,
        closeTo(50, 1e-6),
      );
      expect(
        (buffered[2].latitude - latitude) * _metersPerDegreeLatitude,
        closeTo(-50, 1e-6),
      );
    });
  });
}

List<GeoPoint> _squareRing({
  double latitude = 39.5,
  double longitude = -104.9,
  double radiusMeters = 40,
  bool close = false,
  double closeSlopDegrees = 0,
}) {
  final cosLat = math.cos(latitude * math.pi / 180);
  final dLat = radiusMeters / _metersPerDegreeLatitude;
  final dLon = radiusMeters / (_metersPerDegreeLatitude * cosLat);
  final ring = [
    GeoPoint(latitude + dLat, longitude),
    GeoPoint(latitude, longitude + dLon),
    GeoPoint(latitude - dLat, longitude),
    GeoPoint(latitude, longitude - dLon),
  ];
  if (close) {
    ring.add(
      GeoPoint(
        ring.first.latitude + closeSlopDegrees,
        ring.first.longitude + closeSlopDegrees,
      ),
    );
  }
  return ring;
}

double _radialMeters(GeoPoint point, double latitude, double longitude) {
  final cosLat = math.cos(latitude * math.pi / 180);
  final dy = (point.latitude - latitude) * _metersPerDegreeLatitude;
  final dx = (point.longitude - longitude) * _metersPerDegreeLatitude * cosLat;
  return math.sqrt((dx * dx) + (dy * dy));
}
