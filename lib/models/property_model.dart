class Property {
  final String id;
  final String name;
  final String? address;
  final String? notes;
  final String? ownerId;
  final List<String> assignedTo;
  final Map<String, dynamic>? mapGeojson;
  final String? orthomosaicUrl;
  final List<Map<String, dynamic>>? exclusionZones; // GeoJSON polygons
  final List<Map<String, dynamic>>? specialZones; // Named special zones
  final Map<String, dynamic>? outerBoundary; // GeoJSON polygon
  final String? boundaryMode; // walked_perimeter | property_only | between_property_and_walked
  final double? outerBoundaryBufferFeet;
  final dynamic recommendedPath; // Optional guidance path (GeoJSON or list)
  final String? treatmentType;
  final DateTime? lastApplication;
  final int? frequencyDays;
  final DateTime? nextDue;
  final double? applicationRatePerAcre;
  final String? applicationRateUnit;
  final double? chemicalCostPerUnit;
  final double? defaultTankCapacityGallons;
  final DateTime createdAt;

  Property({
    required this.id,
    required this.name,
    this.address,
    this.notes,
    this.ownerId,
    this.assignedTo = const [],
    this.mapGeojson,
    this.orthomosaicUrl,
    this.exclusionZones,
    this.specialZones,
    this.outerBoundary,
    this.boundaryMode,
    this.outerBoundaryBufferFeet,
    this.recommendedPath,
    this.treatmentType,
    this.lastApplication,
    this.frequencyDays,
    this.nextDue,
    this.applicationRatePerAcre,
    this.applicationRateUnit,
    this.chemicalCostPerUnit,
    this.defaultTankCapacityGallons,
    required this.createdAt,
  });

  bool hasMapData() => mapGeojson != null;
  bool hasOrthomosaic() => orthomosaicUrl != null && orthomosaicUrl!.isNotEmpty;
  bool hasExclusionZones() =>
      exclusionZones != null && exclusionZones!.isNotEmpty;
  bool hasOuterBoundary() => outerBoundary != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'notes': notes,
        'owner_id': ownerId,
        'assigned_to': assignedTo,
        'map_geojson': mapGeojson,
        'orthomosaic_url': orthomosaicUrl,
        'exclusion_zones': exclusionZones,
        'special_zones': specialZones,
        'outer_boundary': outerBoundary,
        'boundary_mode': boundaryMode,
        'outer_boundary_buffer_feet': outerBoundaryBufferFeet,
        'recommended_path': recommendedPath,
        'treatment_type': treatmentType,
        'last_application': lastApplication?.toIso8601String(),
        'frequency_days': frequencyDays,
        'next_due': nextDue?.toIso8601String(),
        'application_rate_per_acre': applicationRatePerAcre,
        'application_rate_unit': applicationRateUnit,
        'chemical_cost_per_unit': chemicalCostPerUnit,
        'default_tank_capacity_gallons': defaultTankCapacityGallons,
        'created_at': createdAt.toIso8601String(),
      };

  static Property fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    }

    List<Map<String, dynamic>>? asMapList(dynamic value) {
      if (value is! List) return null;
      final mapped = value
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      return mapped;
    }

    DateTime? asDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim());
      }
      return null;
    }

    return Property(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      ownerId: json['owner_id'] as String?,
      assignedTo: List<String>.from(json['assigned_to'] as List? ?? []),
      mapGeojson: asMap(json['map_geojson']),
      orthomosaicUrl: json['orthomosaic_url'] as String?,
      exclusionZones: asMapList(json['exclusion_zones']),
      specialZones: asMapList(json['special_zones']),
      outerBoundary: asMap(json['outer_boundary']),
      boundaryMode: json['boundary_mode'] as String?,
      outerBoundaryBufferFeet: (json['outer_boundary_buffer_feet'] as num?)?.toDouble(),
      recommendedPath: json['recommended_path'],
      treatmentType: json['treatment_type'] as String?,
      lastApplication: asDate(json['last_application']),
      frequencyDays: (json['frequency_days'] as num?)?.toInt(),
      nextDue: asDate(json['next_due']),
        applicationRatePerAcre:
          (json['application_rate_per_acre'] as num?)?.toDouble(),
        applicationRateUnit: json['application_rate_unit'] as String?,
        chemicalCostPerUnit: (json['chemical_cost_per_unit'] as num?)?.toDouble(),
        defaultTankCapacityGallons:
          (json['default_tank_capacity_gallons'] as num?)?.toDouble(),
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

