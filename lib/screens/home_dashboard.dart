// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/property_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../services/offline_session_service.dart';
import '../services/supabase_service.dart';
import '../services/weather_service.dart';
import '../utils/theme_controller.dart';
import '../widgets/app_ui.dart';
import '../widgets/dashboard_widgets.dart';
import 'onboarding_screen.dart';
import 'plan_selection_screen.dart';
import 'property_detail_screen.dart';
import 'tracking_screen.dart';
import 'team_overview_screen.dart';

final logger = Logger();

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({Key? key}) : super(key: key);

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _UpcomingTreatmentEntry {
  const _UpcomingTreatmentEntry({
    required this.property,
    required this.treatmentType,
    required this.dueDate,
  });

  final Property property;
  final String treatmentType;
  final DateTime dueDate;
}

class _HomeDashboardState extends State<HomeDashboard> {
  static const Color _greenPrimary = Color(0xFF4CAF50);
  static const Color _blueAccent = Color(0xFF2196F3);

  UserProfile? _userProfile;
  List<Property> _properties = [];
  List<TrackingSession> _allSessions = [];

  List<UserProfile> _teamWorkers = [];
  Map<String, List<TrackingSession>> _teamSessionsByWorker = {};

  final Set<String> _hoveredActionIds = {};
  final Set<String> _pressedActionIds = {};

  double _totalAcresTracked = 0;
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isSyncingPendingSessions = false;
  int _pendingSessionCount = 0;
  int _failedSessionCount = 0;
  Timer? _pendingSyncTimer;
  bool _isOfflineMode = false;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Weather
  final WeatherService _weatherService = WeatherService();
  String? _weatherDesc;
  double? _weatherTempF;
  double? _weatherWindMph;
  int? _weatherRainChancePercent;
  int? _weatherCode;
  DateTime? _weatherFetchedAt;
  String? _weatherError;
  bool _weatherFromCache = false;
  bool _weatherLoading = false;

  // Search
  String _propertySearchQuery = '';

  @override
  void initState() {
    super.initState();
    _initConnectivityMonitoring();
    _loadData();
    _maybeFetchWeather();
    _loadPendingSessionCount();
    _startPendingSyncPoller();
    _attemptStartupSync();
  }

  Future<void> _maybeFetchWeather() async {
    try {
      await _fetchWeather();
    } catch (_) {
      // Keep dashboard stable if weather fetch fails unexpectedly.
    }
  }

  Future<void> _initConnectivityMonitoring() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      final connected = await _hasUsableConnection(initial);
      if (mounted) {
        setState(() => _isOfflineMode = !connected);
      }

      _connectivitySubscription?.cancel();
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((results) async {
        final connectedNow = await _hasUsableConnection(results);
        final wasOffline = _isOfflineMode;

        if (!mounted) return;
        setState(() => _isOfflineMode = !connectedNow);

        if (wasOffline && connectedNow && (_pendingSessionCount > 0 || _failedSessionCount > 0)) {
          await _syncPendingSessions(silent: true);
        }
      });
    } catch (_) {
      // Keep dashboard usable if connectivity plugin is unavailable.
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> _hasUsableConnection(List<ConnectivityResult> results) async {
    if (!_hasConnection(results)) return false;

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.supabaseUrl}/rest/v1/'),
        headers: {
          'apikey': AppConstants.supabaseAnonKey,
          'Authorization': 'Bearer ${AppConstants.supabaseAnonKey}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      // 401/403 are still considered reachable; they prove backend connectivity.
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  Future<void> _loadData() async {
    try {
      final supabase = context.read<SupabaseService>();
      final userId = supabase.currentUserId;
      if (userId == null) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      await supabase.syncCurrentUserActiveMapsCount();

      final profile = await supabase.ensureCurrentUserProfile();
      final role = (profile?.role ?? 'hobbyist').toLowerCase();
      final properties = await supabase.fetchUserProperties(
        userId,
        userRole: role,
      );
      final visibleProperties = role == 'worker'
          ? properties.where((p) => p.assignedTo.contains(userId)).toList()
          : properties;
      final sessions = await supabase.fetchUserSessions(
        userId,
        dateFrom: DateTime(2000),
        dateTo: DateTime.now(),
      );

      List<UserProfile> teamWorkers = [];
      Map<String, List<TrackingSession>> teamSessionsByWorker = {};

      final tierKey = _normalizedTier(profile);
      if (tierKey == 'corporate') {
        teamWorkers = await supabase.fetchTeamWorkers(userId);
        teamSessionsByWorker = await supabase.fetchTeamSessions(
          userId,
          dateFrom: DateTime(2000),
          dateTo: DateTime.now(),
        );
      }

      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        _properties = visibleProperties;
        _allSessions = sessions;
        _teamWorkers = teamWorkers;
        _teamSessionsByWorker = teamSessionsByWorker;
        _totalAcresTracked = _calculateTotalAcres(sessions);
        _isLoading = false;
      });

      if (profile?.firstLogin == true && mounted) {
        Future.microtask(() {
          _showOnboarding();
        });
      }

      await _loadPendingSessionCount();
    } catch (e) {
      logger.e('Load dashboard error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }


  Future<void> _showMapLimitUpgradeDialog(MapLimitCheckResult limit) async {
    if (!mounted) return;

    final maxLabel = limit.maxMaps < 0 ? 'Unlimited' : '${limit.maxMaps}';
    final message =
        'Max maps reached - upgrade? (${limit.activeCount}/$maxLabel)';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map Limit Reached'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openUpgradePlan();
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
  void _showOnboarding() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (context) => const OnboardingScreen(),
    );
  }

  Future<void> _loadPendingSessionCount() async {
    final offline = OfflineSessionService();
    final pending = await offline.getPendingCount();
    final failed = await offline.getFailedCount();
    if (!mounted) return;
    setState(() {
      _pendingSessionCount = pending;
      _failedSessionCount = failed;
    });
  }

  void _startPendingSyncPoller() {
    _pendingSyncTimer?.cancel();
    _pendingSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (!_isOfflineMode &&
          (_pendingSessionCount > 0 || _failedSessionCount > 0) &&
          !_isSyncingPendingSessions) {
        _syncPendingSessions(silent: true);
      }
    });
  }

  Future<void> _syncPendingSessions({bool silent = false}) async {
    if (_isSyncingPendingSessions) return;

    if (_isOfflineMode) {
      if (!silent && mounted) {
        _showSnackBar(
          AppSnackBar.warning(
            'Offline mode is active. Connect to the internet to sync pending sessions.',
          ),
        );
      }
      return;
    }

    final supabase = context.read<SupabaseService>();
    final offline = OfflineSessionService();
    final includeFailed = !silent;
    setState(() => _isSyncingPendingSessions = true);

    try {
      final report = await offline.syncPendingSessionsWithReport(
        supabase,
        includeFailed: includeFailed,
      );
      await _loadPendingSessionCount();

      if (report.syncedCount > 0) {
        await _loadData();
      }

      if (!silent && mounted) {
        _showSnackBar(
          report.syncedCount > 0
              ? AppSnackBar.success(
                  'Synced ${report.syncedCount} session${report.syncedCount == 1 ? '' : 's'}. ${report.pendingCount} queued, ${report.failedCount} failed.',
                )
              : (report.pendingCount > 0 || report.failedCount > 0
                  ? AppSnackBar.warning(
                      'No sessions synced. ${report.pendingCount} queued, ${report.failedCount} failed. Try again on a stronger connection.',
                    )
                  : AppSnackBar.info('No pending sessions to sync.')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        _showSnackBar(AppSnackBar.error(
            'Sync failed. Check your connection and try again.'));
      }
    } finally {
      if (mounted) setState(() => _isSyncingPendingSessions = false);
    }
  }

  Future<void> _attemptStartupSync() async {
    await _loadPendingSessionCount();

    final connectivity = await _connectivity.checkConnectivity();
    final online = await _hasUsableConnection(connectivity);
    if (!mounted) return;
    setState(() => _isOfflineMode = !online);

    if (!online) return;
    if (_pendingSessionCount == 0 && _failedSessionCount == 0) return;
    await _syncPendingSessions(silent: true);
  }
  Future<void> _handleSignOut() async {
    try {
      final supabase = context.read<SupabaseService>();
      await supabase.signOut();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(AppSnackBar.error('Sign out failed. Please try again.'));
    }
  }

  Future<void> _openUpgradePlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlanSelectionScreen(onPlanSelected: _loadData),
      ),
    );
    _loadData();
  }

  void _showSettingsSheet() {
    final themeController = context.read<ThemeController>();
    final supabase = context.read<SupabaseService>();
    double overlapThreshold = _userProfile?.overlapThreshold ?? 25;
    bool isSavingOverlapThreshold = false;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                const Text('Theme mode'),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: themeController.themeMode,
                  title: const Text('System'),
                  onChanged: (mode) {
                    if (mode != null) themeController.setThemeMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: themeController.themeMode,
                  title: const Text('Light'),
                  onChanged: (mode) {
                    if (mode != null) themeController.setThemeMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: themeController.themeMode,
                  title: const Text('Dark'),
                  onChanged: (mode) {
                    if (mode != null) themeController.setThemeMode(mode);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Overlap review threshold',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Highlight overlap risk in the session summary and export once it exceeds ${overlapThreshold.toStringAsFixed(0)}%.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: overlapThreshold,
                  min: 5,
                  max: 50,
                  divisions: 45,
                  label: '${overlapThreshold.toStringAsFixed(0)}%',
                  onChanged: (value) {
                    setSheetState(() => overlapThreshold = value);
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: isSavingOverlapThreshold
                        ? null
                        : () async {
                            try {
                              setSheetState(
                                  () => isSavingOverlapThreshold = true);
                              await supabase.updateCurrentUserOverlapThreshold(
                                overlapThreshold,
                              );
                              if (!mounted) return;
                              setState(() {
                                final profile = _userProfile;
                                if (profile != null) {
                                  _userProfile = UserProfile(
                                    id: profile.id,
                                    email: profile.email,
                                    role: profile.role,
                                    tier: profile.tier,
                                    activeMapsCount: profile.activeMapsCount,
                                    overlapThreshold: overlapThreshold,
                                    stripeCustomerId: profile.stripeCustomerId,
                                    createdAt: profile.createdAt,
                                  );
                                }
                              });
                              Navigator.pop(context);
                              _showSnackBar(
                                AppSnackBar.success(
                                    'Overlap threshold updated.'),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              _showSnackBar(
                                AppSnackBar.error(
                                  'Could not update the overlap threshold.',
                                ),
                              );
                              setSheetState(
                                  () => isSavingOverlapThreshold = false);
                            }
                          },
                    child: Text(
                      isSavingOverlapThreshold ? 'Saving...' : 'Save Threshold',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleProfileAction(String value) async {
    if (value == 'settings') {
      _showSettingsSheet();
      return;
    }

    if (value == 'switch_tier_dev') {
      _showDevTierSwitcher();
      return;
    }

    if (value == 'upgrade') {
      await _openUpgradePlan();
      return;
    }

    if (value == 'sign_out') {
      await _handleSignOut();
    }
  }

  void _showDevTierSwitcher() {
    if (!kDebugMode) return;

    const tierOptions = [
      ('Hobbyist', 'hobbyist'),
      ('Solo Professional', 'solo_professional'),
      ('Premium Solo', 'premium_solo'),
      ('Individual Large Land', 'individual_large_land'),
      ('Corporate', 'corporate'),
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Switch Tier (Dev Only)',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ...tierOptions.map((option) {
              final display = option.$1;
              final tierValue = option.$2;
              return ListTile(
                leading: const Icon(Icons.swap_horiz_outlined),
                title: Text(display),
                onTap: () async {
                  Navigator.pop(context);
                  await _switchTierForTesting(tierValue, display);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTierForTesting(String tierValue, String tierLabel) async {
    if (!kDebugMode) return;

    try {
      final supabase = context.read<SupabaseService>();
      final role = tierValue == 'corporate' ? 'corporate_admin' : 'hobbyist';
      await supabase.updateCurrentUserTier(tierValue, role: role);
      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tier switched to $tierLabel for testing')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to switch tier: $e')),
      );
    }
  }

  void _showAddPropertyDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Property'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Property Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty ||
                  addressController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              try {
                final supabase = context.read<SupabaseService>();
                final limit = await supabase.checkCurrentUserMapLimit();
                if (!limit.allowed) {
                  await _showMapLimitUpgradeDialog(limit);
                  return;
                }

                await supabase.createProperty(
                  name: nameController.text,
                  address: addressController.text,
                  ownerId: supabase.currentUserId!,
                );

                if (mounted) {
                  Navigator.pop(context);
                  await supabase.syncCurrentUserActiveMapsCount();
                  _loadData();
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('Add Property'),
          ),
        ],
      ),
    );
  }

  void _startTrackingAction() {
    final mapProperties = _properties.where((p) => p.hasMapData()).toList();
    if (mapProperties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No mapped properties yet. Add a map first.'),
        ),
      );
      return;
    }

    if (mapProperties.length == 1) {
      _openProperty(mapProperties.first);
      return;
    }

    setState(() => _selectedIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pick a property below to start a new tracking job.'),
      ),
    );
  }

  Future<void> _resumeLastSessionAction() async {
    try {
      final pending = await OfflineSessionService().getPendingSessions();
      final unfinished = pending.where((entry) {
        final hasEnd =
            (entry['end_time']?.toString().trim().isNotEmpty ?? false);
        return !hasEnd;
      }).toList();

      if (unfinished.isEmpty) {
        _showSnackBar(AppSnackBar.info('No unfinished local session found.'));
        return;
      }

      unfinished.sort((a, b) {
        final aQueued = DateTime.tryParse(a['queued_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bQueued = DateTime.tryParse(b['queued_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bQueued.compareTo(aQueued);
      });

      final latest = unfinished.first;
      final propertyId = latest['property_id']?.toString();
      final sessionId = latest['id']?.toString();
      if (propertyId == null || sessionId == null) {
        _showSnackBar(AppSnackBar.warning('Draft session data is incomplete.'));
        return;
      }

      Property? property;
      for (final candidate in _properties) {
        if (candidate.id == propertyId) {
          property = candidate;
          break;
        }
      }
      if (property == null) {
        _showSnackBar(
          AppSnackBar.warning(
              'Could not find the property for the saved draft.'),
        );
        return;
      }
      final resolvedProperty = property;

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackingScreen(
            propertyId: resolvedProperty.id,
            sessionId: sessionId,
            propertyName: resolvedProperty.name,
            tankCapacityGallons:
                (latest['tank_capacity_gallons'] as num?)?.toDouble() ??
                    resolvedProperty.defaultTankCapacityGallons,
            applicationRatePerAcre:
                (latest['application_rate_per_acre'] as num?)?.toDouble() ??
                    resolvedProperty.applicationRatePerAcre,
            applicationRateUnit: latest['application_rate_unit']?.toString() ??
                resolvedProperty.applicationRateUnit,
            chemicalCostPerUnit:
                (latest['chemical_cost_per_unit'] as num?)?.toDouble() ??
                    resolvedProperty.chemicalCostPerUnit,
            overlapThreshold:
                (latest['overlap_threshold'] as num?)?.toDouble() ??
                    (_userProfile?.overlapThreshold ?? 25),
          ),
        ),
      );
      await _loadData();
    } catch (_) {
      _showSnackBar(AppSnackBar.error('Could not resume the last session.'));
    }
  }

  void _addMapAction() {
    if (_properties.isEmpty) {
      _showAddPropertyDialog();
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final property = _properties[index];
            return ListTile(
              leading: const Icon(Icons.landscape_outlined),
              title: Text(property.name),
              subtitle: Text(
                property.hasMapData()
                    ? 'Map exists: update import'
                    : 'No map yet: add import',
              ),
              onTap: () {
                Navigator.pop(context);
                _openProperty(property);
              },
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: _properties.length,
        ),
      ),
    );
  }

  void _openProperty(Property property) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(property: property),
      ),
    ).then((_) => _loadData());
  }

  void _openTeamOverview() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TeamOverviewScreen()),
    ).then((_) => _loadData());
  }

  String _normalizedTier(UserProfile? profile) {
    final tier = UserProfile.normalizeTierValue(profile?.tier ?? 'hobbyist');
    final role = (profile?.role ?? '').toLowerCase();

    if (role == 'corporate_admin' || tier == 'corporate') return 'corporate';
    if (tier == 'individual_large_land') return 'individual_large_land';
    if (tier == 'solo_professional' ||
        tier == 'premium_solo' ||
        tier == 'individual') {
      return 'solo_professional';
    }
    return 'hobbyist';
  }

  Property? _primaryProperty() {
    if (_properties.isEmpty) return null;
    final mapped = _properties.where((p) => p.hasMapData()).toList();
    if (mapped.isNotEmpty) return mapped.first;
    return _properties.first;
  }

  List<TrackingSession> _sessionsForProperty(String propertyId) {
    return _allSessions.where((s) => s.propertyId == propertyId).toList();
  }

  List<_UpcomingTreatmentEntry> _upcomingTreatments({int limit = 5}) {
    final entries = <_UpcomingTreatmentEntry>[];
    for (final property in _properties) {
      final due = property.nextDue;
      final type = property.treatmentType?.trim();
      if (due == null || type == null || type.isEmpty) continue;
      entries.add(
        _UpcomingTreatmentEntry(
          property: property,
          treatmentType: type,
          dueDate: DateTime(due.year, due.month, due.day),
        ),
      );
    }

    entries.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (entries.length <= limit) return entries;
    return entries.take(limit).toList();
  }

  String _upcomingDueLabel(DateTime dueDate) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final diffDays = dueDate.difference(normalizedToday).inDays;

    if (diffDays < 0) {
      final overdue = diffDays.abs();
      return 'overdue by $overdue day${overdue == 1 ? '' : 's'}';
    }
    if (diffDays == 0) {
      return 'due today';
    }
    return 'due in $diffDays day${diffDays == 1 ? '' : 's'}';
  }

  Widget _buildUpcomingTreatmentsCard({int maxItems = 5}) {
    final upcoming = _upcomingTreatments(limit: maxItems);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upcoming Treatments',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            if (upcoming.isEmpty)
              Text(
                'No upcoming treatments',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.72),
                    ),
              )
            else
              ...upcoming.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(
                    '${entry.treatmentType} ${_upcomingDueLabel(entry.dueDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                      'Property: ${entry.property.address ?? entry.property.name}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openProperty(entry.property),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _calculateTotalAcres(List<TrackingSession> sessions) {
    var total = 0.0;
    for (final session in sessions) {
      total += _estimateAcres(session);
    }
    return total;
  }

  double _estimateAcres(TrackingSession session) {
    if (session.paths.length < 2) return 0;

    const distance = Distance();
    var distanceMeters = 0.0;

    for (var i = 0; i < session.paths.length - 1; i++) {
      final a = session.paths[i];
      final b = session.paths[i + 1];
      distanceMeters += distance.as(
        LengthUnit.Meter,
        LatLng(a.latitude, a.longitude),
        LatLng(b.latitude, b.longitude),
      );
    }

    const swathWidth = 2.0;
    final coverageFactor = (session.coveragePercent ?? 100) / 100;
    final areaSqMeters = distanceMeters * swathWidth * coverageFactor;
    return areaSqMeters / 4046.86;
  }

  int _totalTrackedMinutes(List<TrackingSession> sessions) {
    var total = 0;
    for (final session in sessions) {
      final end = session.endTime ?? DateTime.now();
      total += end.difference(session.startTime).inMinutes;
    }
    return total;
  }

  String _coverageLabel(TrackingSession? session) {
    if (session?.coveragePercent == null) return 'N/A';
    return _formatPercent(session!.coveragePercent!);
  }

  String _displayName() {
    final email = _userProfile?.email ?? 'Operator';
    final raw = email.split('@').first;
    if (raw.isEmpty) return 'Operator';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _tierLabel() {
    return _userProfile?.getTierDisplayName() ?? 'Hobbyist';
  }

  String _activeMapsLabel() {
    final active = _userProfile?.activeMapsCount ?? 0;
    final maxMaps = _userProfile?.getMaxMaps() ?? 1;
    if (maxMaps < 0) return '$active/Unlimited';
    return '$active/$maxMaps';
  }

  String _formatAcres(double acres) => AppFormat.acres(acres);

  String _formatPercent(double percent) => AppFormat.percent(percent);

  String _formatDurationMinutes(int minutes) {
    return AppFormat.durationMinutes(minutes);
  }

  bool _isAddMapDisabledByTier() {
    final profile = _userProfile;
    if (profile == null) return false;
    return !profile.canAddNewMap();
  }

  void _handleAddMapPressed() {
    if (_isAddMapDisabledByTier()) {
      final maxMaps = _userProfile?.getMaxMaps() ?? 1;
      final limitLabel = maxMaps < 0 ? 'Unlimited' : '$maxMaps';
      _showSnackBar(
        AppSnackBar.warning(
          'Map limit reached ($limitLabel). Upgrade for unlimited maps and a faster workflow.',
        ),
      );
      return;
    }
    _addMapAction();
  }

  double _averageCoveragePercent(List<TrackingSession> sessions) {
    final covered = sessions.where((s) => s.coveragePercent != null).toList();
    if (covered.isEmpty) return 0;
    final total =
        covered.map((s) => s.coveragePercent!).fold<double>(0, (a, b) => a + b);
    return total / covered.length;
  }

  List<TrackingSession> _recentSessions({int max = 4}) {
    return _allSessions.take(max).toList();
  }

  Future<void> _fetchWeather() async {
    if (!mounted) return;
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final fallback = await _weatherService.cachedOrUnavailable(
          reason: 'Location permission required for live weather.',
        );
        _applyWeatherResult(fallback);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception('Location request timed out'),
      );

      final result = await _weatherService.fetchWithFallback(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _applyWeatherResult(result);
    } catch (e) {
      final fallback = await _weatherService.cachedOrUnavailable(
        reason: 'Weather lookup failed. Please retry.',
      );
      _applyWeatherResult(fallback);
      logger.w('Weather fetch fallback triggered: $e');
    } finally {
      if (mounted) {
        setState(() => _weatherLoading = false);
      }
    }
  }

  void _applyWeatherResult(WeatherFetchResult result) {
    if (!mounted) return;

    setState(() {
      final snapshot = result.snapshot;
      if (snapshot != null) {
        _weatherTempF = snapshot.temperatureF;
        _weatherWindMph = snapshot.windMph;
        _weatherRainChancePercent = snapshot.rainChancePercent;
        _weatherCode = snapshot.weatherCode;
        _weatherDesc = snapshot.description;
        _weatherFetchedAt = snapshot.fetchedAt;
        _weatherFromCache = result.fromCache;
      } else {
        _weatherTempF = null;
        _weatherWindMph = null;
        _weatherRainChancePercent = null;
        _weatherCode = null;
        _weatherDesc = null;
        _weatherFetchedAt = null;
        _weatherFromCache = false;
      }

      _weatherError = result.errorMessage;
    });
  }

  String _weatherAgeLabel() {
    final fetchedAt = _weatherFetchedAt;
    if (fetchedAt == null) return '';
    final mins = DateTime.now().difference(fetchedAt).inMinutes;
    if (mins <= 1) return 'updated just now';
    if (mins < 60) return 'updated ${mins}m ago';
    final hours = (mins / 60).floor();
    return 'updated ${hours}h ago';
  }

  IconData _calcWeatherIcon() {
    final code = _weatherCode;
    if (code == null) return Icons.cloud_outlined;
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud_outlined;
    if (code <= 48) return Icons.foggy;
    if (code <= 55) return Icons.grain;
    if (code <= 65) return Icons.water_drop_outlined;
    if (code <= 77) return Icons.ac_unit;
    if (code <= 82) return Icons.umbrella_outlined;
    return Icons.thunderstorm_outlined;
  }

  Widget _buildWeatherCard(ColorScheme scheme) {
    if (_weatherLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(scheme.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fetching area weather...',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      );
    }

    final hasSnapshot =
        _weatherDesc != null && _weatherTempF != null && _weatherWindMph != null;

    if (hasSnapshot) {
      final ageLabel = _weatherAgeLabel();
      final subtitleParts = <String>[
        if (_weatherFromCache) 'Cached',
        if (ageLabel.isNotEmpty) ageLabel,
      ];
      final subtitle = subtitleParts.join(' - ');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_calcWeatherIcon(), size: 18, color: const Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _weatherDesc ?? 'Weather',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _fetchWeather,
                  tooltip: 'Retry weather fetch',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _weatherChip('Temp', '${_weatherTempF!.round()}F'),
                _weatherChip('Wind', '${_weatherWindMph!.round()} mph'),
                _weatherChip(
                  'Rain chance',
                  '${(_weatherRainChancePercent ?? 0).clamp(0, 100)}%',
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (_weatherError != null && _weatherFromCache) ...[
              const SizedBox(height: 4),
              Text(
                _weatherError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _weatherError ?? 'Weather unavailable',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: _fetchWeather,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _weatherChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
  int _mappedPropertyCount() {
    return _properties.where((p) => p.hasMapData()).length;
  }

  String _propertyNameById(String propertyId) {
    for (final property in _properties) {
      if (property.id == propertyId) return property.name;
    }
    return 'Unknown property';
  }

  String _conditionsLabel(
      double avgCoverage, int jobsToday, int sessionsWithCoverage) {
    if (jobsToday == 0) return 'Standby';
    if (sessionsWithCoverage == 0) return 'Monitoring';
    if (avgCoverage >= 85) return 'Optimal';
    if (avgCoverage >= 65) return 'Good';
    return 'Low coverage';
  }

  IconData _conditionsIcon(
      double avgCoverage, int jobsToday, int sessionsWithCoverage) {
    if (jobsToday == 0) return Icons.pause_circle_outline;
    if (sessionsWithCoverage == 0) return Icons.search_outlined;
    if (avgCoverage >= 85) return Icons.wb_sunny_outlined;
    if (avgCoverage >= 65) return Icons.waves_outlined;
    return Icons.trending_down_outlined;
  }

  Color _conditionsColor(
      double avgCoverage, int jobsToday, int sessionsWithCoverage) {
    if (jobsToday == 0) return Colors.blueGrey;
    if (sessionsWithCoverage == 0) return const Color(0xFF607D8B);
    if (avgCoverage >= 85) return const Color(0xFF2E7D32);
    if (avgCoverage >= 65) return const Color(0xFF0277BD);
    return const Color(0xFFEF6C00);
  }

  List<String> _activityFeed(List<TrackingSession> sessions, {int max = 3}) {
    if (sessions.isEmpty) {
      return const [
        'No live activity yet - start a tracking job to populate feed.'
      ];
    }

    final sorted = sessions.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return sorted.take(max).map((session) {
      final timestamp = DateFormat('MMM d, h:mm a').format(session.startTime);
      final propertyName = _propertyNameById(session.propertyId);
      final coverage = session.coveragePercent != null
          ? _formatPercent(session.coveragePercent!)
          : 'N/A';
      return '$timestamp - $propertyName - $coverage coverage';
    }).toList();
  }

  void _showActivityFeedSheet(List<TrackingSession> sessions) {
    final sorted = sessions.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (ctx, scrollController) => SafeArea(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: sorted.length + 1,
            itemBuilder: (ctx, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Live Property Activity',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                );
              }
              final session = sorted[index - 1];
              final propertyName = _propertyNameById(session.propertyId);
              final date =
                  DateFormat('MMM d, yyyy  h:mm a').format(session.startTime);
              final duration = session.endTime != null
                  ? _formatDurationMinutes(
                      session.endTime!.difference(session.startTime).inMinutes)
                  : 'In progress';
              final coverage = session.coveragePercent != null
                  ? _formatPercent(session.coveragePercent!)
                  : 'N/A';

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: _greenPrimary.withValues(alpha: 0.12),
                    child: const Icon(Icons.bolt_outlined,
                        color: Color(0xFF2E7D32)),
                  ),
                  title: Text(propertyName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(date),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(coverage,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(duration,
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showCrewStatusSheet(bool isCorporate) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.88,
        minChildSize: 0.35,
        builder: (ctx, scrollController) {
          final now = DateTime.now();
          return SafeArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  'Crew Status',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                if (!isCorporate) ...[
                  _crewRowTile(
                    email: _userProfile?.email ?? 'operator@field.com',
                    isActive: _allSessions
                        .any((s) => now.difference(s.startTime).inHours <= 24),
                    subtitle: 'Solo operator',
                    assignedCount: _properties.length,
                  ),
                ] else if (_teamWorkers.isEmpty) ...[
                  const Text('No workers in your team yet.'),
                ] else ...[
                  for (final worker in _teamWorkers)
                    _crewRowTile(
                      email: worker.email,
                      isActive: (_teamSessionsByWorker[worker.id] ?? []).any(
                          (s) => now.difference(s.startTime).inHours <= 24),
                      subtitle:
                          '${(_teamSessionsByWorker[worker.id] ?? []).length} sessions',
                      assignedCount: _properties
                          .where((p) => p.assignedTo.contains(worker.id))
                          .length,
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _crewRowTile({
    required String email,
    required bool isActive,
    required String subtitle,
    required int assignedCount,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              (isActive ? _greenPrimary : Colors.grey).withValues(alpha: 0.14),
          child: Text(
            email.isNotEmpty ? email[0].toUpperCase() : 'W',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isActive ? _greenPrimary : Colors.grey,
            ),
          ),
        ),
        title: Text(email,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$assignedCount prop',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isActive ? _greenPrimary : Colors.grey)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isActive ? 'Active' : 'Standby',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isActive ? _greenPrimary : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMappedPropertiesSheet() {
    String sheetQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final mapped = _properties.where((p) => p.hasMapData()).toList();
          final filtered = sheetQuery.isEmpty
              ? mapped
              : mapped
                  .where((p) =>
                      p.name.toLowerCase().contains(sheetQuery.toLowerCase()) ||
                      (p.address ?? '')
                          .toLowerCase()
                          .contains(sheetQuery.toLowerCase()))
                  .toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (ctx, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mapped Properties',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or address…',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          suffixIcon: sheetQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setSheetState(() => sheetQuery = ''),
                                )
                              : null,
                        ),
                        onChanged: (q) => setSheetState(() => sheetQuery = q),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching properties.'),
                        ))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final property = filtered[i];
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        _greenPrimary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.map_outlined,
                                      color: Color(0xFF2E7D32)),
                                ),
                                title: Text(property.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle:
                                    Text(property.address ?? 'No address'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _openProperty(property);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _opsStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: scheme.surface.withValues(alpha: 0.78),
              border: Border.all(
                  color: color.withValues(alpha: onTap != null ? 0.38 : 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    if (onTap != null) ...[
                      const Spacer(),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: color.withValues(alpha: 0.75)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperationsConsoleCard({
    required List<TrackingSession> sessions,
    required bool isCorporate,
  }) {
    final now = DateTime.now();
    final avgCoverage = _averageCoveragePercent(sessions);
    final sessionsWithCoverage =
        sessions.where((s) => s.coveragePercent != null).length;
    final mappedCount = _mappedPropertyCount();
    final jobsToday = sessions
        .where((s) =>
            s.startTime.year == now.year &&
            s.startTime.month == now.month &&
            s.startTime.day == now.day)
        .length;

    final recentActiveSessions =
        sessions.where((s) => now.difference(s.startTime).inHours <= 24).length;

    final crewTotal = isCorporate ? _teamWorkers.length : 1;
    final crewActive = isCorporate
        ? _teamWorkers
            .where((worker) => (_teamSessionsByWorker[worker.id] ?? [])
                .any((entry) => now.difference(entry.startTime).inHours <= 24))
            .length
        : (recentActiveSessions > 0 ? 1 : 0);

    final feed = _activityFeed(sessions);
    final conditionColor =
        _conditionsColor(avgCoverage, jobsToday, sessionsWithCoverage);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x1F2E7D32), Color(0x1F8D6E63), Color(0x1FB0BEC5)],
          ),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: conditionColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.radar_outlined,
                    color: conditionColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Field Ops Console',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Conditions, crew, and live activity.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildWeatherCard(scheme),
            const SizedBox(height: 14),
            Row(
              children: [
                _opsStatTile(
                  label: 'Field conditions',
                  value: _conditionsLabel(
                      avgCoverage, jobsToday, sessionsWithCoverage),
                  icon: _conditionsIcon(
                      avgCoverage, jobsToday, sessionsWithCoverage),
                  color: conditionColor,
                ),
                const SizedBox(width: 8),
                _opsStatTile(
                  label: 'Crew status',
                  value: '$crewActive/$crewTotal active',
                  icon: Icons.groups_2_outlined,
                  color: const Color(0xFF00695C),
                  onTap: () => _showCrewStatusSheet(isCorporate),
                ),
                const SizedBox(width: 8),
                _opsStatTile(
                  label: 'Mapped',
                  value: '$mappedCount',
                  icon: Icons.map_outlined,
                  color: const Color(0xFF455A64),
                  onTap: _showMappedPropertiesSheet,
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showActivityFeedSheet(sessions),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Live property activity',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        Icon(Icons.open_in_new_rounded,
                            size: 15, color: scheme.primary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...feed.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Icon(Icons.bolt_outlined, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to see full activity log →',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.primary.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lastSessionSummary() {
    if (_allSessions.isEmpty) return 'No sessions yet';
    final s = _allSessions.first;
    final date = DateFormat('MMM d').format(s.startTime);
    final coverage =
        s.coveragePercent != null ? _formatPercent(s.coveragePercent!) : 'N/A';
    return '$date - $coverage';
  }

  bool _shouldShowUpgradeNudge() {
    final profile = _userProfile;
    if (profile == null) return false;

    final tier = UserProfile.normalizeTierValue(profile.tier);
    if (tier == 'hobbyist') return true;

    final maxMaps = profile.getMaxMaps();
    if (maxMaps < 0) return false;
    return profile.activeMapsCount >= (maxMaps - 1);
  }

  String _upgradeNudgeMessage() {
    final profile = _userProfile;
    if (profile == null) return 'Upgrade for higher map limits.';

    final active = profile.activeMapsCount;
    final max = profile.getMaxMaps();
    final maxLabel = max < 0 ? 'Unlimited' : '$max';
    return 'You\'re at $active/$maxLabel maps. Upgrade for unlimited maps?';
  }

  Future<void> _openProofPdf(TrackingSession session) async {
    final proofUrl = session.proofPdfUrl;
    if (proofUrl == null || proofUrl.isEmpty) {
      _showSnackBar(
          AppSnackBar.info('No proof PDF is available for this session yet.'));
      return;
    }

    final uri = Uri.tryParse(proofUrl);
    if (uri == null) {
      _showSnackBar(AppSnackBar.error('The proof PDF link is invalid.'));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showSnackBar(AppSnackBar.error('Could not open the proof PDF.'));
    }
  }

  // ignore: unused_element
  Widget _buildUnifiedHomeDashboard() {
    final recent = _recentSessions();
    final avgCoverage = _averageCoveragePercent(_allSessions);
    final isCorporate = _normalizedTier(_userProfile) == 'corporate';

    final quickActions = <Widget>[
      _buildInteractiveQuickActionCard(
        id: 'start_tracking',
        title: 'Start New Tracking',
        subtitle: 'Go to properties list',
        icon: Icons.play_circle_outline_rounded,
        color: _greenPrimary,
        onTap: () => setState(() => _selectedIndex = 1),
      ),
      _buildInteractiveQuickActionCard(
        id: 'add_map',
        title: 'Add New Map',
        subtitle: 'Import drone map files',
        icon: Icons.add_a_photo_outlined,
        color: _blueAccent,
        onTap: _addMapAction,
      ),
      _buildInteractiveQuickActionCard(
        id: 'resume_session',
        title: 'Resume Last Session',
        subtitle: 'Continue unfinished local draft',
        icon: Icons.playlist_play_outlined,
        color: const Color(0xFFFF9800),
        onTap: _resumeLastSessionAction,
      ),
      _buildInteractiveQuickActionCard(
        id: 'recent_sessions',
        title: 'View Recent Sessions',
        subtitle: 'Latest jobs and proof files',
        icon: Icons.list_alt_rounded,
        color: Colors.teal,
        onTap: () => setState(() => _selectedIndex = 2),
        child: recent.isEmpty
            ? const Text('No jobs yet - start tracking!')
            : Column(
                children: recent.map((session) {
                  final date = DateFormat('MMM d').format(session.startTime);
                  final coverage = session.coveragePercent != null
                      ? '${session.coveragePercent!.toStringAsFixed(0)}%'
                      : 'N/A';
                  return SessionPreviewRow(
                    label: date,
                    coverage: coverage,
                    hasPdf: (session.proofPdfUrl ?? '').isNotEmpty,
                    onViewPdf: () => _openProofPdf(session),
                  );
                }).toList(),
              ),
      ),
      if (isCorporate)
        _buildInteractiveQuickActionCard(
          id: 'team_overview',
          title: 'Team Overview',
          subtitle: 'Assignments and crew stats',
          icon: Icons.groups_2_outlined,
          color: Colors.purple,
          onTap: _openTeamOverview,
        ),
    ];

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildHeroWithTexture(
            DashboardHeroCard(
              welcomeText: 'Welcome back, ${_displayName()}',
              tierLabel: _tierLabel(),
              activeMaps: _activeMapsLabel(),
              lastJob: _lastSessionSummary(),
              totalAcres: _formatAcres(_totalAcresTracked),
            ),
          ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.32),
                  ],
                ),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.10),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today at a glance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Live map usage, acreage progress, and session quality without digging through tabs.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.72),
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    childAspectRatio: 1.9,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      DashboardStatBox(
                        label: 'Active maps',
                        value: _activeMapsLabel(),
                        icon: Icons.map_outlined,
                        color: _greenPrimary,
                      ),
                      DashboardStatBox(
                        label: 'Total acres tracked',
                        value: _formatAcres(_totalAcresTracked),
                        icon: Icons.crop_square_outlined,
                        color: _blueAccent,
                      ),
                      DashboardStatBox(
                        label: 'Average coverage',
                        value: '${avgCoverage.toStringAsFixed(0)}%',
                        icon: Icons.track_changes_outlined,
                        color: Colors.teal,
                      ),
                      DashboardStatBox(
                        label: 'Last session',
                        value: _lastSessionSummary(),
                        icon: Icons.schedule_outlined,
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 80.ms, duration: 300.ms)
              .slideY(begin: 0.04, end: 0),
          const SizedBox(height: 14),
          const DashboardSectionHeader(title: 'Quick Actions'),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: quickActions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.92,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              return quickActions[index]
                  .animate(delay: (70 * index).ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.05, end: 0);
            },
          ),
          if (_shouldShowUpgradeNudge()) ...[
            const SizedBox(height: 14),
            UpgradeNudgeCard(
              message: _upgradeNudgeMessage(),
              onSeePlans: _openUpgradePlan,
            ).animate().fadeIn(delay: 180.ms, duration: 280.ms),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroWithTexture(Widget child) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _greenPrimary.withValues(alpha: 0.08),
            _blueAccent.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -16,
            right: -10,
            child: Icon(
              Icons.grid_4x4_rounded,
              size: 80,
              color: _greenPrimary.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            bottom: -12,
            left: -8,
            child: Icon(
              Icons.map_outlined,
              size: 72,
              color: _blueAccent.withValues(alpha: 0.12),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveQuickActionCard({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isHovered = _hoveredActionIds.contains(id);
    final isPressed = _pressedActionIds.contains(id);
    final liftScale = isPressed
        ? 0.985
        : isHovered
            ? 1.01
            : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredActionIds.add(id)),
      onExit: (_) => setState(() => _hoveredActionIds.remove(id)),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressedActionIds.add(id)),
        onTapCancel: () => setState(() => _pressedActionIds.remove(id)),
        onTapUp: (_) => setState(() => _pressedActionIds.remove(id)),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 130),
          scale: liftScale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withValues(alpha: isHovered ? 0.16 : 0.09),
                  blurRadius: isHovered ? 16 : 10,
                  offset: Offset(0, isHovered ? 8 : 5),
                ),
              ],
            ),
            child: Card(
              elevation: isHovered ? 5 : 3,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: color, size: 30),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface.withValues(alpha: 0.88),
                            ),
                      ),
                      if (child != null) ...[
                        const SizedBox(height: 10),
                        DefaultTextStyle.merge(
                          style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                  ) ??
                              TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                          child: child,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHobbyDashboard() {
    final property = _primaryProperty();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _buildHeroWithTexture(
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    _greenPrimary.withValues(alpha: 0.14),
                    _blueAccent.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your 1 map dashboard',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Only 1 map allowed',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Welcome back, ${_displayName()}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ).animate().fadeIn(duration: 340.ms).slideY(begin: 0.06, end: 0),
        const SizedBox(height: 14),
        _buildOperationsConsoleCard(
          sessions: _allSessions,
          isCorporate: false,
        )
            .animate()
            .fadeIn(delay: 80.ms, duration: 300.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        _buildUpcomingTreatmentsCard(maxItems: 3)
            .animate()
            .fadeIn(delay: 110.ms, duration: 280.ms)
            .slideY(begin: 0.04, end: 0),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Property',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                if (property == null)
                  DashboardEmptyStateCard(
                    title: 'No maps yet. Add one to get started.',
                    subtitle:
                        'Import your first map to unlock tracking and coverage proof.',
                    icon: Icons.map_outlined,
                    actionLabel: 'Add New Map',
                    onAction: _handleAddMapPressed,
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 210,
                      width: double.infinity,
                      child: property.hasOrthomosaic()
                          ? Image.network(
                              property.orthomosaicUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _mapPlaceholder(),
                            )
                          : _mapPlaceholder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    property.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(property.address ?? 'No address'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openProperty(property),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Tracking'),
                    ),
                  ),
                  if (_sessionsForProperty(property.id).isEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('No jobs yet - start tracking!'),
                  ],
                ],
              ],
            ),
          ),
        )
            .animate(delay: 100.ms)
            .fadeIn(duration: 320.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        UpgradeNudgeCard(
          message: _upgradeNudgeMessage(),
          onSeePlans: _openUpgradePlan,
        ).animate(delay: 150.ms).fadeIn(duration: 280.ms),
      ],
    );
  }

  Widget _buildSoloDashboard() {
    final recent = _allSessions.take(4).toList();
    final addMapDisabled = _isAddMapDisabledByTier();
    final avgCoverage = _averageCoveragePercent(_allSessions);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _buildHeroWithTexture(
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${_displayName()}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tierLabel(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DashboardStatBox(
                          label: 'Active maps',
                          value: _activeMapsLabel(),
                          icon: Icons.map_outlined,
                          color: _greenPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DashboardStatBox(
                          label: 'Recent sessions',
                          value: '${_allSessions.length}',
                          icon: Icons.timelapse_outlined,
                          color: _blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DashboardStatBox(
                          label: 'Total acres',
                          value: _formatAcres(_totalAcresTracked),
                          icon: Icons.crop_square_outlined,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DashboardStatBox(
                          label: 'Avg coverage',
                          value: _formatPercent(avgCoverage),
                          icon: Icons.track_changes_outlined,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 14),
        _buildOperationsConsoleCard(
          sessions: _allSessions,
          isCorporate: false,
        )
            .animate()
            .fadeIn(delay: 90.ms, duration: 300.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        _buildUpcomingTreatmentsCard(maxItems: 5)
            .animate()
            .fadeIn(delay: 120.ms, duration: 280.ms)
            .slideY(begin: 0.04, end: 0),
        const SizedBox(height: 14),
        const DashboardSectionHeader(title: 'Quick Actions'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _buildInteractiveQuickActionCard(
                id: 'solo_start_tracking',
                title: 'Start New Tracking',
                subtitle: 'Begin job on a property',
                icon: Icons.play_circle_outline_rounded,
                color: _greenPrimary,
                onTap: _startTrackingAction,
              ),
              _buildInteractiveQuickActionCard(
                id: 'solo_add_map',
                title: 'Add New Map',
                subtitle: 'Import drone footage',
                icon: Icons.map_outlined,
                color: _blueAccent,
                onTap: _handleAddMapPressed,
                child: addMapDisabled
                    ? const Text('Limit reached. Upgrade to add more maps.')
                    : null,
              ),
              _buildInteractiveQuickActionCard(
                id: 'solo_resume_last',
                title: 'Resume Last Session',
                subtitle: 'Continue unfinished local draft',
                icon: Icons.playlist_play_outlined,
                color: const Color(0xFFFF9800),
                onTap: _resumeLastSessionAction,
              ),
              _buildInteractiveQuickActionCard(
                id: 'solo_recent_jobs',
                title: 'View Recent Jobs',
                subtitle: 'Latest sessions with coverage',
                icon: Icons.list_alt_rounded,
                color: Colors.teal,
                onTap: () => setState(() => _selectedIndex = 2),
                child: recent.isEmpty
                    ? const Text('No jobs yet - start tracking!')
                    : Column(
                        children: recent.take(4).map((session) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: RecentJobLine(
                              label:
                                  DateFormat('MMM d').format(session.startTime),
                              value: _coverageLabel(session),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ];

            if (constraints.maxWidth < 700) {
              return Column(
                children: List.generate(cards.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: cards[index]
                        .animate(delay: (80 * index).ms)
                        .fadeIn(duration: 320.ms)
                        .slideY(begin: 0.06, end: 0),
                  );
                }),
              );
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) => cards[index],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics Quick View',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (_allSessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('No jobs yet - start tracking!'),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _inlineMetric(
                          'Total acres', _formatAcres(_totalAcresTracked)),
                    ),
                    Expanded(
                      child: _inlineMetric(
                        'Avg %',
                        _formatPercent(_averageCoveragePercent(_allSessions)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 2),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Open Analytics'),
                ),
              ],
            ),
          ),
        ),
        if (_shouldShowUpgradeNudge()) ...[
          const SizedBox(height: 12),
          UpgradeNudgeCard(
            message: _upgradeNudgeMessage(),
            onSeePlans: _openUpgradePlan,
          ),
        ],
      ],
    );
  }

  Widget _buildLargeLandDashboard() {
    final property = _primaryProperty();
    if (property == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          DashboardEmptyStateCard(
            title: 'No maps yet. Add one to get started.',
            subtitle:
                'Large Land view unlocks once your first property map is imported.',
            icon: Icons.map_outlined,
            actionLabel: 'Add New Map',
            onAction: _handleAddMapPressed,
          ),
        ],
      );
    }

    final sessions = _sessionsForProperty(property.id);
    final lastSession = sessions.isEmpty ? null : sessions.first;
    final totalAcres = _calculateTotalAcres(sessions);
    final totalMinutes = _totalTrackedMinutes(sessions);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _buildOperationsConsoleCard(
          sessions: sessions,
          isCorporate: false,
        ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        _buildUpcomingTreatmentsCard(maxItems: 4)
            .animate()
            .fadeIn(delay: 90.ms, duration: 280.ms)
            .slideY(begin: 0.04, end: 0),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 3,
                    child: property.hasOrthomosaic()
                        ? Image.network(
                            property.orthomosaicUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _mapPlaceholder(),
                          )
                        : _mapPlaceholder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _inlineMetric(
                              'Total acres', _formatAcres(totalAcres)),
                        ),
                        Expanded(
                          child: _inlineMetric(
                              'Last session', _coverageLabel(lastSession)),
                        ),
                        Expanded(
                          child: _inlineMetric('Total time',
                              _formatDurationMinutes(totalMinutes)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openProperty(property),
                        icon: const Icon(Icons.play_arrow, size: 28),
                        label: const Text('Start Tracking on This Property'),
                      ),
                    ),
                    if (sessions.isEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('No jobs yet - start tracking!'),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapPlaceholder() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.tertiaryContainer.withValues(alpha: 0.35),
            scheme.surfaceContainerHighest.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 18,
            right: 18,
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Text(
                  'Ortho Preview',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 52,
            bottom: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.14)),
                color: scheme.surface.withValues(alpha: 0.18),
              ),
              child: Stack(
                children: [
                  for (int i = 0; i < 5; i++)
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 12 + (i * 18),
                      child: Container(
                        height: 2,
                        color: scheme.primary.withValues(alpha: 0.15),
                      ),
                    ),
                  for (int i = 0; i < 4; i++)
                    Positioned(
                      top: 12,
                      bottom: 12,
                      left: 22 + (i * 44),
                      child: Container(
                        width: 2,
                        color: scheme.tertiary.withValues(alpha: 0.13),
                      ),
                    ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: Icon(
                      Icons.place,
                      size: 18,
                      color: scheme.primary.withValues(alpha: 0.8),
                    ),
                  ),
                  Positioned(
                    bottom: 18,
                    left: 18,
                    child: Icon(
                      Icons.track_changes,
                      size: 18,
                      color: scheme.tertiary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 14,
            child: Text(
              'Map preview pending upload',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorporateDashboard() {
    final allTeamSessions =
        _teamSessionsByWorker.values.expand((e) => e).toList();
    final avgCoverage = _averageCoveragePercent(allTeamSessions);
    final activeWorkers = _teamWorkers
        .where((w) => (_teamSessionsByWorker[w.id] ?? []).isNotEmpty)
        .length;
    final mappedCount = _properties.where((p) => p.hasMapData()).length;

    final assignmentRows =
        _properties.where((p) => p.assignedTo.isNotEmpty).take(4).toList();

    final activityFeed = _properties
        .where((p) => p.assignedTo.isNotEmpty)
        .map(
          (p) => 'Assigned ${p.assignedTo.length} workers to ${p.name}',
        )
        .take(3)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _buildHeroWithTexture(
          DashboardHeroCard(
            welcomeText: 'Welcome back, ${_displayName()}',
            tierLabel: 'Corporate Admin Overview',
            activeMaps: '$mappedCount',
            lastJob: '${_formatPercent(avgCoverage)} team avg',
            totalAcres: _formatAcres(_calculateTotalAcres(allTeamSessions)),
          ),
        ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        _buildOperationsConsoleCard(
          sessions: allTeamSessions,
          isCorporate: true,
        )
            .animate()
            .fadeIn(delay: 70.ms, duration: 300.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        _buildUpcomingTreatmentsCard(maxItems: 5)
            .animate()
            .fadeIn(delay: 100.ms, duration: 280.ms)
            .slideY(begin: 0.04, end: 0),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _inlineMetric('Total maps', '$mappedCount')),
            Expanded(child: _inlineMetric('Active workers', '$activeWorkers')),
            Expanded(
                child:
                    _inlineMetric('Avg coverage', _formatPercent(avgCoverage))),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team Assignments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (assignmentRows.isEmpty)
                  const Text('No worker assignments yet.')
                else
                  ...assignmentRows.map((property) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment_ind_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(property.name)),
                          Text('${property.assignedTo.length} workers'),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (activityFeed.isEmpty)
                  const Text(
                      'No assignments yet - create your first assignment.')
                else
                  ...activityFeed.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_outlined, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(entry)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Per-Worker Performance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (_teamWorkers.isEmpty)
                  const Text(
                      'No workers yet. Add or assign workers to start tracking team output.')
                else
                  ..._teamWorkers.take(6).map((worker) {
                    final sessions = _teamSessionsByWorker[worker.id] ?? [];
                    final avg = _averageCoveragePercent(sessions);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text(worker.email.isNotEmpty
                            ? worker.email[0].toUpperCase()
                            : 'W'),
                      ),
                      title: Text(worker.email),
                      subtitle: Text('${sessions.length} sessions'),
                      trailing: Text(
                        _formatPercent(avg),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _showAddPropertyDialog,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Add New Property'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openTeamOverview,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Assign Workers'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _inlineMetric(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isDark
        ? scheme.onSurface.withValues(alpha: 0.84)
        : const Color(0xFF2E4A2B);
    final valueColor = isDark ? Colors.white : const Color(0xFF16301A);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF24332A),
                  const Color(0xFF1E2A23),
                ]
              : [
                  const Color(0xFFF9FBF7),
                  _greenPrimary.withValues(alpha: 0.12),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? scheme.outline.withValues(alpha: 0.45)
              : _greenPrimary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierDashboardTab() {
    final tier = _normalizedTier(_userProfile);
    if (tier == 'corporate') return _buildCorporateDashboard();
    if (tier == 'individual_large_land') return _buildLargeLandDashboard();
    if (tier == 'solo_professional') return _buildSoloDashboard();
    return _buildHobbyDashboard();
  }

  Widget _buildPropertiesTab() {
    final addDisabled = _isAddMapDisabledByTier();
    final visible = _propertySearchQuery.isEmpty
        ? _properties
        : _properties
            .where((p) =>
                p.name
                    .toLowerCase()
                    .contains(_propertySearchQuery.toLowerCase()) ||
                (p.address ?? '')
                    .toLowerCase()
                    .contains(_propertySearchQuery.toLowerCase()))
            .toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          DashboardSectionHeader(
            title: 'Properties (${_properties.length})',
            trailing: Tooltip(
              message: addDisabled
                  ? 'Map limit reached for your current tier'
                  : 'Add a new property',
              child: FilledButton.icon(
                onPressed: addDisabled ? null : _showAddPropertyDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search properties…',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              suffixIcon: _propertySearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          setState(() => _propertySearchQuery = ''),
                    )
                  : null,
            ),
            onChanged: (q) => setState(() => _propertySearchQuery = q),
          ),
          const SizedBox(height: 12),
          if (_properties.isEmpty)
            DashboardEmptyStateCard(
              title: 'No maps yet. Add one to get started.',
              subtitle:
                  'Import your first property map to unlock tracking, proof, and guidance.',
              icon: Icons.map_outlined,
              actionLabel: 'Add Map',
              onAction: addDisabled ? null : _showAddPropertyDialog,
            )
          else if (visible.isEmpty)
            const DashboardEmptyStateCard(
              title: 'No matches found',
              subtitle:
                  'Try a different property name or clear the search to see everything again.',
              icon: Icons.search_off_outlined,
            )
          else
            ...visible.map((property) {
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openProperty(property),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: SizedBox(
                          height: 170,
                          width: double.infinity,
                          child: property.hasOrthomosaic()
                              ? Image.network(
                                  property.orthomosaicUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _mapPlaceholder(),
                                )
                              : _mapPlaceholder(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    property.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    property.hasMapData()
                                        ? 'Map preview ready'
                                        : (property.address ?? 'No address'),
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to open property details',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.chevron_right, size: 28),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final sessionCount = _allSessions.length;
    final avgCoverage = _averageCoveragePercent(_allSessions);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const DashboardSectionHeader(title: 'Analytics Snapshot'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metricCard('Sessions', '$sessionCount', Icons.timeline_outlined),
            _metricCard('Avg Coverage', _formatPercent(avgCoverage),
                Icons.track_changes_outlined),
            _metricCard('Acres', _formatAcres(_totalAcresTracked),
                Icons.crop_square_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open full dashboard',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the full analytics page for charts, team metrics, and range filters.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/analytics'),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Open Analytics'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                _blueAccent.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _blueAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _blueAccent),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.72),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surface,
                scheme.primaryContainer.withValues(alpha: 0.22),
              ],
            ),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.72),
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const DashboardSectionHeader(title: 'More'),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  _greenPrimary.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workspace controls',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Account actions, product info, and upgrade paths collected in one place.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildMoreActionCard(
          icon: Icons.info_outline,
          title: 'About SprayMap Pro',
          subtitle: 'Read product details and platform capabilities.',
          onTap: () => Navigator.pushNamed(context, '/about'),
        ),
        const SizedBox(height: 10),
        _buildMoreActionCard(
          icon: Icons.settings_outlined,
          title: 'App Settings',
          subtitle: 'Theme and dashboard preferences.',
          onTap: _showSettingsSheet,
        ),
        const SizedBox(height: 10),
        _buildMoreActionCard(
          icon: Icons.star_outline,
          title: 'Upgrade Plan',
          subtitle: 'Unlock higher map limits and team features.',
          onTap: _openUpgradePlan,
        ),
        const SizedBox(height: 10),
        _buildMoreActionCard(
          icon: Icons.logout,
          title: 'Sign Out',
          subtitle: 'Securely sign out of this account.',
          onTap: _handleSignOut,
        ),
      ],
    );
  }

  Widget _buildDashboardBackdrop({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface,
                  const Color(0xFFF2F8F1),
                  const Color(0xFFEAF3E4),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -30,
          child: Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x224CAF50),
            ),
          ),
        ),
        Positioned(
          top: 200,
          left: -70,
          child: Container(
            width: 180,
            height: 180,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x1A8D6E63),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          right: 10,
          child: Container(
            width: 170,
            height: 170,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x1AAFB42B),
            ),
          ),
        ),
        child,
      ],
    );
  }

  String _assignedWorkersSummary(Property property) {
    if (property.assignedTo.isEmpty) return 'No workers assigned';

    final emails = property.assignedTo
        .map((id) {
          for (final worker in _teamWorkers) {
            if (worker.id == id) return worker.email;
          }
          return null;
        })
        .whereType<String>()
        .toList();

    if (emails.isEmpty) return '${property.assignedTo.length} assigned';
    return emails.join(', ');
  }

  Widget _buildTeamTab() {
    final assignedProperties =
        _properties.where((p) => p.assignedTo.isNotEmpty).length;
    final activeWorkers = _teamWorkers
        .where((w) => _properties.any((p) => p.assignedTo.contains(w.id)))
        .length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const DashboardSectionHeader(title: 'Team Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _metricCard('Assigned Properties',
                      '$assignedProperties', Icons.assignment_ind_outlined)),
              const SizedBox(width: 10),
              Expanded(
                  child: _metricCard('Active Workers', '$activeWorkers',
                      Icons.groups_2_outlined)),
            ],
          ),
          const SizedBox(height: 12),
          if (_properties.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No properties found for your corporate account.'),
              ),
            )
          else
            ..._properties.map((property) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(property.name),
                  subtitle: Text(_assignedWorkersSummary(property)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openProperty(property),
                ),
              );
            }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _openTeamOverview,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Full Team Screen'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    final isCorporate = _normalizedTier(_userProfile) == 'corporate';

    if (_selectedIndex == 0) return _buildTierDashboardTab();
    if (_selectedIndex == 1) return _buildPropertiesTab();
    if (_selectedIndex == 2) return _buildAnalyticsTab();
    if (isCorporate && _selectedIndex == 3) return _buildTeamTab();
    return _buildMoreTab();
  }

  @override
  void dispose() {
    _pendingSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = (_userProfile?.email ?? 'U').trim();
    final isCorporate = _normalizedTier(_userProfile) == 'corporate';
    final navItems = isCorporate ? 5 : 4;
    final currentIndex =
        _selectedIndex >= navItems ? navItems - 1 : _selectedIndex;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.22),
              ],
            ),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.spa_outlined),
            SizedBox(width: 8),
            Text('SprayMap Pro'),
          ],
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: (_pendingSessionCount > 0 || _failedSessionCount > 0)
                    ? 'Sync pending sessions'
                    : 'No pending sessions',
                onPressed: (_pendingSessionCount > 0 || _failedSessionCount > 0)
                    ? () => _syncPendingSessions()
                    : null,
                icon: _isSyncingPendingSessions
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_outlined),
              ),
              if ((_pendingSessionCount + _failedSessionCount) > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_pendingSessionCount + _failedSessionCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            onSelected: _handleProfileAction,
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[
                const PopupMenuItem(value: 'settings', child: Text('Settings')),
                if (kDebugMode)
                  const PopupMenuItem(
                    value: 'switch_tier_dev',
                    child: Text('Switch Tier (Dev Only)'),
                  ),
                const PopupMenuItem(
                    value: 'upgrade', child: Text('Upgrade plan')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
              ];
              return items;
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: _blueAccent.withValues(alpha: 0.14),
                child: Text(
                  initial.isEmpty ? 'U' : initial[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildDashboardBackdrop(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        '${_selectedIndex}_${_normalizedTier(_userProfile)}',
                      ),
                      child: _buildTabBody(),
                    ),
                  ),
                  if (_isOfflineMode)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 10,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.cloud_off_outlined,
                                  size: 16,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Offline Mode - sessions are saved locally',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_selectedIndex == 0 && (_pendingSessionCount > 0 || _failedSessionCount > 0))
                    Positioned(
                      left: 12,
                      right: 12,
                      top: _isOfflineMode ? 64 : 10,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.cloud_off_outlined,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Pending: $_pendingSessionCount | Failed: $_failedSessionCount',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: _isSyncingPendingSessions
                                    ? null
                                    : () => _syncPendingSessions(),
                                child: const Text('Sync Now'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          elevation: 10,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1F1F1F)
              : Colors.white,
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: currentIndex,
            elevation: 4,
            selectedItemColor: _greenPrimary,
            unselectedItemColor: Colors.grey,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1F1F1F)
                : Colors.white,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: isCorporate
                ? const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.map_outlined),
                      activeIcon: Icon(Icons.map),
                      label: 'Properties',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.bar_chart_outlined),
                      activeIcon: Icon(Icons.bar_chart),
                      label: 'Analytics',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.groups_outlined),
                      activeIcon: Icon(Icons.groups),
                      label: 'Team',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.more_horiz),
                      activeIcon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ]
                : const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.map_outlined),
                      activeIcon: Icon(Icons.map),
                      label: 'Properties',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.bar_chart_outlined),
                      activeIcon: Icon(Icons.bar_chart),
                      label: 'Analytics',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.more_horiz),
                      activeIcon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}




















