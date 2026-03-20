class TrackingPath {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;

  TrackingPath({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'timestamp': timestamp.toIso8601String(),
  };

  static TrackingPath fromJson(Map<String, dynamic> json) {
    return TrackingPath(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class CoveragePolygon {
  final List<List<double>> coordinates;
  final double swathWidth;
  final DateTime createdAt;

  CoveragePolygon({
    required this.coordinates,
    required this.swathWidth,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'coordinates': coordinates,
    'swath_width': swathWidth,
    'created_at': createdAt.toIso8601String(),
  };

  static CoveragePolygon fromJson(Map<String, dynamic> json) {
    return CoveragePolygon(
      coordinates: List<List<double>>.from(
        (json['coordinates'] as List).map((c) => 
          List<double>.from((c as List).map((x) => (x as num).toDouble()))
        )
      ),
      swathWidth: (json['swath_width'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class TrackingSession {
  final String id;
  final String propertyId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final double? coveragePercent;
  final List<TrackingPath> paths;
  final String? proofPdfUrl;
  final double? swathWidthFeet;
  final double? tankCapacityGallons;
  final double? applicationRatePerAcre;
  final String? applicationRateUnit;
  final double? chemicalCostPerUnit;
  final double? overlapPercent;
  final double? overlapSavingsEstimate;
  final double? overlapThreshold;
  final String? partialCompletionReason;
  final Map<String, dynamic>? checklistData;
  final DateTime createdAt;

  TrackingSession({
    required this.id,
    required this.propertyId,
    required this.userId,
    required this.startTime,
    this.endTime,
    this.coveragePercent,
    this.paths = const [],
    this.proofPdfUrl,
    this.swathWidthFeet,
    this.tankCapacityGallons,
    this.applicationRatePerAcre,
    this.applicationRateUnit,
    this.chemicalCostPerUnit,
    this.overlapPercent,
    this.overlapSavingsEstimate,
    this.overlapThreshold,
    this.partialCompletionReason,
    this.checklistData,
    required this.createdAt,
  });

  bool get isActive => endTime == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'property_id': propertyId,
    'user_id': userId,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime?.toIso8601String(),
    'coverage_percent': coveragePercent,
    'paths': paths.map((p) => p.toJson()).toList(),
    'proof_pdf_url': proofPdfUrl,
    'swath_width_feet': swathWidthFeet,
    'tank_capacity_gallons': tankCapacityGallons,
    'application_rate_per_acre': applicationRatePerAcre,
    'application_rate_unit': applicationRateUnit,
    'chemical_cost_per_unit': chemicalCostPerUnit,
    'overlap_percent': overlapPercent,
    'overlap_savings_estimate': overlapSavingsEstimate,
    'overlap_threshold': overlapThreshold,
    'partial_completion_reason': partialCompletionReason,
    'checklist_data': checklistData,
    'created_at': createdAt.toIso8601String(),
  };

  static TrackingSession fromJson(Map<String, dynamic> json) {
    return TrackingSession(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      userId: json['user_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time'] as String) : null,
      coveragePercent: (json['coverage_percent'] as num?)?.toDouble(),
      paths: (json['paths'] as List?)?.map((p) => TrackingPath.fromJson(p as Map<String, dynamic>)).toList() ?? [],
      proofPdfUrl: json['proof_pdf_url'] as String?,
      swathWidthFeet: (json['swath_width_feet'] as num?)?.toDouble(),
      tankCapacityGallons: (json['tank_capacity_gallons'] as num?)?.toDouble(),
      applicationRatePerAcre: (json['application_rate_per_acre'] as num?)?.toDouble(),
      applicationRateUnit: json['application_rate_unit'] as String?,
      chemicalCostPerUnit: (json['chemical_cost_per_unit'] as num?)?.toDouble(),
      overlapPercent: (json['overlap_percent'] as num?)?.toDouble(),
      overlapSavingsEstimate: (json['overlap_savings_estimate'] as num?)?.toDouble(),
      overlapThreshold: (json['overlap_threshold'] as num?)?.toDouble(),
      partialCompletionReason: json['partial_completion_reason'] as String?,
      checklistData: json['checklist_data'] is Map
          ? Map<String, dynamic>.from(json['checklist_data'] as Map)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}
