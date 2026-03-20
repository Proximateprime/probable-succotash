import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

class RecommendedPathGenerationResult {
  final Map<String, dynamic> geoJson;
  final List<List<LatLng>> previewSegments;
  final bool usedFallback;

  const RecommendedPathGenerationResult({
    required this.geoJson,
    required this.previewSegments,
    required this.usedFallback,
  });
}

class RecommendedPathService {
  static const double defaultSwathWidthFeet = 15.0;

  RecommendedPathGenerationResult generate({
    required Map<String, dynamic> boundaryGeoJson,
    required List<Map<String, dynamic>> exclusionZones,
    required double swathWidthFeet,
  }) {
    try {
      final complex = _generateComplex(
        boundaryGeoJson: boundaryGeoJson,
        exclusionZones: exclusionZones,
        swathWidthFeet: swathWidthFeet,
      );

      if (complex.previewSegments.isNotEmpty) {
        return complex;
      }

      throw Exception('No segments produced by complex mode');
    } catch (_) {
      return _generateFallback(
        boundaryGeoJson: boundaryGeoJson,
        exclusionZones: exclusionZones,
        swathWidthFeet: swathWidthFeet,
      );
    }
  }

  RecommendedPathGenerationResult _generateComplex({
    required Map<String, dynamic> boundaryGeoJson,
    required List<Map<String, dynamic>> exclusionZones,
    required double swathWidthFeet,
  }) {
    final boundary = _asPolygon(boundaryGeoJson);
    final boundaryLine = polygonToLine(boundary);
    final exclusions = _extractExclusionPolygons(exclusionZones);

    final areaBounds = bbox(boundary, recompute: true);
    final minLng = areaBounds[0]!.toDouble();
    final minLat = areaBounds[1]!.toDouble();
    final maxLng = areaBounds[2]!.toDouble();
    final maxLat = areaBounds[3]!.toDouble();

    final spacingMeters =
        (swathWidthFeet <= 0 ? defaultSwathWidthFeet : swathWidthFeet) * 0.3048;
    final double spacingDegrees =
        math.max(lengthToDegrees(spacingMeters, Unit.meters).toDouble(), 1e-6);

    final padLng = math.max((maxLng - minLng) * 0.02, 0.0002);
    final totalRows = ((maxLat - minLat) / spacingDegrees).ceil() + 1;

    var leftToRight = true;
    final outputSegments = <List<Position>>[];

    for (var row = 0; row < totalRows; row++) {
      final lat = minLat + (row * spacingDegrees);
      if (lat > maxLat + 1e-9) {
        break;
      }

      final rowStart = Position.of([
        leftToRight ? minLng - padLng : maxLng + padLng,
        lat,
      ]);
      final rowEnd = Position.of([
        leftToRight ? maxLng + padLng : minLng - padLng,
        lat,
      ]);
      final scanLine = LineString(coordinates: [rowStart, rowEnd]);

      final intersections = lineIntersect(scanLine, boundaryLine)
          .features
          .map((f) => f.geometry?.coordinates)
          .whereType<Position>()
          .toList(growable: false);

      if (intersections.length < 2) {
        leftToRight = !leftToRight;
        continue;
      }

      final ordered = List<Position>.from(intersections)
        ..sort((a, b) => a.lng.compareTo(b.lng));

      for (var i = 0; i < ordered.length - 1; i += 2) {
        var a = ordered[i];
        var b = ordered[i + 1];
        if (!leftToRight) {
          final temp = a;
          a = b;
          b = temp;
        }

        final midpoint = _lerpPosition(a, b, 0.5);
        if (!booleanPointInPolygon(midpoint, boundary)) {
          continue;
        }

        final clippedPieces = _subtractExclusions(a, b, exclusions);
        for (final piece in clippedPieces) {
          final start = piece[0];
          final end = piece[1];
          if (_distanceSq(start, end) < 1e-16) {
            continue;
          }
          outputSegments.add([start, end]);
        }
      }

      leftToRight = !leftToRight;
    }

    return _toResult(outputSegments, usedFallback: false);
  }

  List<List<Position>> _subtractExclusions(
    Position start,
    Position end,
    List<Polygon> exclusions,
  ) {
    var pieces = <List<Position>>[
      [start, end]
    ];

    for (final exclusion in exclusions) {
      if (pieces.isEmpty) {
        break;
      }

      final next = <List<Position>>[];
      for (final piece in pieces) {
        next.addAll(_subtractOneExclusion(piece[0], piece[1], exclusion));
      }
      pieces = next;
    }

    return pieces;
  }

  List<List<Position>> _subtractOneExclusion(
    Position start,
    Position end,
    Polygon exclusion,
  ) {
    final line = LineString(coordinates: [start, end]);
    final exclusionLine = polygonToLine(exclusion);
    final intersections = lineIntersect(line, exclusionLine)
        .features
        .map((f) => f.geometry?.coordinates)
        .whereType<Position>()
        .toList(growable: false);

    final splitTs = <double>{0.0, 1.0};
    for (final point in intersections) {
      splitTs.add(_projectT(start, end, point));
    }

    final sorted = splitTs.toList(growable: false)..sort();
    final kept = <List<Position>>[];

    for (var i = 0; i < sorted.length - 1; i++) {
      final t0 = sorted[i];
      final t1 = sorted[i + 1];
      if (t1 - t0 < 1e-6) {
        continue;
      }

      final mid = _lerpPosition(start, end, (t0 + t1) / 2);
      final insideExclusion = booleanPointInPolygon(mid, exclusion);
      if (!insideExclusion) {
        kept.add([
          _lerpPosition(start, end, t0),
          _lerpPosition(start, end, t1),
        ]);
      }
    }

    return kept;
  }

  RecommendedPathGenerationResult _generateFallback({
    required Map<String, dynamic> boundaryGeoJson,
    required List<Map<String, dynamic>> exclusionZones,
    required double swathWidthFeet,
  }) {
    final boundary = _asPolygon(boundaryGeoJson);
    final exclusions = _extractExclusionPolygons(exclusionZones);

    final areaBounds = bbox(boundary, recompute: true);
    final minLng = areaBounds[0]!.toDouble();
    final minLat = areaBounds[1]!.toDouble();
    final maxLng = areaBounds[2]!.toDouble();
    final maxLat = areaBounds[3]!.toDouble();

    final spacingMeters =
        (swathWidthFeet <= 0 ? defaultSwathWidthFeet : swathWidthFeet) * 0.3048;
    final double spacingDegrees =
        math.max(lengthToDegrees(spacingMeters, Unit.meters).toDouble(), 1e-6);

    final outputSegments = <List<Position>>[];
    var leftToRight = true;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += spacingDegrees) {
      final start = Position.of([leftToRight ? minLng : maxLng, lat]);
      final end = Position.of([leftToRight ? maxLng : minLng, lat]);
      leftToRight = !leftToRight;

      final mid = _lerpPosition(start, end, 0.5);
      if (!booleanPointInPolygon(mid, boundary)) {
        continue;
      }

      var blocked = false;
      for (final exclusion in exclusions) {
        if (booleanPointInPolygon(mid, exclusion)) {
          blocked = true;
          break;
        }
      }
      if (!blocked) {
        outputSegments.add([start, end]);
      }
    }

    return _toResult(outputSegments, usedFallback: true);
  }

  RecommendedPathGenerationResult _toResult(
    List<List<Position>> segments, {
    required bool usedFallback,
  }) {
    final validSegments = segments
        .where((segment) => segment.length >= 2)
        .toList(growable: false);

    final featureCollection = {
      'type': 'FeatureCollection',
      'features': validSegments
          .map(
            (segment) => {
              'type': 'Feature',
              'properties': const <String, dynamic>{},
              'geometry': {
                'type': 'LineString',
                'coordinates':
                    segment.map((p) => [p.lng, p.lat]).toList(growable: false),
              },
            },
          )
          .toList(growable: false),
    };

    final previewSegments = validSegments
        .map(
          (segment) => segment
              .map((p) => LatLng(p.lat.toDouble(), p.lng.toDouble()))
              .toList(growable: false),
        )
        .toList(growable: false);

    return RecommendedPathGenerationResult(
      geoJson: featureCollection,
      previewSegments: previewSegments,
      usedFallback: usedFallback,
    );
  }

  Polygon _asPolygon(Map<String, dynamic> geoJson) {
    final rawCoordinates = geoJson['coordinates'];
    if (geoJson['type'] != 'Polygon' || rawCoordinates is! List) {
      throw Exception('Expected GeoJSON Polygon');
    }

    final rings = <List<Position>>[];
    for (final ringNode in rawCoordinates) {
      if (ringNode is! List) {
        continue;
      }

      final ring = <Position>[];
      for (final vertex in ringNode) {
        if (vertex is List && vertex.length >= 2) {
          final lng = (vertex[0] as num).toDouble();
          final lat = (vertex[1] as num).toDouble();
          ring.add(Position.of([lng, lat]));
        }
      }

      if (ring.length >= 3) {
        if (ring.first != ring.last) {
          ring.add(ring.first);
        }
        rings.add(ring);
      }
    }

    if (rings.isEmpty) {
      throw Exception('Polygon has no valid coordinates');
    }

    return Polygon(coordinates: rings);
  }

  List<Polygon> _extractExclusionPolygons(
    List<Map<String, dynamic>> exclusionZones,
  ) {
    return exclusionZones
        .map((zone) {
          if (zone['type'] == 'Polygon') {
            return zone;
          }

          final polygon = zone['polygon'];
          if (polygon is Map<String, dynamic> && polygon['type'] == 'Polygon') {
            return polygon;
          }

          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(_asPolygon)
        .toList(growable: false);
  }

  Position _lerpPosition(Position a, Position b, double t) {
    return Position.of([
      a.lng + ((b.lng - a.lng) * t),
      a.lat + ((b.lat - a.lat) * t),
    ]);
  }

  double _projectT(Position start, Position end, Position point) {
    final dx = end.lng - start.lng;
    final dy = end.lat - start.lat;

    if (dx.abs() >= dy.abs()) {
      if (dx.abs() < 1e-12) {
        return 0.0;
      }
      return ((point.lng - start.lng) / dx).clamp(0.0, 1.0).toDouble();
    }

    if (dy.abs() < 1e-12) {
      return 0.0;
    }
    return ((point.lat - start.lat) / dy).clamp(0.0, 1.0).toDouble();
  }

  double _distanceSq(Position a, Position b) {
    final dx = b.lng - a.lng;
    final dy = b.lat - a.lat;
    return ((dx * dx) + (dy * dy)).toDouble();
  }
}
