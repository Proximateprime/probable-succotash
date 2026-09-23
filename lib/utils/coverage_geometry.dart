import 'dart:math' as math;

/// WGS84 coordinate in degrees. Pure value type for coverage math.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Great-circle distance in meters.
///
/// Spherical radius is 6378137 m, the same value Geolocator.distanceBetween
/// uses, so path length does not depend on the GPS plugin.
double distanceMeters(GeoPoint start, GeoPoint end) {
  const earthRadiusMeters = 6378137.0;
  final dLat = _toRadians(end.latitude - start.latitude);
  final dLon = _toRadians(end.longitude - start.longitude);
  final sinHalfLat = math.sin(dLat / 2);
  final sinHalfLon = math.sin(dLon / 2);
  final a =
      sinHalfLat * sinHalfLat +
      sinHalfLon *
          sinHalfLon *
          math.cos(_toRadians(start.latitude)) *
          math.cos(_toRadians(end.latitude));
  final c = 2 * math.asin(math.sqrt(a));
  return earthRadiusMeters * c;
}

/// Sum of segment lengths in miles. Returns 0 when [points] has fewer than two.
double pathDistanceMiles(List<GeoPoint> points) {
  if (points.length < 2) return 0.0;

  var totalMeters = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    totalMeters += distanceMeters(points[i], points[i + 1]);
  }
  return totalMeters / 1609.34;
}

/// Closed swath polygon around [points]. Each vertex is `[latitude, longitude]`.
///
/// Half of [swathWidthFeet] is offset to each side of the path. Half-width is
/// at least 0.5 m. Segments shorter than 1 cm are skipped. Returns an empty
/// list when nothing is long enough to buffer.
List<List<double>> buildCoveragePolygon(
  List<GeoPoint> points,
  double swathWidthFeet,
) {
  if (points.length < 2) return [];

  final swathHalfMeters = math.max(0.5, (swathWidthFeet * 0.3048) / 2);

  final leftSide = <List<double>>[];
  final rightSide = <List<double>>[];

  for (var i = 0; i < points.length; i++) {
    final current = points[i];
    final previous = i > 0 ? points[i - 1] : current;
    final next = i < points.length - 1 ? points[i + 1] : current;

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

    if (direction.$3 < 0.01 && i < points.length - 1) {
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

/// Expands [ring] outward from its centroid by [bufferMeters].
///
/// A repeated closing vertex within [closingToleranceDegrees] is dropped
/// before scaling, then the ring is closed again. Non-positive buffers and
/// empty rings are returned unchanged.
List<GeoPoint> expandRingOutwardMeters(
  List<GeoPoint> ring,
  double bufferMeters, {
  double closingToleranceDegrees = 1e-8,
}) {
  if (ring.isEmpty || bufferMeters <= 0) return ring;

  final closed =
      ring.length >= 2 &&
      (ring.first.latitude - ring.last.latitude).abs() <
          closingToleranceDegrees &&
      (ring.first.longitude - ring.last.longitude).abs() <
          closingToleranceDegrees;
  final pts = closed ? ring.sublist(0, ring.length - 1) : ring;
  if (pts.isEmpty) return ring;

  const metersPerDegLat = 111320.0;
  final centLat =
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final centLng =
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  final cosLat = math.cos(centLat * math.pi / 180);
  final expanded = pts.map((p) {
    final dLatM = (p.latitude - centLat) * metersPerDegLat;
    final dLngM = (p.longitude - centLng) * metersPerDegLat * cosLat;
    final dist = math.sqrt(dLatM * dLatM + dLngM * dLngM);
    if (dist < 1e-6) return p;
    final scale = (dist + bufferMeters) / dist;
    return GeoPoint(
      centLat + (p.latitude - centLat) * scale,
      centLng + (p.longitude - centLng) * scale,
    );
  }).toList();
  expanded.add(expanded.first);
  return expanded;
}

double _toRadians(double degrees) => degrees * math.pi / 180;

(double, double, double) _segmentVectorMeters(
  double fromLat,
  double fromLon,
  double toLat,
  double toLon,
  double referenceLat,
) {
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = math.max(
    1e-6,
    111320.0 * math.cos(referenceLat * math.pi / 180),
  );
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
  final metersPerDegLng = math.max(
    1e-6,
    111320.0 * math.cos(lat * math.pi / 180),
  );
  return [
    lat + (dyMeters / metersPerDegLat),
    lon + (dxMeters / metersPerDegLng),
  ];
}
