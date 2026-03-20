import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';
import '../models/property_model.dart';
import '../models/session_model.dart';
class MapLimitCheckResult {
  const MapLimitCheckResult({
    required this.allowed,
    required this.activeCount,
    required this.maxMaps,
    required this.tier,
    required this.message,
  });

  final bool allowed;
  final int activeCount;
  final int maxMaps;
  final String tier;
  final String message;
}


class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  late SupabaseClient _client;
  final Logger _logger = Logger();

  Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
    _client = Supabase.instance.client;
    _logger.i('Supabase initialized');
  }

  SupabaseClient get client => _client;
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  bool get isAuthenticated => currentUser != null;

  // AUTH
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signUp(email: email, password: password);
    } catch (e) {
      _logger.e('Sign up error: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      _logger.e('Sign in error: $e');
      rethrow;
    }
  }

  Future<void> resetPassword({
    required String email,
  }) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      _logger.i('Password reset email sent to: $email');
    } catch (e) {
      _logger.e('Reset password error: $e');
      rethrow;
    }
  }

  Future<void> resendSignupConfirmation({
    required String email,
  }) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      _logger.i('Signup confirmation resent to: $email');
    } catch (e) {
      _logger.e('Resend signup confirmation error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      _logger.i('User signed out');
    } catch (e) {
      _logger.e('Sign out error: $e');
      rethrow;
    }
  }

  // USER PROFILE (profiles table, RLS: auth.uid() = id)
  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final response =
          await _client.from('profiles').select().eq('id', userId).single();
      return UserProfile.fromJson(response);
    } catch (e) {
      _logger.e('Fetch user profile error: $e');
      return null;
    }
  }

  Future<UserProfile?> fetchCurrentUserProfile() async {
    if (currentUserId == null) return null;
    return fetchUserProfile(currentUserId!);
  }

  Future<void> createUserProfile({
    required String userId,
    required String email,
  }) async {
    try {
      await _client.from('profiles').insert({
        'id': userId,
        'email': email,
        'role': 'hobbyist',
        'tier': 'hobbyist',
        'active_maps_count': 0,
        'overlap_threshold': 25,
        'first_login': true,
        'created_at': DateTime.now().toIso8601String(),
      });
      _logger.i('User profile created: $userId');
    } catch (e) {
      _logger.e('Create user profile error: $e');
      rethrow;
    }
  }

  /// Ensures current user has a profile. Creates one if missing.
  /// Called on app init as safety check for existing auth users.
  Future<UserProfile?> ensureCurrentUserProfile() async {
    if (currentUserId == null) return null;

    try {
      // Try to fetch existing profile
      final profile = await fetchUserProfile(currentUserId!);
      if (profile != null) return profile;

      // Profile missing, create it
      _logger.i('Profile missing for user ${currentUserId!}, creating...');
      await createUserProfile(
        userId: currentUserId!,
        email: currentUser?.email ?? '',
      );

      // Return newly created profile
      return await fetchUserProfile(currentUserId!);
    } catch (e) {
      _logger.e('Ensure profile error: $e');
      return null;
    }
  }

  /// Increment active_maps_count after successful property/map creation
  /// Attempts to use RPC, falls back to read-update if not available
  Future<void> incrementActiveMapsCount(String userId) async {
    try {
      // Try RPC first (most atomic and efficient)
      try {
        await _client.rpc('increment_active_maps', params: {'user_id': userId});
        _logger.i('Active maps count incremented via RPC for user: $userId');
        return;
      } catch (rpcError) {
        _logger.w('RPC not available, falling back to manual update');
      }

      // Fallback: Fetch current value, increment, and update
      final current = await _client
          .from('profiles')
          .select('active_maps_count')
          .eq('id', userId)
          .single();

      final newCount =
          ((current['active_maps_count'] as num?) ?? 0).toInt() + 1;

      await _client
          .from('profiles')
          .update({'active_maps_count': newCount}).eq('id', userId);

      _logger.i(
          'Active maps count incremented manually for user: $userId (new: $newCount)');
    } catch (e) {
      _logger.e('Increment active maps count error: $e');
    }
  }

  /// Fetch all authenticated users (for assignment/team selection)
  Future<List<UserProfile>> fetchAllUsers() async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .order('email', ascending: true);

      return (response as List)
          .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Fetch all users error: $e');
      return [];
    }
  }

  /// Fetch workers that can be assigned to corporate properties.
  Future<List<UserProfile>> fetchAssignableWorkers() async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('role', 'worker')
          .order('email', ascending: true);

      return (response as List)
          .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Fetch assignable workers error: $e');
      return [];
    }
  }

  /// Dev/testing helper to switch current user's tier.
  Future<void> updateCurrentUserTier(
    String tier, {
    String? role,
  }) async {
    if (currentUserId == null) {
      throw Exception('No authenticated user');
    }

    try {
      final normalizedTier = UserProfile.normalizeTierValue(tier);
      final payload = <String, dynamic>{'tier': normalizedTier};
      if (role != null && role.isNotEmpty) {
        payload['role'] = role;
      }

      await _client.from('profiles').update(payload).eq('id', currentUserId!);
      _logger.i('Updated current user tier to: $normalizedTier (role: $role)');
    } catch (e) {
      _logger.e('Update current user tier error: $e');
      rethrow;
    }
  }

  Future<void> updateCurrentUserOverlapThreshold(double threshold) async {
    if (currentUserId == null) {
      throw Exception('No authenticated user');
    }

    try {
      await _client.from('profiles').update({
        'overlap_threshold': threshold,
      }).eq('id', currentUserId!);
      _logger.i('Updated overlap threshold to: $threshold');
    } catch (e) {
      _logger.e('Update overlap threshold error: $e');
      rethrow;
    }
  }

  /// Mark first login as complete (set first_login = false)
  Future<void> markFirstLoginComplete() async {
    if (currentUserId == null) {
      throw Exception('No authenticated user');
    }

    try {
      await _client.from('profiles').update({
        'first_login': false,
      }).eq('id', currentUserId!);
      _logger.i('Marked first login complete for user: $currentUserId');
    } catch (e) {
      _logger.e('Mark first login complete error: $e');
      rethrow;
    }
  }

  // PROPERTIES (RLS: auth.uid() = owner_id for owners, or auth.uid() in assigned_to for workers)
  Future<List<Property>> fetchUserProperties(String userId,
      {required String userRole}) async {
    try {
      if (userRole == 'corporate_admin') {
        final response =
            await _client.from('properties').select().eq('owner_id', userId);
        return (response as List)
            .map((p) => Property.fromJson(p as Map<String, dynamic>))
            .toList();
      } else if (userRole == 'worker') {
        // Workers only see properties assigned to them.
        try {
          final response = await _client
              .from('properties')
              .select()
              .contains('assigned_to', [userId]);

          return (response as List)
              .map((p) => Property.fromJson(p as Map<String, dynamic>))
              .toList();
        } catch (_) {
          final response = await _client.from('properties').select();
          return (response as List)
              .map((p) => Property.fromJson(p as Map<String, dynamic>))
              .where((p) => p.assignedTo.contains(userId))
              .toList();
        }
      } else {
        // Hobby/Solo/Large Land users see their own properties.
        final response =
            await _client.from('properties').select().eq('owner_id', userId);
        return (response as List)
            .map((p) => Property.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      _logger.e('Fetch properties error: $e');
      return [];
    }
  }

  /// Recalculate and persist active_maps_count from owned properties.
  Future<int> syncCurrentUserActiveMapsCount() async {
    if (currentUserId == null) return 0;

    try {
      final mappedProperties = await _client
          .from('properties')
          .select('id')
          .eq('owner_id', currentUserId!)
          ;

      final propertyCount = (mappedProperties as List).length;

      await _client
          .from('profiles')
          .update({'active_maps_count': propertyCount}).eq('id', currentUserId!);

      return propertyCount;
    } catch (e) {
      _logger.e('Sync active maps count error: $e');
      return 0;
    }
  }


  Future<MapLimitCheckResult> checkCurrentUserMapLimit() async {
    if (currentUserId == null) {
      throw Exception('No authenticated user');
    }

    try {
      final response = await _client.rpc('check_map_limit');
      final rows = response as List<dynamic>;
      if (rows.isNotEmpty && rows.first is Map<String, dynamic>) {
        final row = rows.first as Map<String, dynamic>;
        final result = MapLimitCheckResult(
          allowed: row['allowed'] as bool? ?? false,
          activeCount: (row['active_count'] as num?)?.toInt() ?? 0,
          maxMaps: (row['max_maps'] as num?)?.toInt() ?? 1,
          tier: row['tier']?.toString() ?? 'hobbyist',
          message: row['message']?.toString() ?? 'Map limit check completed.',
        );

        _logger.i(
          'Map-limit check: count=${result.activeCount}, limit=${result.maxMaps}, tier=${result.tier}, allowed=${result.allowed}',
        );
        return result;
      }
      throw Exception('Empty map-limit response');
    } catch (e) {
      // Fallback to profile snapshot if RPC is not yet deployed.
      final profile = await fetchCurrentUserProfile();
      if (profile == null) {
        throw Exception('Unable to validate map limits.');
      }

      final max = profile.getMaxMaps();
      final allowed = max < 0 ? true : profile.activeMapsCount < max;
      final result = MapLimitCheckResult(
        allowed: allowed,
        activeCount: profile.activeMapsCount,
        maxMaps: max,
        tier: profile.tier,
        message: allowed ? 'Map available.' : 'Max maps reached - upgrade?',
      );
      _logger.i(
        'Map-limit fallback check: count=${result.activeCount}, limit=${result.maxMaps}, tier=${result.tier}, allowed=${result.allowed}',
      );
      return result;
    }
  }
  Future<Property?> fetchProperty(String propertyId) async {
    try {
      final response = await _client
          .from('properties')
          .select()
          .eq('id', propertyId)
          .single();
      return Property.fromJson(response);
    } catch (e) {
      _logger.e('Fetch property error: $e');
      return null;
    }
  }

  Future<String> createProperty({
    required String name,
    String? address,
    required String ownerId,
    String? notes,
    Map<String, dynamic>? mapGeojson,
  }) async {
    final effectiveOwnerId = currentUserId ?? ownerId;
    if (currentUserId != null && ownerId != currentUserId) {
      _logger.w(
          'createProperty ownerId mismatch. Using authenticated user id instead.');
    }

    final limit = await checkCurrentUserMapLimit();
    if (!limit.allowed) {
      throw Exception('Max maps reached - upgrade? (${limit.activeCount}/${limit.maxMaps})');
    }

    final payload = {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
      'owner_id': effectiveOwnerId,
      'notes': notes,
      'assigned_to': [],
      'map_geojson': mapGeojson,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final response =
          await _client.from('properties').insert(payload).select();
      _logger.i('Property created');
      await syncCurrentUserActiveMapsCount();
      return response[0]['id'] as String;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains("could not find the 'address' column")) {
        _logger.w(
            'Address column missing in properties table; retrying insert without it');
        final retryPayload = Map<String, dynamic>.from(payload);
        retryPayload.remove('address');
        final response =
            await _client.from('properties').insert(retryPayload).select();
        _logger.i('Property created without address column');
        await syncCurrentUserActiveMapsCount();
        return response[0]['id'] as String;
      }

      _logger.e('Create property error: $e');
      rethrow;
    }
  }

  Future<void> updateProperty(
      String propertyId, Map<String, dynamic> data) async {
    try {
      await _client.from('properties').update(data).eq('id', propertyId);
      _logger.i('Property updated: $propertyId');
    } catch (e) {
      _logger.e('Update property error: $e');
      rethrow;
    }
  }

  /// Update the assigned_to array for a property (assign workers)
  Future<void> updatePropertyAssignments({
    required String propertyId,
    required List<String> assignedTo,
  }) async {
    try {
      await _client.from('properties').update({
        'assigned_to': assignedTo,
      }).eq('id', propertyId);
      _logger.i(
          'Property assignments updated: $propertyId (${assignedTo.length} workers)');
    } catch (e) {
      _logger.e('Update property assignments error: $e');
      rethrow;
    }
  }

  /// Update exclusion zones for a property
  Future<void> updateExclusionZones({
    required String propertyId,
    required List<Map<String, dynamic>> zones,
  }) async {
    try {
      await _client.from('properties').update({
        'exclusion_zones': zones,
      }).eq('id', propertyId);
      _logger.i('Exclusion zones updated: $propertyId (${zones.length} zones)');
    } catch (e) {
      _logger.e('Update exclusion zones error: $e');
      rethrow;
    }
  }

  /// Update outer boundary polygon for a property
  Future<void> updateOuterBoundary({
    required String propertyId,
    required Map<String, dynamic>? outerBoundary,
  }) async {
    try {
      await _client.from('properties').update({
        'outer_boundary': outerBoundary,
      }).eq('id', propertyId);
      _logger.i('Outer boundary updated: $propertyId');
    } catch (e) {
      _logger.e('Update outer boundary error: $e');
      rethrow;
    }
  }

  /// Update recommended spray path (GeoJSON) for a property
  Future<void> updateRecommendedPath({
    required String propertyId,
    required Map<String, dynamic>? recommendedPath,
  }) async {
    try {
      await _client.from('properties').update({
        'recommended_path': recommendedPath,
      }).eq('id', propertyId);
      _logger.i('Recommended path updated: $propertyId');
    } catch (e) {
      _logger.e('Update recommended path error: $e');
      rethrow;
    }
  }

  /// Clear recommended spray path for a property
  Future<void> clearRecommendedPath({
    required String propertyId,
  }) async {
    return updateRecommendedPath(
      propertyId: propertyId,
      recommendedPath: null,
    );
  }

  // TRACKING SESSIONS (RLS: auth.uid() = user_id)
  Future<String> createTrackingSession({
    required String propertyId,
    required String userId,
    double? tankCapacityGallons,
    double? applicationRatePerAcre,
    String? applicationRateUnit,
    double? chemicalCostPerUnit,
    double? overlapThreshold,
  }) async {
    final fullPayload = {
      'property_id': propertyId,
      'user_id': userId,
      'start_time': DateTime.now().toIso8601String(),
      'paths': [],
      'coverage_percent': null,
      'proof_pdf_url': null,
      'tank_capacity_gallons': tankCapacityGallons,
      'application_rate_per_acre': applicationRatePerAcre,
      'application_rate_unit': applicationRateUnit,
      'chemical_cost_per_unit': chemicalCostPerUnit,
      'overlap_threshold': overlapThreshold,
      'created_at': DateTime.now().toIso8601String(),
    };

    final fallbackPayload = {
      'property_id': propertyId,
      'user_id': userId,
      'start_time': DateTime.now().toIso8601String(),
      'paths': [],
      'coverage_percent': null,
      'proof_pdf_url': null,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final response =
          await _client.from('tracking_sessions').insert(fullPayload).select();

      _logger.i('Tracking session created');
      return response[0]['id'] as String;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final likelySchemaMismatch =
          msg.contains('column') || msg.contains('does not exist') || msg.contains("could not find");

      if (likelySchemaMismatch) {
        try {
          final response = await _client
              .from('tracking_sessions')
              .insert(fallbackPayload)
              .select();
          _logger.w(
            'Tracking session created with fallback payload due to schema mismatch',
          );
          return response[0]['id'] as String;
        } catch (fallbackError) {
          _logger.e('Create tracking session fallback error: $fallbackError');
        }
      }

      _logger.e('Create tracking session error: $e');
      rethrow;
    }
  }

  Future<TrackingSession?> fetchTrackingSession(String sessionId) async {
    try {
      final response = await _client
          .from('tracking_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      return TrackingSession.fromJson(response);
    } catch (e) {
      _logger.e('Fetch tracking session error: $e');
      return null;
    }
  }

  Future<List<TrackingSession>> fetchPropertySessions(String propertyId) async {
    try {
      final response = await _client
          .from('tracking_sessions')
          .select()
          .eq('property_id', propertyId)
          .order('start_time', ascending: false);

      return (response as List)
          .map((s) => TrackingSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Fetch property sessions error: $e');
      return [];
    }
  }

  Future<double?> fetchLatestPropertySwathWidthFeet(String propertyId) async {
    try {
      final response = await _client
          .from('tracking_sessions')
          .select('swath_width_feet')
          .eq('property_id', propertyId)
          .not('swath_width_feet', 'is', null)
          .order('start_time', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final value = response.first['swath_width_feet'];
        if (value is num) {
          return value.toDouble();
        }
      }
      return null;
    } catch (e) {
      _logger.e('Fetch latest swath width error: $e');
      return null;
    }
  }

  Future<void> completeTrackingSession({
    required String sessionId,
    required double coveragePercent,
    String? proofPdfUrl,
    String? rawGnssData,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final payload = <String, dynamic>{
        'end_time': DateTime.now().toIso8601String(),
        'coverage_percent': coveragePercent,
        'proof_pdf_url': proofPdfUrl,
      };
      if (rawGnssData != null && rawGnssData.isNotEmpty) {
        payload['raw_gnss_data'] = rawGnssData;
      }
      if (extraData != null && extraData.isNotEmpty) {
        payload.addAll(extraData);
      }

      await _client
          .from('tracking_sessions')
          .update(payload)
          .eq('id', sessionId);
      _logger.i('Tracking session completed: $sessionId');
    } catch (e) {
      _logger.e('Complete tracking session error: $e');
      rethrow;
    }
  }

  Future<void> updateSessionRawGnssData({
    required String sessionId,
    required String rawGnssData,
  }) async {
    try {
      await _client.from('tracking_sessions').update({
        'raw_gnss_data': rawGnssData,
      }).eq('id', sessionId);
      _logger.i('Session raw GNSS data updated: $sessionId');
    } catch (e) {
      _logger.e('Update session raw GNSS data error: $e');
      rethrow;
    }
  }

  /// Update proof_pdf_url for a tracking session after successful upload
  Future<void> updateSessionProofPdfUrl({
    required String sessionId,
    required String proofPdfUrl,
  }) async {
    try {
      await _client.from('tracking_sessions').update({
        'proof_pdf_url': proofPdfUrl,
      }).eq('id', sessionId);
      _logger.i('Session proof PDF URL updated: $sessionId');
    } catch (e) {
      _logger.e('Update session proof PDF URL error: $e');
      rethrow;
    }
  }

  Future<void> updateSessionPaths(
      String sessionId, List<TrackingPath> paths) async {
    try {
      await _client.from('tracking_sessions').update({
        'paths': paths.map((p) => p.toJson()).toList(),
      }).eq('id', sessionId);
    } catch (e) {
      _logger.e('Update session paths error: $e');
      rethrow;
    }
  }

  Future<void> updateSessionChecklistData({
    required String sessionId,
    required Map<String, dynamic> checklistData,
  }) async {
    try {
      await _client.from('tracking_sessions').update({
        'checklist_data': checklistData,
      }).eq('id', sessionId);
      _logger.i('Session checklist updated: $sessionId');
    } catch (e) {
      _logger.e('Update session checklist error: $e');
      rethrow;
    }
  }

  // ANALYTICS QUERIES

  /// Fetch sessions for a user within a date range (for personal/worker analytics)
  Future<List<TrackingSession>> fetchUserSessions(
    String userId, {
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    try {
      final response = await _client
          .from('tracking_sessions')
          .select()
          .eq('user_id', userId)
          .gte('start_time', dateFrom.toIso8601String())
          .lte('start_time', dateTo.toIso8601String())
          .order('start_time', ascending: false);

      return (response as List)
          .map((s) => TrackingSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Fetch user sessions analytics error: $e');
      return [];
    }
  }

  /// Fetch sessions for all workers of a corporate admin within a date range
  Future<Map<String, List<TrackingSession>>> fetchTeamSessions(
    String adminId, {
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    try {
      // First, get all properties owned by this admin
      final properties =
          await _client.from('properties').select().eq('owner_id', adminId);

      if (properties.isEmpty) return {};

      final Map<String, List<TrackingSession>> teamSessions = {};

      // For each property, get assigned workers
      for (final prop in properties as List) {
        final assignedTo = prop['assigned_to'] as List? ?? [];

        // Get sessions for each assigned worker on this property
        for (final workerId in assignedTo) {
          try {
            final sessions = await _client
                .from('tracking_sessions')
                .select()
                .eq('user_id', workerId)
                .eq('property_id', prop['id'])
                .gte('start_time', dateFrom.toIso8601String())
                .lte('start_time', dateTo.toIso8601String())
                .order('start_time', ascending: false);

            if (!teamSessions.containsKey(workerId)) {
              teamSessions[workerId] = [];
            }

            teamSessions[workerId]!.addAll(
              (sessions as List)
                  .map((s) =>
                      TrackingSession.fromJson(s as Map<String, dynamic>))
                  .toList(),
            );
          } catch (e) {
            _logger.w('Error fetching sessions for worker $workerId: $e');
          }
        }
      }

      return teamSessions;
    } catch (e) {
      _logger.e('Fetch team sessions analytics error: $e');
      return {};
    }
  }

  /// Fetch worker profiles for a corporate admin's team
  Future<List<UserProfile>> fetchTeamWorkers(String adminId) async {
    try {
      // Get all properties owned by admin
      final properties = await _client
          .from('properties')
          .select('assigned_to')
          .eq('owner_id', adminId);

      final Set<String> workerIds = {};
      for (final prop in properties as List) {
        final assigned = prop['assigned_to'] as List? ?? [];
        workerIds.addAll(assigned.cast<String>());
      }

      if (workerIds.isEmpty) return [];

      // Fetch profiles for these workers
      final profiles = await _client
          .from('profiles')
          .select()
          .inFilter('id', workerIds.toList());

      return (profiles as List)
          .map((p) => UserProfile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Fetch team workers error: $e');
      return [];
    }
  }

  /// Get count of maps for billing (corporate admin)
  Future<int> fetchMapsCount(String adminId) async {
    try {
      final response = await _client
          .from('properties')
          .select('id')
          .eq('owner_id', adminId)
          ;

      return (response as List).length;
    } catch (e) {
      _logger.e('Fetch maps count error: $e');
      return 0;
    }
  }
}


