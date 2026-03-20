import 'package:latlong2/latlong.dart';

/// Represents a single exclusion zone (no-spray area)
class ExclusionZone {
  final String id;
  final List<LatLng> vertices; // Polygon vertices in lat/lng
  final DateTime createdAt;
  final String? notes;

  ExclusionZone({
    required this.id,
    required this.vertices,
    required this.createdAt,
    this.notes,
  });

  /// Convert to GeoJSON geometry format for storage
  Map<String, dynamic> toGeoJSON() {
    return {
      'type': 'Polygon',
      'coordinates': [
        vertices.map((point) => [point.longitude, point.latitude]).toList(),
      ],
      if (notes != null && notes!.trim().isNotEmpty)
        'properties': {
          'note': notes!.trim(),
        },
    };
  }

  /// Preferred storage object for exclusion_zones jsonb array.
  Map<String, dynamic> toStorageMap({String zoneType = 'exclusion_zone'}) {
    final trimmed = notes?.trim();
    return {
      'polygon': {
        'type': 'Polygon',
        'coordinates': [
          vertices.map((point) => [point.longitude, point.latitude]).toList(),
        ],
      },
      'zone_type': zoneType,
      if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
    };
  }

  /// Convert to serializable map for JSON storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vertices':
          vertices.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'created_at': createdAt.toIso8601String(),
      'notes': notes,
    };
  }

  /// Create from stored JSON format
  static ExclusionZone fromJson(Map<String, dynamic> json) {
    final vertices = (json['vertices'] as List?)
            ?.map((v) => LatLng(v['lat'] as double, v['lon'] as double))
            .toList() ??
        [];

    return ExclusionZone(
      id: json['id'] as String,
      vertices: vertices,
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      notes: json['notes'] as String?,
    );
  }

  /// Create from GeoJSON polygon geometry
  static ExclusionZone fromGeoJSON(Map<String, dynamic> geojson, {String? id}) {
    final source = (geojson['polygon'] is Map)
        ? Map<String, dynamic>.from(geojson['polygon'] as Map)
        : geojson;

    final coordinates = (source['coordinates'] as List?)?.first as List? ?? [];
    final vertices = coordinates
        .map((coord) => LatLng(coord[1] as double, coord[0] as double))
        .toList();

    final fromProperties = (source['properties'] is Map)
        ? (source['properties']['note']?.toString())
        : null;
    final note = geojson['note']?.toString() ?? fromProperties;

    return ExclusionZone(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      vertices: vertices,
      createdAt: DateTime.now(),
      notes: (note == null || note.trim().isEmpty) ? null : note.trim(),
    );
  }
}
