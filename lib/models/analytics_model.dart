/// Analytics data models for SprayMap Pro

class SessionStats {
  final int totalSessions;
  final double totalTrackedMinutes;
  final double averageSessionMinutes;
  final double totalAcresCovered;
  final double averageCoveragePercent;
  final DateTime dateFrom;
  final DateTime dateTo;

  SessionStats({
    required this.totalSessions,
    required this.totalTrackedMinutes,
    required this.averageSessionMinutes,
    required this.totalAcresCovered,
    required this.averageCoveragePercent,
    required this.dateFrom,
    required this.dateTo,
  });

  factory SessionStats.empty() {
    return SessionStats(
      totalSessions: 0,
      totalTrackedMinutes: 0,
      averageSessionMinutes: 0,
      totalAcresCovered: 0,
      averageCoveragePercent: 0,
      dateFrom: DateTime.now().subtract(const Duration(days: 30)),
      dateTo: DateTime.now(),
    );
  }

  /// Calculate acres covered from coverage %, distance, and swath width
  /// Formula: (distance_km * swath_width_m * coverage_percent) / 100 converted to acres
  static double calculateAcres({
    required double distanceKm,
    required double swathWidthMeters,
    required double coveragePercent,
  }) {
    // Convert distance to meters
    final distanceMeters = distanceKm * 1000;
    // Calculate area in square meters: distance * width
    final areaSqMeters = distanceMeters * swathWidthMeters;
    // Convert to acres (1 acre = 4046.86 m²)
    final acres = areaSqMeters / 4046.86;
    // Apply coverage percentage
    return (acres * coveragePercent) / 100;
  }
}

class WorkerStats {
  final String workerId;
  final String workerEmail;
  final int sessionCount;
  final double totalTrackedMinutes;
  final double averageSessionMinutes;
  final double totalAcresCovered;
  final double averageCoveragePercent;

  WorkerStats({
    required this.workerId,
    required this.workerEmail,
    required this.sessionCount,
    required this.totalTrackedMinutes,
    required this.averageSessionMinutes,
    required this.totalAcresCovered,
    required this.averageCoveragePercent,
  });

  factory WorkerStats.empty(String workerId, String email) {
    return WorkerStats(
      workerId: workerId,
      workerEmail: email,
      sessionCount: 0,
      totalTrackedMinutes: 0,
      averageSessionMinutes: 0,
      totalAcresCovered: 0,
      averageCoveragePercent: 0,
    );
  }
}

class BillingStats {
  final int totalMaps;
  final double baseCost; // $149/month for corporate
  final int extraMapsCount; // Maps over 10 limit
  final double extraMapsFee; // $5 per extra map
  final double totalMonthlyCost;

  BillingStats({
    required this.totalMaps,
    this.baseCost = 149.0,
    required this.extraMapsCount,
    this.extraMapsFee = 5.0,
  }) : totalMonthlyCost = baseCost + (extraMapsCount * extraMapsFee);

  factory BillingStats.create({required int totalMaps}) {
    final extraMaps = totalMaps > 10 ? totalMaps - 10 : 0;
    return BillingStats(
      totalMaps: totalMaps,
      extraMapsCount: extraMaps,
    );
  }
}

enum DateRange {
  last7Days,
  last30Days,
  allTime,
}

extension DateRangeExt on DateRange {
  String get label {
    switch (this) {
      case DateRange.last7Days:
        return 'Last 7 Days';
      case DateRange.last30Days:
        return 'Last 30 Days';
      case DateRange.allTime:
        return 'All Time';
    }
  }

  DateTime getStartDate() {
    final now = DateTime.now();
    switch (this) {
      case DateRange.last7Days:
        return now.subtract(const Duration(days: 7));
      case DateRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case DateRange.allTime:
        return DateTime(2000); // Far past date
    }
  }

  DateTime getEndDate() {
    return DateTime.now();
  }
}
