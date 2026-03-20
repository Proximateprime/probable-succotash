import 'dart:convert';

import 'package:latlong2/latlong.dart';

class MapImportValidationResult {
  final bool isValid;
  final String? errorMessage;
  final double? estimatedAreaAcres;

  const MapImportValidationResult({
    required this.isValid,
    this.errorMessage,
    this.estimatedAreaAcres,
  });
}

class _TierLimits {
  final int maxBytes;
  final double? maxAreaAcres;

  const _TierLimits({
    required this.maxBytes,
    required this.maxAreaAcres,
  });
}

class MapImportValidator {
  static const int _mb = 1024 * 1024;
  static const double _sqmPerAcre = 4046.8564224;
  static const String _upgradeMessage =
      'Map too large for your tier. Upgrade or use a smaller area.';

  static MapImportValidationResult validate({
    required String tier,
    required List<int> geoFileBytes,
    required String geoFileExtension,
    List<int>? orthomosaicBytes,
  }) {
    final limits = _limitsForTier(tier);
    final totalBytes = geoFileBytes.length + (orthomosaicBytes?.length ?? 0);

    if (totalBytes > limits.maxBytes) {
      return MapImportValidationResult(
        isValid: false,
        errorMessage:
            '$_upgradeMessage (File size exceeds ${_formatMb(limits.maxBytes)} MB limit.)',
      );
    }

    final estimatedAreaAcres = _estimateAreaAcres(
      geoFileBytes: geoFileBytes,
      geoFileExtension: geoFileExtension,
    );

    if (estimatedAreaAcres != null &&
        limits.maxAreaAcres != null &&
        estimatedAreaAcres > limits.maxAreaAcres!) {
      return MapImportValidationResult(
        isValid: false,
        errorMessage:
            '$_upgradeMessage (Estimated area ${estimatedAreaAcres.toStringAsFixed(1)} acres exceeds ${limits.maxAreaAcres!.toStringAsFixed(0)}-acre limit.)',
        estimatedAreaAcres: estimatedAreaAcres,
      );
    }

    return MapImportValidationResult(
      isValid: true,
      estimatedAreaAcres: estimatedAreaAcres,
    );
  }

  static _TierLimits _limitsForTier(String tier) {
    final normalized = tier.trim().toLowerCase();

    // Hobbyist
    if (normalized == 'hobby' || normalized == 'hobbyist') {
      return const _TierLimits(maxBytes: 50 * _mb, maxAreaAcres: 5);
    }

    // Solo Professional
    if (normalized == 'solo' ||
        normalized == 'solo_professional' ||
        normalized == 'soloprofessional') {
      return const _TierLimits(maxBytes: 150 * _mb, maxAreaAcres: 50);
    }

    // Premium Solo
    if (normalized == 'premium' ||
        normalized == 'premium_solo' ||
        normalized == 'premiumsolo') {
      return const _TierLimits(maxBytes: 500 * _mb, maxAreaAcres: 200);
    }

    // Individual Large Land (very high / practical no limit)
    if (normalized == 'large' ||
        normalized == 'large_individual' ||
        normalized == 'largeindividual' ||
        normalized == 'individual_large_land') {
      return const _TierLimits(maxBytes: 500 * _mb, maxAreaAcres: null);
    }

    // Corporate
    if (normalized == 'corporate') {
      return const _TierLimits(maxBytes: 500 * _mb, maxAreaAcres: 200);
    }

    // Legacy fallback: treat old "individual" tier as Solo Professional.
    if (normalized == 'individual') {
      return const _TierLimits(maxBytes: 150 * _mb, maxAreaAcres: 50);
    }

    return const _TierLimits(maxBytes: 50 * _mb, maxAreaAcres: 5);
  }

  static double _formatMb(int bytes) => bytes / _mb;

  static double? _estimateAreaAcres({
    required List<int> geoFileBytes,
    required String geoFileExtension,
  }) {
    try {
      final extension = geoFileExtension.trim().toLowerCase();
      final text = utf8.decode(geoFileBytes);

      List<LatLng> points;
      if (extension == 'geojson' || extension == 'json') {
        points = _extractGeoJsonPoints(text);
      } else if (extension == 'kml') {
        points = _extractKmlPoints(text);
      } else {
        return null;
      }

      if (points.length < 2) return null;

      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;

      for (final p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      final midLat = (minLat + maxLat) / 2;
      const distance = Distance();
      final widthMeters = distance(
        LatLng(midLat, minLng),
        LatLng(midLat, maxLng),
      );
      final heightMeters = distance(
        LatLng(minLat, minLng),
        LatLng(maxLat, minLng),
      );

      final areaSqMeters = widthMeters * heightMeters;
      return areaSqMeters / _sqmPerAcre;
    } catch (_) {
      return null;
    }
  }

  static List<LatLng> _extractGeoJsonPoints(String text) {
    final decoded = jsonDecode(text);
    final points = <LatLng>[];
    _collectGeoJsonCoordinates(decoded, points);
    return points;
  }

  static void _collectGeoJsonCoordinates(dynamic node, List<LatLng> points) {
    if (node is Map<String, dynamic>) {
      if (node.containsKey('coordinates')) {
        _collectGeoJsonCoordinates(node['coordinates'], points);
      }

      if (node.containsKey('features') && node['features'] is List) {
        for (final feature in node['features'] as List) {
          _collectGeoJsonCoordinates(feature, points);
        }
      }

      if (node.containsKey('geometry')) {
        _collectGeoJsonCoordinates(node['geometry'], points);
      }

      return;
    }

    if (node is List) {
      if (node.length >= 2 && node[0] is num && node[1] is num) {
        final lng = (node[0] as num).toDouble();
        final lat = (node[1] as num).toDouble();
        points.add(LatLng(lat, lng));
        return;
      }

      for (final child in node) {
        _collectGeoJsonCoordinates(child, points);
      }
    }
  }

  static List<LatLng> _extractKmlPoints(String text) {
    final points = <LatLng>[];
    final coordinateBlocks = RegExp(
      r'<coordinates>([\s\S]*?)</coordinates>',
      caseSensitive: false,
    ).allMatches(text);

    for (final block in coordinateBlocks) {
      final raw = (block.group(1) ?? '').trim();
      if (raw.isEmpty) continue;

      final entries = raw.split(RegExp(r'\s+'));
      for (final entry in entries) {
        final parts = entry.split(',');
        if (parts.length < 2) continue;

        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lat == null || lng == null) continue;

        points.add(LatLng(lat, lng));
      }
    }

    return points;
  }
}
