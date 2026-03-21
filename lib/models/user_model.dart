// ignore_for_file: constant_identifier_names

enum UserRole { hobbyist, individual, corporate_admin, worker }

class UserProfile {
  final String id;
  final String email;
  final String role; // 'hobbyist', 'individual', 'corporate_admin', 'worker'
  final String tier; // 'hobby', 'individual', 'corporate'
  final int activeMapsCount;
  final double overlapThreshold;
  final String? stripeCustomerId;
  final DateTime createdAt;
  final bool firstLogin; // Legacy flag
  final bool hasSeenOnboarding; // True means show onboarding popup

  UserProfile({
    required this.id,
    required this.email,
    required this.role,
    required this.tier,
    this.activeMapsCount = 0,
    this.overlapThreshold = 25,
    this.stripeCustomerId,
    required this.createdAt,
    this.firstLogin = true,
    this.hasSeenOnboarding = true,
  });

  static String normalizeTierValue(String rawTier) {
    final normalized = rawTier.trim().toLowerCase();

    if (normalized == 'hobby' || normalized == 'hobbyist') return 'hobbyist';
    if (normalized == 'solo' ||
        normalized == 'solo_professional' ||
        normalized == 'soloprofessional') {
      return 'solo_professional';
    }
    if (normalized == 'premium' ||
        normalized == 'premium_solo' ||
        normalized == 'premiumsolo') {
      return 'premium_solo';
    }
    if (normalized == 'large' ||
        normalized == 'large_individual' ||
        normalized == 'largeindividual' ||
        normalized == 'individual_large_land') {
      return 'individual_large_land';
    }
    if (normalized == 'corporate') return 'corporate';

    // Legacy tier used in older builds.
    if (normalized == 'individual') return 'individual';

    return 'hobbyist';
  }

  bool canAddNewMap() {
    final max = getMaxMaps();
    if (max < 0) return true;
    return activeMapsCount < max;
  }

  int getMaxMaps() {
    final normalizedTier = normalizeTierValue(tier);

    if (normalizedTier == 'corporate') return -1;
    if (normalizedTier == 'solo_professional' ||
        normalizedTier == 'premium_solo') {
      return -1;
    }

    if (normalizedTier == 'hobby' || normalizedTier == 'hobbyist') return 1;
    if (normalizedTier == 'individual_large_land') return 1;
    if (normalizedTier == 'individual') return 3;

    return 1;
  }

  String getTierDisplayName() {
    final normalizedTier = normalizeTierValue(tier);

    if (normalizedTier == 'hobby' || normalizedTier == 'hobbyist') {
      return 'Hobbyist';
    }
    if (normalizedTier == 'solo_professional') return 'Solo Professional';
    if (normalizedTier == 'premium_solo') return 'Premium Solo';
    if (normalizedTier == 'individual_large_land') {
      return 'Individual Large Land';
    }
    if (normalizedTier == 'individual') return 'Individual';
    if (normalizedTier == 'corporate') return 'Corporate';

    return tier;
  }

  bool isWorker() => role == 'worker';
  bool isAdmin() => role == 'corporate_admin';

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'tier': tier,
        'active_maps_count': activeMapsCount,
        'overlap_threshold': overlapThreshold,
        'stripe_customer_id': stripeCustomerId,
        'created_at': createdAt.toIso8601String(),
        'first_login': firstLogin,
        'has_seen_onboarding': hasSeenOnboarding,
      };

  static UserProfile fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String? ?? 'hobbyist',
      tier: json['tier'] as String? ?? 'hobbyist',
      activeMapsCount: (json['active_maps_count'] as num?)?.toInt() ?? 0,
      overlapThreshold: (json['overlap_threshold'] as num?)?.toDouble() ?? 25,
      stripeCustomerId: json['stripe_customer_id'] as String?,
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      firstLogin: json['first_login'] as bool? ?? true,
      hasSeenOnboarding: json['has_seen_onboarding'] as bool? ?? true,
    );
  }
}

