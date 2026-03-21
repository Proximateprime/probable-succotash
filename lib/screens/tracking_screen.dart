// ignore_for_file: use_build_context_synchronously, deprecated_member_use, curly_braces_in_flow_control_structures, prefer_const_declarations

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:turf/turf.dart' as turf;

import '../models/property_model.dart';
import '../models/session_model.dart';
import '../services/map_service.dart';
import '../services/network_status_service.dart';
import '../services/offline_session_service.dart';
import '../services/recommended_path_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_ui.dart';
import 'export_screen.dart';
import 'job_summary_screen.dart';

enum TrackingViewMode { map, guidance }

class TrackingScreen extends StatefulWidget {
  final String propertyId;
  final String sessionId;
  final String propertyName;
  final double? tankCapacityGallons;
  final double? applicationRatePerAcre;
  final String? applicationRateUnit;
  final double? chemicalCostPerUnit;
  final double overlapThreshold;

  const TrackingScreen({
    Key? key,
    required this.propertyId,
    required this.sessionId,
    required this.propertyName,
    this.tankCapacityGallons,
    this.applicationRatePerAcre,
    this.applicationRateUnit,
    this.chemicalCostPerUnit,
    this.overlapThreshold = 25,
  }) : super(key: key);

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const String _satelliteUrlTemplate =
      'https://mt.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  static const MethodChannel _gnssSupportChannel =
      MethodChannel('spraymap/gnss_support');
  static const EventChannel _rawGnssEventChannel =
      EventChannel('spraymap/raw_gnss_measurements');

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<dynamic>? _rawGnssSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerStream;
  Timer? _elapsedTimer;
  Timer? _cancelJobTimer;

  final MapController _mapController = MapController();

  Property? _property;
  LatLngBounds? _mapBounds;
  List<LatLng> _propertyBoundary = [];
  List<Polygon> _exclusionPolygons = [];
  List<List<LatLng>> _exclusionRings = [];
  List<MapEntry<List<LatLng>, String?>> _exclusionRingNotes = const [];
  List<LatLng> _outerBoundaryRing = [];
  List<Polyline> _outerBoundaryDashed = [];
  List<_SpecialZoneOverlay> _specialZones = const [];
  String _activeZoneSelection = _allSprayableSelectionId;

  static const String _allSprayableSelectionId = '__all_sprayable__';
  static const List<double> _presetSwathFeet = [
    2.0,
    3.0,
    4.0,
    5.0,
    6.0,
    8.0,
    10.0
  ];
  static const String _swathPrefPrefix = 'tracking_swath_width_feet';
  static const String _tankPrefPrefix = 'tracking_tank_capacity_gallons';
  static const int _autoPauseInactivitySeconds = 180;
  static const double _maxAcceptedAccuracyMeters = 16.0;
  static const double _stationarySpeedThresholdMps = 0.85;
  static const double _highPrecisionStationarySpeedThresholdMps = 0.6;
  static const double _stationaryExtraMovementMeters = 3.0;
  static const double _highPrecisionStationaryExtraMovementMeters = 1.8;
  static const double _minAccuracyNoiseFloorMeters = 1.5;
  static const double _maxAccuracyNoiseFloorMeters = 8.5;

  final List<TrackingPath> _paths = [];
  bool _isTracking = true;
  bool _isSessionEnded = false;
  bool _isLoadingMap = true;
  bool _orientationLocked = true;
  bool _outOfBoundsNoticeShown = false;
  DateTime? _lastNoSprayWarning;

  double _swathWidthFeet = 5.0;
  double _latitude = 0;
  double _longitude = 0;
  double _accuracy = 0;
  int _elapsedSeconds = 0;

  TrackingViewMode _viewMode = TrackingViewMode.map;
  List<LatLng> _recommendedPath = const [];
  int _guidanceSegmentIndex = -1;
  double _distanceToLineMeters = 0;
  String _guidanceStatus = 'No guidance path available';
  double _displayArrowRadians = 0;
  bool _guidanceDeviationWarning = false;
  bool _showDeviationFlash = false;
  DateTime? _lastDeviationHaptic;
  Timer? _deviationFlashTimer;

  bool _isCheckingGnssSupport = true;
  bool _isRawGnssSupported = false;
  bool _highAccuracyGnssEnabled = false;
  final List<String> _rawGnssObsLines = [];
  String? _rawGnssObsContent;
  DateTime _sessionStartedAt = DateTime.now();
  DateTime? _lastMovementAt;
  bool _autoPausedByInactivity = false;
  bool _showOverlapHeatmap = true;
  DateTime? _lastGpsErrorAt;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOfflineMode = false;
  DateTime? _lastOfflineSnapshotAt;
  bool _reachModeEnabled = false;
  bool _isCompassAvailable = false;
  double? _compassHeadingDegrees;
  double _manualHeadingOffsetDegrees = 0;
  double _manualHeadingDegrees = 0;
  final List<_ReachSpraySample> _reachSamples = [];
  bool _cancelJobArmed = false;
  int _cancelJobTapsRemaining = 3;
  int _cancelJobSecondsLeft = 0;
  bool _cancelDialogOpen = false;
  _SessionSummary? _sessionSummary;
  double? _tankCapacityGallons;
  double? _applicationRatePerAcre;
  String _applicationRateUnit = 'gal';
  double? _chemicalCostPerUnit;
  final Set<int> _triggeredLowProductThresholds = <int>{};
  int? _activeLowProductThreshold;

  @override
  void initState() {
    super.initState();
    _tankCapacityGallons = widget.tankCapacityGallons;
    _applicationRatePerAcre = widget.applicationRatePerAcre;
    _applicationRateUnit = widget.applicationRateUnit ?? 'gal';
    _chemicalCostPerUnit = widget.chemicalCostPerUnit;
    _initializeTracking();
  }

  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  Future<void> _initializeTracking() async {
    await _initConnectivityMonitoring();
    _startCompassHeadingStream();
    await _loadSwathWidthPreference();
    await _promptForTankCapacityAtSessionStart();
    await _checkRawGnssSupport();
    await _hydrateFromOfflineDraft();
    await _loadPropertyMapData();
    await _primeCurrentLocation();
    _startTracking();
    _startElapsedTimer();
  }

  Future<void> _hydrateFromOfflineDraft() async {
    try {
      final pending = await OfflineSessionService().getPendingSessions();
      final draft = pending.firstWhere(
        (entry) =>
            entry['id']?.toString() == widget.sessionId &&
            entry['end_time'] == null,
        orElse: () => const <String, dynamic>{},
      );

      if (draft.isEmpty) return;

      final startTimeRaw = draft['start_time']?.toString();
      final parsedStart =
          startTimeRaw == null ? null : DateTime.tryParse(startTimeRaw);

      final rawPaths = draft['paths'];
      final hydratedPaths = <TrackingPath>[];
      if (rawPaths is List) {
        for (final entry in rawPaths) {
          if (entry is Map) {
            hydratedPaths.add(
              TrackingPath.fromJson(Map<String, dynamic>.from(entry)),
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        if (parsedStart != null) {
          _sessionStartedAt = parsedStart;
          _elapsedSeconds = DateTime.now().difference(parsedStart).inSeconds;
        }
        if (hydratedPaths.isNotEmpty) {
          _paths
            ..clear()
            ..addAll(hydratedPaths);
          _lastMovementAt = hydratedPaths.last.timestamp;
        }
      });
    } catch (_) {
      // Continue with a fresh in-memory session if draft hydration fails.
    }
  }

  String _swathPrefKey() {
    final userId = context.read<SupabaseService>().currentUserId ?? 'anonymous';
    return '${_swathPrefPrefix}_$userId';
  }

  String _tankPrefKey() {
    final userId = context.read<SupabaseService>().currentUserId ?? 'anonymous';
    return '${_tankPrefPrefix}_$userId';
  }

  Future<double?> _loadTankCapacityPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_tankPrefKey());
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistTankCapacityPreference(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_tankPrefKey(), value);
    } catch (_) {
      // Continue even if preference save fails.
    }
  }

  Future<void> _promptForTankCapacityAtSessionStart() async {
    if (!mounted) return;

    final saved = await _loadTankCapacityPreference();
    final initial = _tankCapacityGallons ?? saved;
    final controller = TextEditingController(
      text: initial == null ? '' : initial.toStringAsFixed(1),
    );
    var remember = true;

    final selected = await showDialog<double?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tank Capacity (optional)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tank capacity (gal)',
                  hintText: 'e.g. 2.0',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: remember,
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember for next jobs'),
                onChanged: (value) {
                  setDialogState(() => remember = value ?? true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null || parsed <= 0) {
                  Navigator.pop(context, null);
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (!mounted) return;

    if (selected == null) {
      if (saved != null && _tankCapacityGallons == null) {
        setState(() => _tankCapacityGallons = saved);
      }
      return;
    }

    setState(() => _tankCapacityGallons = selected);
    if (remember) {
      await _persistTankCapacityPreference(selected);
    }
  }

  double _normalizeSwathValue(double value) {
    final clamped = value.clamp(1.0, 10.0);
    return (clamped * 2).round() / 2;
  }

  Future<void> _loadSwathWidthPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_swathPrefKey());
      if (saved == null || !mounted) return;

      setState(() {
        _swathWidthFeet = _normalizeSwathValue(saved);
      });
    } catch (_) {
      // Keep default value if preference loading fails.
    }
  }

  Future<void> _persistSwathWidthPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_swathPrefKey(), _swathWidthFeet);
    } catch (_) {
      // Continue if preference persistence fails.
    }
  }

  void _setSwathWidthFeet(double value) {
    final normalized = _normalizeSwathValue(value);
    setState(() {
      _swathWidthFeet = normalized;
    });
    unawaited(_persistSwathWidthPreference());
  }

  bool get _isCustomSwathSelection {
    return !_presetSwathFeet.any((v) => (v - _swathWidthFeet).abs() < 1e-6);
  }

  String get _swathSegmentSelection =>
      _isCustomSwathSelection ? 'custom' : _swathWidthFeet.toStringAsFixed(1);

  Future<void> _openCustomSwathPicker() async {
    var draft = _normalizeSwathValue(_swathWidthFeet);

    final selected = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Custom Reach / Swath'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${draft.toStringAsFixed(1)} ft',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Slider(
                value: draft,
                min: 1,
                max: 10,
                divisions: 18,
                label: '${draft.toStringAsFixed(1)} ft',
                onChanged: (value) {
                  setDialogState(() {
                    draft = _normalizeSwathValue(value);
                  });
                },
              ),
              const SizedBox(height: 4),
              const Text(
                '0.5 ft increments (1.0 - 10.0 ft)',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft),
              child: const Text('Use Value'),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    _setSwathWidthFeet(selected);
  }

  void _startCompassHeadingStream() {
    _magnetometerStream?.cancel();
    _magnetometerStream = magnetometerEventStream().listen(
      (event) {
        final rawHeading =
            (90 - (math.atan2(event.y, event.x) * 180 / math.pi) + 360) % 360;

        if (!mounted) return;
        setState(() {
          _isCompassAvailable = true;
          if (_compassHeadingDegrees == null) {
            _compassHeadingDegrees = rawHeading;
          } else {
            _compassHeadingDegrees =
                _smoothHeading(_compassHeadingDegrees!, rawHeading, 0.22);
          }
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isCompassAvailable = false;
          _compassHeadingDegrees = null;
        });
      },
    );
  }

  double _smoothHeading(double current, double target, double alpha) {
    var delta = target - current;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return (current + (delta * alpha) + 360) % 360;
  }

  Future<void> _initConnectivityMonitoring() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      final connected = await _hasUsableConnection(initial);

      if (mounted) {
        setState(() => _isOfflineMode = !connected);
      }

      if (!connected && mounted) {
        _showOfflineBanner();
      }

      _connectivitySubscription?.cancel();
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((results) async {
        final nowConnected = await _hasUsableConnection(results);
        final wasOffline = _isOfflineMode;

        if (!mounted) return;
        setState(() => _isOfflineMode = !nowConnected);

        if (!nowConnected) {
          _showOfflineBanner();
          return;
        }

        if (wasOffline) {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          await _syncPendingSessionsSilently();
        }
      });
    } catch (_) {
      // If connectivity plugin is unavailable, fallback to request/exception flow.
    }
  }

  Future<bool> _hasUsableConnection(List<ConnectivityResult> results) {
    return NetworkStatusService.hasUsableConnection(results);
  }

  void _showOfflineBanner() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Offline â€“ session saved locally. Will sync when online.',
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncPendingSessionsSilently() async {
    try {
      final supabase = context.read<SupabaseService>();
      await OfflineSessionService().syncPendingSessions(supabase);
    } catch (_) {
      // Keep queued sessions for later sync.
    }
  }

  Future<void> _primeCurrentLocation() async {
    try {
      final position = await context.read<MapService>().getCurrentPosition();
      if (!mounted || position == null) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
      });

      if (_mapBounds == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            17,
          );
        });
      }
    } catch (_) {
      // Leave the camera at the map bounds when GPS is unavailable.
    }
  }

  Future<void> _checkRawGnssSupport() async {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      if (!mounted) return;
      setState(() {
        _isRawGnssSupported = false;
        _isCheckingGnssSupport = false;
      });
      return;
    }

    bool supported = false;
    try {
      supported =
          await _gnssSupportChannel.invokeMethod<bool>('isRawGnssAvailable') ??
              false;
    } catch (_) {
      // Fallback when native channel is unavailable in this build.
      supported = false;
    }

    if (!supported) {
      supported = await _probeRawGnssStreamSupport();
    }

    if (!mounted) return;
    setState(() {
      _isRawGnssSupported = supported;
      _isCheckingGnssSupport = false;
    });
  }

  bool get _canUseHighPrecisionMode {
    // On web we cannot access native raw GNSS channels, but we can still
    // tighten sampling cadence/filters for better mobile-browser precision.
    return defaultTargetPlatform == TargetPlatform.android || kIsWeb;
  }

  Future<bool> _probeRawGnssStreamSupport() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final event = await _rawGnssEventChannel
          .receiveBroadcastStream()
          .first
          .timeout(const Duration(seconds: 2));
      return event != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadPropertyMapData() async {
    try {
      final supabase = context.read<SupabaseService>();
      final property = await supabase.fetchProperty(widget.propertyId);

      if (!mounted) return;

      if (property == null) {
        setState(() => _isLoadingMap = false);
        return;
      }

      final mapPoints = _extractGeoPoints(property.mapGeojson);
      final bounds = _buildBounds(mapPoints);
      final exclusionPolygons =
          _buildExclusionPolygons(property.exclusionZones);
      final exclusionRings = _extractExclusionRings(property.exclusionZones);
      final exclusionRingNotes =
          _extractExclusionRingNotes(property.exclusionZones);
      final outerBoundaryRing = _extractPolygonRing(property.outerBoundary);
      final outerBoundaryDashed = _buildDashedBoundary(outerBoundaryRing);
      final specialZones = _extractSpecialZones(property.specialZones);
      final sprayableZones =
          specialZones.where((zone) => zone.isSprayable).toList();
      final recommendedPath = _extractRecommendedPath(property.recommendedPath);

      setState(() {
        _property = property;
        _propertyBoundary = mapPoints;
        _mapBounds = bounds;
        _exclusionPolygons = exclusionPolygons;
        _exclusionRings = exclusionRings;
        _exclusionRingNotes = exclusionRingNotes;
        _outerBoundaryRing = outerBoundaryRing;
        _outerBoundaryDashed = outerBoundaryDashed;
        _specialZones = specialZones;
        _activeZoneSelection =
            sprayableZones.isEmpty ? '' : _allSprayableSelectionId;
        _recommendedPath = recommendedPath;
        _isLoadingMap = false;
      });

      if (bounds != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(28),
            ),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMap = false);
      _showSnackBar(
        AppSnackBar.error('Failed to load map data. Please try again.'),
      );
    }
  }

  void _startTracking() {
    final mapService = context.read<MapService>();
    _positionStream?.cancel();

    final intervalSeconds = _highAccuracyGnssEnabled ? 1 : 2;
    final distanceFilterMeters = _highAccuracyGnssEnabled ? 0 : 1;

    _positionStream = mapService
        .getPositionStream(
      intervalSeconds: intervalSeconds,
      distanceFilterMeters: distanceFilterMeters,
    )
        .listen(
      (Position position) {
        if (!_isTracking || _isSessionEnded) return;

        final currentPoint = LatLng(position.latitude, position.longitude);
        final inMapBounds = _isPointInsideMapBounds(currentPoint);
        final insideOuterBoundary = _isInsideOuterBoundary(currentPoint);
        final insideNoSprayZone = _isInsideAnyExclusion(currentPoint);
        final insideActiveZone = _isInsideActiveSprayZone(currentPoint);
        final now = DateTime.now();
        var recordedPoint = false;

        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _accuracy = position.accuracy;
          _updateGuidanceForPoint(currentPoint);

          if (inMapBounds &&
              insideOuterBoundary &&
              insideActiveZone &&
              !insideNoSprayZone &&
              _shouldRecordPathPoint(position)) {
            final heading = _effectiveReachHeadingDegrees();
            final pathPoint = TrackingPath(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              timestamp: now,
            );
            _paths.add(
              pathPoint,
            );
            _lastMovementAt = now;
            _autoPausedByInactivity = false;
            recordedPoint = true;

            if (_reachModeEnabled) {
              _reachSamples.add(
                _ReachSpraySample(
                  point: currentPoint,
                  headingDegrees: heading,
                  reachFeet: _swathWidthFeet,
                  timestamp: now,
                ),
              );
            }
          }
        });

        _updateLowProductWarningState();

        if (!recordedPoint) {
          final baseline = _lastMovementAt ?? _sessionStartedAt;
          if (now.difference(baseline).inSeconds >= _autoPauseInactivitySeconds) {
            _autoPauseForInactivity();
            return;
          }
        }

        if (_isOfflineMode) {
          _persistOfflineDraft();
        }

        if (!inMapBounds && !_outOfBoundsNoticeShown && _mapBounds != null) {
          _outOfBoundsNoticeShown = true;
          _showSnackBar(
            AppSnackBar.warning(
              'Current GPS position is outside the imported map area. Tracking points stay locked to the map boundary.',
            ),
          );
        }

        if (!insideOuterBoundary && _outerBoundaryRing.isNotEmpty) {
          final lastWarning = _lastNoSprayWarning;
          final shouldShow = lastWarning == null ||
              DateTime.now().difference(lastWarning).inSeconds >= 8;
          if (shouldShow) {
            _lastNoSprayWarning = DateTime.now();
            _showSnackBar(
              AppSnackBar.warning(
                'Outside the outer boundary. GPS points are ignored until you are back inside.',
              ),
            );
          }
        }

        if (!insideActiveZone && _sprayableZones().isNotEmpty) {
          final lastWarning = _lastNoSprayWarning;
          final shouldShow = lastWarning == null ||
              DateTime.now().difference(lastWarning).inSeconds >= 8;
          if (shouldShow) {
            _lastNoSprayWarning = DateTime.now();
            final active = _activeSprayableZone();
            final message = active != null
                ? 'Outside ${active.name}. Move back into the selected spray zone.'
                : 'Outside sprayable zones. Points are ignored until you re-enter one.';
            _showSnackBar(AppSnackBar.warning(message));
          }
        }

        if (insideNoSprayZone) {
          final lastWarning = _lastNoSprayWarning;
          final shouldShow = lastWarning == null ||
              DateTime.now().difference(lastWarning).inSeconds >= 8;
          if (shouldShow) {
            _lastNoSprayWarning = DateTime.now();
            final note = _exclusionNoteForPoint(currentPoint);
            if (note != null && note.isNotEmpty) {
              HapticFeedback.heavyImpact();
              _showSnackBar(
                AppSnackBar.warning(
                  'Entering exclusion zone: $note',
                ),
              );
            } else {
              _showSnackBar(
                AppSnackBar.warning(
                  'Entering a no-spray area. That point was not counted.',
                ),
              );
            }
          }
        }
      },
      onError: (e) {
        _handlePositionStreamError(e);
      },
    );
  }

  void _autoPauseForInactivity() {
    if (!_isTracking || _isSessionEnded) return;

    setState(() {
      _isTracking = false;
      _autoPausedByInactivity = true;
    });

    _showSnackBar(
      AppSnackBar.warning(
        'Auto-paused after no movement for 3 minutes. Tap Resume to continue.',
      ),
    );
    _persistOfflineDraft(force: true);
  }

  bool _shouldRecordPathPoint(Position position) {
    final accuracy =
        position.accuracy.isFinite ? position.accuracy.clamp(0.0, 100.0) : 100.0;

    // Reject fixes too noisy -- prevents stationary drift.
    if (accuracy > _maxAcceptedAccuracyMeters) return false;

    if (_paths.isEmpty) return true;

    final last = _paths.last;
    final movedMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      position.latitude,
      position.longitude,
    );

    final elapsedSeconds =
        math.max(1, DateTime.now().difference(last.timestamp).inSeconds);

    final speedFromSensor = (position.speed.isFinite && position.speed > 0)
        ? position.speed
        : 0.0;
    final speedMps = math.max(speedFromSensor, movedMeters / elapsedSeconds);

    final speedThreshold = _highAccuracyGnssEnabled
        ? _highPrecisionStationarySpeedThresholdMps
        : _stationarySpeedThresholdMps;
    final extraGuard = _highAccuracyGnssEnabled
        ? _highPrecisionStationaryExtraMovementMeters
        : _stationaryExtraMovementMeters;

    final likelyStationary = speedMps < speedThreshold;
    final noiseFloor = accuracy
        .clamp(_minAccuracyNoiseFloorMeters, _maxAccuracyNoiseFloorMeters)
        .toDouble();
    return movedMeters >= noiseFloor + (likelyStationary ? extraGuard : 0);
  }

  void _handlePositionStreamError(Object _) {
    final now = DateTime.now();
    if (_lastGpsErrorAt != null &&
        now.difference(_lastGpsErrorAt!).inSeconds < 12) return;
    _lastGpsErrorAt = now;
    _showSnackBar(AppSnackBar.error(
      'GPS signal unstable. Move to open sky or check location permissions.',
    ));
  }

  Future<void> _persistOfflineDraft({bool force = false}) async {
    if (!_isOfflineMode || _isSessionEnded) return;

    final now = DateTime.now();
    if (!force && _lastOfflineSnapshotAt != null) {
      final elapsed = now.difference(_lastOfflineSnapshotAt!).inSeconds;
      if (elapsed < 2) return;
    }

    _lastOfflineSnapshotAt = now;

    try {
      final supabase = context.read<SupabaseService>();
      final payload = <String, dynamic>{
        'id': widget.sessionId,
        'property_id': widget.propertyId,
        if (supabase.currentUserId != null) 'user_id': supabase.currentUserId,
        'start_time': _sessionStartedAt.toIso8601String(),
        'coverage_percent': _liveCoveragePercent(),
        'paths': _paths.map((p) => p.toJson()).toList(),
        'proof_pdf_url': null,
        'raw_gnss_data': _rawGnssObsContent,
        'swath_width_feet': _swathWidthFeet,
        'tank_capacity_gallons': _tankCapacityGallons,
        'application_rate_per_acre': _applicationRatePerAcre,
        'application_rate_unit': _applicationRateUnit,
        'chemical_cost_per_unit': _chemicalCostPerUnit,
        'overlap_threshold': widget.overlapThreshold,
        'created_at': _sessionStartedAt.toIso8601String(),
        // Context kept locally for resilient replay/debug.
        'exclusion_zones': _property?.exclusionZones,
        'recommended_path': _property?.recommendedPath,
        'outer_boundary': _property?.outerBoundary,
        'is_completed': false,
      };

      await OfflineSessionService().enqueueSession(payload);
    } catch (_) {
      // Continue tracking even if draft persistence fails.
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isSessionEnded) {
        timer.cancel();
        return;
      }

      if (_isTracking) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _togglePause() {
    if (_isSessionEnded) return;
    setState(() {
      _isTracking = !_isTracking;
      if (_isTracking) {
        _autoPausedByInactivity = false;
        _lastMovementAt ??= DateTime.now();
      }
    });
  }

  void _undoLast30Seconds() {
    if (_isSessionEnded || _paths.isEmpty) {
      return;
    }

    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    final before = _paths.length;

    setState(() {
      _paths.removeWhere((point) => point.timestamp.isAfter(cutoff));
      _reachSamples.removeWhere((sample) => sample.timestamp.isAfter(cutoff));
      _lastMovementAt = _paths.isEmpty ? null : _paths.last.timestamp;
      _autoPausedByInactivity = false;
    });

    final removed = before - _paths.length;
    if (removed <= 0) {
      _showSnackBar(
          AppSnackBar.info('Nothing to undo in the last 30 seconds.'));
      return;
    }

    _showSnackBar(
      AppSnackBar.success(
          'Undid $removed recent point${removed == 1 ? '' : 's'}.'),
    );
    _persistOfflineDraft(force: true);
  }

  Future<void> _onCancelJobPressed() async {
    if (_isSessionEnded) return;

    if (_cancelJobArmed) {
      setState(() {
        _cancelJobTapsRemaining = math.max(0, _cancelJobTapsRemaining - 1);
      });

      if (_cancelJobTapsRemaining <= 0) {
        await _abandonCurrentJob();
      }
      return;
    }

    _armCancelJobWindow();
    await _showCancelArmingDialog();
  }

  void _armCancelJobWindow() {
    _cancelJobTimer?.cancel();

    setState(() {
      _cancelJobArmed = true;
      _cancelJobTapsRemaining = 3;
      _cancelJobSecondsLeft = 10;
    });

    _cancelJobTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cancelJobSecondsLeft <= 1) {
        timer.cancel();
        _resetCancelJobArming(showTimeoutMessage: true);
        return;
      }

      setState(() {
        _cancelJobSecondsLeft -= 1;
      });
    });
  }

  void _resetCancelJobArming({bool showTimeoutMessage = false}) {
    _cancelJobTimer?.cancel();
    _cancelJobTimer = null;

    if (!mounted) return;

    final shouldCloseDialog = _cancelDialogOpen;
    setState(() {
      _cancelJobArmed = false;
      _cancelJobTapsRemaining = 3;
      _cancelJobSecondsLeft = 0;
    });

    if (shouldCloseDialog) {
      _cancelDialogOpen = false;
      Navigator.of(context, rootNavigator: true).maybePop();
    }

    if (showTimeoutMessage) {
      _showSnackBar(
        AppSnackBar.warning('Cancel request timed out. Session continues.'),
      );
    }
  }

  Future<void> _showCancelArmingDialog() async {
    if (!mounted) return;

    _cancelDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon this job?'),
        content: const Text(
          'Tap Cancel 3 more times in 10 seconds to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continue Tracking'),
          ),
        ],
      ),
    );

    _cancelDialogOpen = false;
  }

  Future<void> _abandonCurrentJob() async {
    _resetCancelJobArming(showTimeoutMessage: false);

    setState(() {
      _isTracking = false;
      _isSessionEnded = true;
      _paths.clear();
      _reachSamples.clear();
      _rawGnssObsLines.clear();
      _rawGnssObsContent = null;
    });

    await _positionStream?.cancel();
    await _stopRawGnssCapture();

    try {
      await OfflineSessionService().removePendingSession(widget.sessionId);
    } catch (_) {
      // Ignore local queue cleanup failures.
    }

    try {
      final supabase = context.read<SupabaseService>();
      await supabase.client
          .from('tracking_sessions')
          .delete()
          .eq('id', widget.sessionId);
    } catch (_) {
      // Ignore remote cleanup failures for abandon flow.
    }

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      AppSnackBar.success('Job abandoned'),
    );

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _setHighAccuracyGnssEnabled(bool enabled) async {
    if (!_canUseHighPrecisionMode) return;

    setState(() {
      _highAccuracyGnssEnabled = enabled;
      if (!enabled) {
        _rawGnssObsLines.clear();
        _rawGnssObsContent = null;
      }
    });

    // Restart the position stream so cadence/filter settings apply immediately.
    if (!_isSessionEnded) {
      _startTracking();
    }

    if (enabled && _isRawGnssSupported) {
      await _startRawGnssCapture();
    } else {
      await _stopRawGnssCapture();
    }
  }

  Future<void> _startRawGnssCapture() async {
    await _rawGnssSubscription?.cancel();
    _rawGnssSubscription = null;

    try {
      _rawGnssSubscription =
          _rawGnssEventChannel.receiveBroadcastStream().listen(
        (event) {
          final obsLine = _rawEventToObsLine(event);
          if (obsLine != null && obsLine.isNotEmpty) {
            _rawGnssObsLines.add(obsLine);
          }
        },
        onError: (_) {
          // Keep normal GPS behavior if raw GNSS stream is unavailable.
        },
      );
    } catch (_) {
      // Keep normal GPS behavior if raw GNSS stream is unavailable.
    }
  }

  Future<void> _stopRawGnssCapture() async {
    await _rawGnssSubscription?.cancel();
    _rawGnssSubscription = null;
  }

  String? _rawEventToObsLine(dynamic event) {
    if (event is! Map) return null;
    final data = Map<String, dynamic>.from(event);

    final time = (data['timeNanos'] ?? data['time'] ?? '').toString();
    final svid = (data['svid'] ?? data['satelliteId'] ?? '').toString();
    final cn0 = (data['cn0DbHz'] ?? data['cn0'] ?? '').toString();
    final pr =
        (data['pseudorangeMeters'] ?? data['pseudorange'] ?? '').toString();
    final doppler =
        (data['pseudorangeRateMetersPerSecond'] ?? data['doppler'] ?? '')
            .toString();
    final carrier =
        (data['carrierPhase'] ?? data['accumulatedDeltaRangeMeters'] ?? '')
            .toString();

    if (time.isEmpty && svid.isEmpty && cn0.isEmpty) return null;
    return '$time,$svid,$cn0,$pr,$doppler,$carrier';
  }

  String _buildObsContent() {
    final now = DateTime.now().toUtc();
    final header = <String>[
      '     3.03           OBSERVATION DATA    M                   RINEX VERSION / TYPE',
      'SprayMap Pro        GitHub Copilot                          PGM / RUN BY / DATE',
      'Use free RTKLIB software + nearby CORS data for 10-50 cm accuracy COMMENT',
      '${now.year.toString().padLeft(4)}${now.month.toString().padLeft(3)}${now.day.toString().padLeft(3)}${now.hour.toString().padLeft(3)}${now.minute.toString().padLeft(3)}${now.second.toString().padLeft(3)}     GPS         TIME OF FIRST OBS',
      '                                                            END OF HEADER',
      '# session_id=${widget.sessionId}',
      '# property_id=${widget.propertyId}',
      '# columns=time,svid,cn0DbHz,pseudorangeMeters,doppler,carrierPhase',
    ];

    if (_rawGnssObsLines.isEmpty) {
      return [...header, '# No raw GNSS events captured in this session.']
          .join('\n');
    }

    return [...header, ..._rawGnssObsLines].join('\n');
  }

  Future<void> _showPostProcessingInstructions(String filePath) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post-Processing Export Ready'),
        content: SelectableText(
          'Saved .obs file:\n$filePath\n\n'
          'Use free RTKLIB software + nearby CORS data for 10-50 cm accuracy.\n\n'
          'Steps:\n'
          '1. Copy the .obs file from app storage.\n'
          '2. Download nearby CORS/base station RINEX.\n'
          '3. Run RTKLIB post-processing (RTKPOST).\n'
          '4. Use corrected track for final reporting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportForPostProcessing() async {
    try {
      final content = _rawGnssObsContent ?? _buildObsContent();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}spraymap_${widget.sessionId}_$timestamp.obs',
      );

      await file.writeAsString(content, flush: true);
      await _showPostProcessingInstructions(file.path);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        AppSnackBar.error('Failed to export the .obs file.'),
      );
    }
  }

  Future<void> _showSessionCompleteActions({
    required double distance,
    required double coverage,
    bool savedOffline = false,
    bool isPartial = false,
  }) async {
    if (!mounted) return;

    final summary = _sessionSummary ?? _buildSessionSummary();
    final acresCovered = _estimatedUniqueCoverageAreaSqMeters() / 4046.8564224;

    final result = await Navigator.push<JobSummaryResult>(
      context,
      MaterialPageRoute(
        builder: (_) => JobSummaryScreen(
          propertyName: widget.propertyName,
          propertyId: widget.propertyId,
          sessionId: widget.sessionId,
          acresCovered: acresCovered,
          coveragePercent: coverage,
          timeTakenSeconds: _elapsedSeconds,
          overlapPercent: summary.overlapPercent,
          estimatedChemicalUsed: summary.estimatedProductUsed,
          potentialSavings: summary.overlapPercent > 15
              ? summary.overlapSavingsEstimate
              : null,
          applicationRateUnit: summary.applicationRateUnit,
        ),
      ),
    );

    if (!mounted || result == null) return;

    final mergedChecklist =
        Map<String, dynamic>.from(summary.checklistData ?? <String, dynamic>{});
    if (result.notes.isNotEmpty) {
      mergedChecklist['job_summary_notes'] = result.notes;
    }
    if (result.photoUrl != null && result.photoUrl!.isNotEmpty) {
      mergedChecklist['job_summary_photo_url'] = result.photoUrl;
    }

    if (mergedChecklist.isNotEmpty) {
      _sessionSummary = summary.copyWith(checklistData: mergedChecklist);
      if (!_isOfflineMode) {
        try {
          final supabase = context.read<SupabaseService>();
          await supabase.updateSessionChecklistData(
            sessionId: widget.sessionId,
            checklistData: mergedChecklist,
          );
        } catch (_) {
          if (mounted) {
            _showSnackBar(
              AppSnackBar.warning(
                'Summary notes/photo could not sync yet. They will be included in PDF only.',
              ),
            );
          }
        }
      }
    }

    if (savedOffline && mounted) {
      _showSnackBar(
        AppSnackBar.warning(
          'Offline mode: session stored locally. Sync from dashboard when online.',
        ),
      );
    }

    if (result.discard) {
      Navigator.pop(context);
      return;
    }

    if (!result.generatePdf) {
      Navigator.pop(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          sessionId: widget.sessionId,
          propertyId: widget.propertyId,
          propertyName: widget.propertyName,
          paths: _paths,
          coverage: coverage,
          distance: distance,
          acresCovered: acresCovered,
          timeTakenSeconds: _elapsedSeconds,
          summaryNotes: result.notes,
          summaryPhotoUrl: result.photoUrl,
          overlapPercent: summary.overlapPercent,
          estimatedChemicalUsed: summary.estimatedProductUsed,
          potentialSavings: summary.overlapPercent > 15
              ? summary.overlapSavingsEstimate
              : null,
          applicationRateUnit: summary.applicationRateUnit,
        ),
      ),
    ).then((_) => Navigator.pop(context));
  }
Future<void> _stopTracking() async {
    setState(() {
      _isTracking = false;
      _isSessionEnded = true;
    });

    await _positionStream?.cancel();
    await _stopRawGnssCapture();

    if (_isOfflineMode) {
      await _saveSessionOfflineAndComplete();
      return;
    }

    try {
      final supabase = context.read<SupabaseService>();
      final mapService = context.read<MapService>();

      final distance = mapService.calculateDistanceMiles(_paths);
      final coverage = _liveCoveragePercent();
      final rawObs = _highAccuracyGnssEnabled ? _buildObsContent() : null;
      final summary = _buildSessionSummary();
      _rawGnssObsContent = rawObs;
      _sessionSummary = summary;

      await supabase.updateSessionPaths(widget.sessionId, _paths);
      await supabase.completeTrackingSession(
        sessionId: widget.sessionId,
        coveragePercent: coverage,
        rawGnssData: rawObs,
        extraData: summary.toSessionExtraData(),
      );

      if (!mounted) return;

      await _showSessionCompleteActions(distance: distance, coverage: coverage);
    } catch (e) {
      final supabase = context.read<SupabaseService>();
      final mapService = context.read<MapService>();
      final offline = OfflineSessionService();

      final distance = mapService.calculateDistanceMiles(_paths);
      final coverage = _liveCoveragePercent();
      final rawObs = _highAccuracyGnssEnabled ? _buildObsContent() : null;
      final summary = _buildSessionSummary();
      _rawGnssObsContent = rawObs;
      _sessionSummary = summary;

      final payload = <String, dynamic>{
        'id': widget.sessionId,
        'property_id': widget.propertyId,
        if (supabase.currentUserId != null) 'user_id': supabase.currentUserId,
        'start_time': _sessionStartedAt.toIso8601String(),
        'end_time': DateTime.now().toIso8601String(),
        'coverage_percent': coverage,
        'paths': _paths.map((p) => p.toJson()).toList(),
        'proof_pdf_url': null,
        'raw_gnss_data': rawObs,
        'swath_width_feet': _swathWidthFeet,
        'tank_capacity_gallons': _tankCapacityGallons,
        'application_rate_per_acre': _applicationRatePerAcre,
        'application_rate_unit': _applicationRateUnit,
        'chemical_cost_per_unit': _chemicalCostPerUnit,
        'overlap_threshold': widget.overlapThreshold,
        'created_at': _sessionStartedAt.toIso8601String(),
        ...summary.toSessionExtraData(),
      };

      await offline.enqueueSession(payload);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: const Text('Offline - session saved locally'),
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );

      await _showSessionCompleteActions(
        distance: distance,
        coverage: coverage,
        savedOffline: true,
      );
    }
  }

  Future<void> _saveSessionOfflineAndComplete() async {
    final supabase = context.read<SupabaseService>();
    final mapService = context.read<MapService>();
    final offline = OfflineSessionService();

    final distance = mapService.calculateDistanceMiles(_paths);
    final coverage = _liveCoveragePercent();
    final rawObs = _highAccuracyGnssEnabled ? _buildObsContent() : null;
    final summary = _buildSessionSummary();
    _rawGnssObsContent = rawObs;
    _sessionSummary = summary;

    final payload = <String, dynamic>{
      'id': widget.sessionId,
      'property_id': widget.propertyId,
      if (supabase.currentUserId != null) 'user_id': supabase.currentUserId,
      'start_time': _sessionStartedAt.toIso8601String(),
      'end_time': DateTime.now().toIso8601String(),
      'coverage_percent': coverage,
      'paths': _paths.map((p) => p.toJson()).toList(),
      'proof_pdf_url': null,
      'raw_gnss_data': rawObs,
      'swath_width_feet': _swathWidthFeet,
        'tank_capacity_gallons': _tankCapacityGallons,
        'application_rate_per_acre': _applicationRatePerAcre,
        'application_rate_unit': _applicationRateUnit,
        'chemical_cost_per_unit': _chemicalCostPerUnit,
        'overlap_threshold': widget.overlapThreshold,
        'created_at': _sessionStartedAt.toIso8601String(),
      'exclusion_zones': _property?.exclusionZones,
      'recommended_path': _property?.recommendedPath,
      'outer_boundary': _property?.outerBoundary,
      'is_completed': true,
      ...summary.toSessionExtraData(),
    };

    await offline.enqueueSession(payload);

    if (!mounted) return;

    _showOfflineBanner();

    await _showSessionCompleteActions(
      distance: distance,
      coverage: coverage,
      savedOffline: true,
    );
  }

  Future<void> _savePartialSession() async {
    setState(() {
      _isTracking = false;
      _isSessionEnded = true;
    });

    await _positionStream?.cancel();
    await _stopRawGnssCapture();

    final supabase = context.read<SupabaseService>();
    final mapService = context.read<MapService>();
    final offline = OfflineSessionService();
    final distance = mapService.calculateDistanceMiles(_paths);
    final coverage = _liveCoveragePercent();
    final rawObs = _highAccuracyGnssEnabled ? _buildObsContent() : null;
    final summary = _buildSessionSummary(
      partialCompletionReason: 'Low product warning',
    );
    _sessionSummary = summary;

    try {
      if (!_isOfflineMode) {
        await supabase.updateSessionPaths(widget.sessionId, _paths);
        await supabase.completeTrackingSession(
          sessionId: widget.sessionId,
          coveragePercent: coverage,
          rawGnssData: rawObs,
          extraData: summary.toSessionExtraData(),
        );
      } else {
        await offline.enqueueSession({
          'id': widget.sessionId,
          'property_id': widget.propertyId,
          if (supabase.currentUserId != null) 'user_id': supabase.currentUserId,
          'start_time': _sessionStartedAt.toIso8601String(),
          'end_time': DateTime.now().toIso8601String(),
          'coverage_percent': coverage,
          'paths': _paths.map((p) => p.toJson()).toList(),
          'proof_pdf_url': null,
          'raw_gnss_data': rawObs,
          'swath_width_feet': _swathWidthFeet,
        'tank_capacity_gallons': _tankCapacityGallons,
        'application_rate_per_acre': _applicationRatePerAcre,
        'application_rate_unit': _applicationRateUnit,
        'chemical_cost_per_unit': _chemicalCostPerUnit,
        'overlap_threshold': widget.overlapThreshold,
        'created_at': _sessionStartedAt.toIso8601String(),
          'is_completed': true,
          ...summary.toSessionExtraData(),
        });
      }

      if (!mounted) return;
      await _showSessionCompleteActions(
        distance: distance,
        coverage: coverage,
        savedOffline: _isOfflineMode,
        isPartial: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        AppSnackBar.error('Could not save the partial session.'),
      );
    }
  }

  Future<Map<String, dynamic>?> _showTreatmentChecklistDialog() async {
    var coveredBareSoil = false;
    var avoidedGreenAreas = false;
    var noProductLeft = false;
    final notesController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Treatment Complete Checklist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: coveredBareSoil,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Covered all intended bare soil'),
                  onChanged: (value) =>
                      setDialogState(() => coveredBareSoil = value ?? false),
                ),
                CheckboxListTile(
                  value: avoidedGreenAreas,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Avoided all green areas'),
                  onChanged: (value) =>
                      setDialogState(() => avoidedGreenAreas = value ?? false),
                ),
                CheckboxListTile(
                  value: noProductLeft,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('No product left in tank'),
                  onChanged: (value) =>
                      setDialogState(() => noProductLeft = value ?? false),
                ),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'skipped': true,
                'notes': notesController.text.trim(),
              }),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: coveredBareSoil && avoidedGreenAreas && noProductLeft
                  ? () => Navigator.pop(context, {
                        'skipped': false,
                        'covered_bare_soil': coveredBareSoil,
                        'avoided_green_areas': avoidedGreenAreas,
                        'no_product_left': noProductLeft,
                        'notes': notesController.text.trim(),
                        'completed_at': DateTime.now().toIso8601String(),
                      })
                  : null,
              child: const Text('Save Checklist'),
            ),
          ],
        ),
      ),
    );

    notesController.dispose();
    return result;
  }

  _SessionSummary _buildSessionSummary({String? partialCompletionReason}) {
    final sprayedAreaSqMeters = _estimatedSprayedAreaSqMeters();
    final uniqueCoverageSqMeters = _estimatedUniqueCoverageAreaSqMeters();
    final overlapSqMeters =
        math.max(0, sprayedAreaSqMeters - uniqueCoverageSqMeters);
    final overlapPercent = sprayedAreaSqMeters <= 0
        ? 0.0
        : (overlapSqMeters / sprayedAreaSqMeters) * 100;
    final sprayedAreaAcres = sprayedAreaSqMeters / 4046.8564224;
    final estimatedProductUsed = _applicationRatePerAcre == null
        ? null
        : sprayedAreaAcres * _applicationRatePerAcre!;
    final remainingProduct =
        (_tankCapacityGallons == null || estimatedProductUsed == null)
            ? null
            : _tankCapacityGallons! - estimatedProductUsed;
    final overlapSavingsEstimate = (_chemicalCostPerUnit == null ||
            _applicationRatePerAcre == null)
        ? null
        : (overlapSqMeters / 4046.8564224) *
            _applicationRatePerAcre! *
            _chemicalCostPerUnit!;

    return _SessionSummary(
      overlapPercent: overlapPercent.clamp(0.0, 100.0),
      overlapSavingsEstimate: overlapSavingsEstimate == null
          ? null
          : math.max(0, overlapSavingsEstimate),
      overlapThreshold: widget.overlapThreshold,
      tankCapacityGallons: _tankCapacityGallons,
      estimatedProductUsed: estimatedProductUsed,
      remainingProduct: remainingProduct,
      applicationRateUnit: _applicationRateUnit,
      partialCompletionReason: partialCompletionReason,
      checklistData: _sessionSummary?.checklistData,
    );
  }

  double _estimatedSprayedAreaSqMeters() {
    if (_reachModeEnabled) {
      return _reachCoveredAreaSqMeters();
    }
    if (_paths.length < 2) return 0;
    return (_distanceMiles() * 1609.34) * (_swathWidthFeet * 0.3048);
  }

  double _estimatedUniqueCoverageAreaSqMeters() {
    if (_reachModeEnabled) {
      final polygons = _reachCoveragePolygons();
      final total = polygons.fold<double>(
        0,
        (sum, polygon) => sum + _polygonAreaSqMeters(polygon),
      );
      return math.min(total, _estimatedSprayedAreaSqMeters());
    }

    final coveragePoints = _coveragePolygonPoints();
    if (coveragePoints.length < 3) return 0;
    return _polygonAreaSqMeters(coveragePoints);
  }

  double? _remainingProductPercent() {
    final summary = _sessionSummary ?? _buildSessionSummary();
    if (summary.tankCapacityGallons == null ||
        summary.remainingProduct == null ||
        summary.tankCapacityGallons! <= 0) {
      return null;
    }
    return (summary.remainingProduct! / summary.tankCapacityGallons!) * 100;
  }

  void _updateLowProductWarningState() {
    final summary = _sessionSummary ?? _buildSessionSummary();
    final tank = summary.tankCapacityGallons;
    final remaining = summary.remainingProduct;

    if (tank == null || remaining == null || tank <= 0) {
      if (_activeLowProductThreshold != null) {
        setState(() {
          _activeLowProductThreshold = null;
        });
      }
      return;
    }

    final normalizedRemaining = remaining.clamp(0.0, tank);
    final percent = (normalizedRemaining / tank) * 100;

    int? threshold;
    if (percent <= 5) {
      threshold = 5;
    } else if (percent <= 10) {
      threshold = 10;
    } else if (percent <= 20) {
      threshold = 20;
    }

    if (_activeLowProductThreshold != threshold) {
      setState(() {
        _activeLowProductThreshold = threshold;
      });
    }

    if (threshold != null && !_triggeredLowProductThresholds.contains(threshold)) {
      _triggeredLowProductThresholds.add(threshold);
      _showSnackBar(
        AppSnackBar.warning(
          'Low product - ~${normalizedRemaining.toStringAsFixed(1)} gal left',
        ),
      );
    }
  }

  bool _isPointInsideMapBounds(LatLng point) {
    final bounds = _mapBounds;
    if (bounds == null) return true;

    final latPadding = (bounds.north - bounds.south).abs() * 0.05;
    final lngPadding = (bounds.east - bounds.west).abs() * 0.05;

    return point.latitude >= bounds.south - latPadding &&
        point.latitude <= bounds.north + latPadding &&
        point.longitude >= bounds.west - lngPadding &&
        point.longitude <= bounds.east + lngPadding;
  }

  List<LatLng> _extractGeoPoints(Map<String, dynamic>? geoJson) {
    if (geoJson == null) return [];
    final points = <LatLng>[];

    void collect(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('coordinates')) {
          collect(node['coordinates']);
        }
        if (node.containsKey('features') && node['features'] is List) {
          for (final feature in node['features'] as List) {
            collect(feature);
          }
        }
        if (node.containsKey('geometry')) {
          collect(node['geometry']);
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
          collect(child);
        }
      }
    }

    collect(geoJson);
    return points;
  }

  LatLngBounds? _buildBounds(List<LatLng> points) {
    if (points.isEmpty) return null;

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

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  List<Polygon> _buildExclusionPolygons(List<Map<String, dynamic>>? zones) {
    if (zones == null || zones.isEmpty) return [];

    final polygons = <Polygon>[];

    for (final zone in zones) {
      final polygonGeoJson = _extractExclusionPolygonGeoJson(zone);
      if (polygonGeoJson == null) continue;
      final coordinates = polygonGeoJson['coordinates'];
      if (coordinates is! List ||
          coordinates.isEmpty ||
          coordinates.first is! List) {
        continue;
      }

      final ring = coordinates.first as List;
      final points = <LatLng>[];

      for (final vertex in ring) {
        if (vertex is List && vertex.length >= 2) {
          final lng = (vertex[0] as num).toDouble();
          final lat = (vertex[1] as num).toDouble();
          points.add(LatLng(lat, lng));
        }
      }

      if (points.length >= 3) {
        polygons.add(
          Polygon(
            points: points,
            color: Colors.red.withValues(alpha: 0.28),
            borderColor: Colors.red,
            borderStrokeWidth: 2,
            isFilled: true,
          ),
        );
      }
    }

    return polygons;
  }

  List<List<LatLng>> _extractExclusionRings(List<Map<String, dynamic>>? zones) {
    final ringNotes = _extractExclusionRingNotes(zones);
    if (ringNotes.isEmpty) return const [];
    return ringNotes.map((entry) => entry.key).toList(growable: false);
  }

  List<MapEntry<List<LatLng>, String?>> _extractExclusionRingNotes(
    List<Map<String, dynamic>>? zones,
  ) {
    if (zones == null || zones.isEmpty) return const [];

    final ringNotes = <MapEntry<List<LatLng>, String?>>[];
    for (final zone in zones) {
      final polygonGeoJson = _extractExclusionPolygonGeoJson(zone);
      if (polygonGeoJson == null) continue;

      final ring = _extractPolygonRing(polygonGeoJson);
      if (ring.length < 3) continue;

      String? note;
      final rawNote = zone['note'];
      if (rawNote != null) {
        final normalized = rawNote.toString().trim();
        if (normalized.isNotEmpty) {
          note = normalized;
        }
      }

      ringNotes.add(MapEntry(ring, note));
    }

    return ringNotes;
  }

  Map<String, dynamic>? _extractExclusionPolygonGeoJson(
    Map<String, dynamic>? zone,
  ) {
    if (zone == null) return null;

    if (zone['type'] == 'Polygon') {
      return zone;
    }

    final polygonNode = zone['polygon'];
    if (polygonNode is Map) {
      final polygonGeoJson = Map<String, dynamic>.from(polygonNode);
      if (polygonGeoJson['type'] == 'Polygon') {
        return polygonGeoJson;
      }
    }

    return null;
  }

  List<LatLng> _extractPolygonRing(Map<String, dynamic>? geoJsonPolygon) {
    if (geoJsonPolygon == null || geoJsonPolygon['type'] != 'Polygon') {
      return const [];
    }

    final coordinates = geoJsonPolygon['coordinates'];
    if (coordinates is! List ||
        coordinates.isEmpty ||
        coordinates.first is! List) {
      return const [];
    }

    final ringCoords = coordinates.first as List;
    final ring = <LatLng>[];
    for (final vertex in ringCoords) {
      if (vertex is List && vertex.length >= 2) {
        ring.add(
          LatLng((vertex[1] as num).toDouble(), (vertex[0] as num).toDouble()),
        );
      }
    }
    return ring;
  }

  List<Polyline> _buildDashedBoundary(List<LatLng> ring) {
    if (ring.length < 2) return const [];

    final closed = List<LatLng>.from(ring);
    if (!_samePoint(closed.first, closed.last)) {
      closed.add(closed.first);
    }

    final dashed = <Polyline>[];
    for (var i = 0; i < closed.length - 1; i++) {
      if (i.isEven) {
        dashed.add(
          Polyline(
            points: [closed[i], closed[i + 1]],
            strokeWidth: 3,
            color: const Color(0xFFFBC02D),
          ),
        );
      }
    }
    return dashed;
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-8 &&
        (a.longitude - b.longitude).abs() < 1e-8;
  }

  bool _isInsideOuterBoundary(LatLng point) {
    if (_outerBoundaryRing.length < 3) return true;
    return _pointInPolygon(point, _outerBoundaryRing);
  }

  bool _isInsideAnyExclusion(LatLng point) {
    for (final entry in _exclusionRingNotes) {
      if (_pointInPolygon(point, entry.key)) return true;
    }
    return false;
  }

  List<_SpecialZoneOverlay> _extractSpecialZones(
    List<Map<String, dynamic>>? zones,
  ) {
    if (zones == null || zones.isEmpty) return const [];

    final parsed = <_SpecialZoneOverlay>[];
    for (final zone in zones) {
      final polygonGeoJson = _extractExclusionPolygonGeoJson(zone);
      if (polygonGeoJson == null) continue;

      final ring = _extractPolygonRing(polygonGeoJson);
      if (ring.length < 3) continue;

      final id = (zone['id'] ?? zone['name'] ?? zone['label'] ?? ring.hashCode)
          .toString();
      final name =
          (zone['name'] ?? zone['label'] ?? 'Unnamed Zone').toString().trim();
      final type =
          (zone['type'] ?? zone['zone_type'] ?? 'sprayable').toString().trim();
      final color =
          _colorFromHex(zone['color']?.toString()) ?? const Color(0xFF2E7D32);
      final sprayableRaw = zone['sprayable'];
      final isSprayable = sprayableRaw is bool
          ? sprayableRaw
          : (type == 'sprayable' || type == 'caution');

      parsed.add(
        _SpecialZoneOverlay(
          id: id,
          name: name.isEmpty ? 'Unnamed Zone' : name,
          type: type.isEmpty ? 'sprayable' : type,
          color: color,
          isSprayable: isSprayable,
          ring: ring,
        ),
      );
    }

    return parsed;
  }

  List<_SpecialZoneOverlay> _sprayableZones() {
    return _specialZones
        .where((zone) => zone.isSprayable)
        .toList(growable: false);
  }

  _SpecialZoneOverlay? _activeSprayableZone() {
    if (_activeZoneSelection.isEmpty ||
        _activeZoneSelection == _allSprayableSelectionId) {
      return null;
    }

    for (final zone in _specialZones) {
      if (zone.id == _activeZoneSelection && zone.isSprayable) {
        return zone;
      }
    }
    return null;
  }

  bool _isInsideActiveSprayZone(LatLng point) {
    final sprayable = _sprayableZones();
    if (sprayable.isEmpty) {
      return true;
    }

    final active = _activeSprayableZone();
    if (active != null) {
      return _pointInPolygon(point, active.ring);
    }

    for (final zone in sprayable) {
      if (_pointInPolygon(point, zone.ring)) {
        return true;
      }
    }
    return false;
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  String? _exclusionNoteForPoint(LatLng point) {
    for (final entry in _exclusionRingNotes) {
      final ring = entry.key;
      if (ring.length >= 3 && _pointInPolygon(point, ring)) {
        final note = entry.value?.trim();
        if (note != null && note.isNotEmpty) {
          return note;
        }
        return null;
      }
    }
    return null;
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    try {
      final closed = List<LatLng>.from(polygon);
      if (!_samePoint(closed.first, closed.last)) {
        closed.add(closed.first);
      }

      final ring = closed
          .map((p) => turf.Position.of([p.longitude, p.latitude]))
          .toList(growable: false);
      final geo = turf.Polygon(coordinates: [ring]);
      return turf.booleanPointInPolygon(
        turf.Position.of([point.longitude, point.latitude]),
        geo,
      );
    } catch (_) {
      return false;
    }
  }

  List<LatLng> _extractRecommendedPath(dynamic rawPath) {
    if (rawPath == null) return const [];

    List<dynamic>? coordinateNodes;

    if (rawPath is Map) {
      final map = Map<String, dynamic>.from(rawPath);
      final type = (map['type'] ?? '').toString();

      if (type == 'LineString' && map['coordinates'] is List) {
        coordinateNodes = map['coordinates'] as List;
      } else if (type == 'FeatureCollection' && map['features'] is List) {
        final features = map['features'] as List;
        for (final feature in features) {
          if (feature is Map && feature['geometry'] is Map) {
            final geometry =
                Map<String, dynamic>.from(feature['geometry'] as Map);
            if ((geometry['type'] ?? '') == 'LineString' &&
                geometry['coordinates'] is List) {
              coordinateNodes = geometry['coordinates'] as List;
              break;
            }
          }
        }
      }
    } else if (rawPath is List) {
      coordinateNodes = rawPath;
    }

    if (coordinateNodes == null || coordinateNodes.isEmpty) return const [];

    final points = <LatLng>[];
    for (final node in coordinateNodes) {
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        final latValue = map['lat'] ?? map['latitude'];
        final lngValue = map['lng'] ?? map['lon'] ?? map['longitude'];
        if (latValue is num && lngValue is num) {
          points.add(LatLng(latValue.toDouble(), lngValue.toDouble()));
        }
      } else if (node is List && node.length >= 2) {
        final a = node[0];
        final b = node[1];
        if (a is num && b is num) {
          final first = a.toDouble();
          final second = b.toDouble();
          if (first.abs() <= 90 && second.abs() <= 180) {
            points.add(LatLng(first, second));
          } else {
            points.add(LatLng(second, first));
          }
        }
      }
    }

    return points;
  }

  void _updateGuidanceForPoint(LatLng currentPoint) {
    if (_recommendedPath.length < 2) {
      _guidanceSegmentIndex = -1;
      _distanceToLineMeters = 0;
      _guidanceStatus = 'No guidance path available';
      _displayArrowRadians = 0;
      _guidanceDeviationWarning = false;
      return;
    }

    var bestSegment = 0;
    var minDistance = double.infinity;
    var bestSignedOffset = 0.0;

    for (var i = 0; i < _recommendedPath.length - 1; i++) {
      final a = _recommendedPath[i];
      final b = _recommendedPath[i + 1];
      final metrics = _pointToSegmentMetrics(currentPoint, a, b);
      if (metrics.distanceMeters < minDistance) {
        minDistance = metrics.distanceMeters;
        bestSegment = i;
        bestSignedOffset = metrics.signedOffsetMeters;
      }
    }

    final swathHalfMeters = (_swathWidthFeet * 0.3048) / 2;
    String driftStatus;
    if (minDistance <= swathHalfMeters) {
      driftStatus = 'On path';
    } else if (bestSignedOffset > 0) {
      driftStatus = 'Drifting left';
    } else {
      driftStatus = 'Drifting right';
    }

    final start = _recommendedPath[bestSegment];
    final end = _recommendedPath[bestSegment + 1];
    final targetArrow = _bearingRadians(start, end);
    final smoothedArrow = _smoothAngle(_displayArrowRadians, targetArrow, 0.22);

    final offLine = minDistance > swathHalfMeters;
    if (offLine && _viewMode == TrackingViewMode.guidance) {
      _triggerDeviationWarning();
    }

    _guidanceSegmentIndex = bestSegment;
    _distanceToLineMeters = minDistance;
    _guidanceStatus = driftStatus;
    _displayArrowRadians = smoothedArrow;
    _guidanceDeviationWarning = offLine;
  }

  double _smoothAngle(double current, double target, double alpha) {
    var delta = target - current;
    while (delta > math.pi) delta -= 2 * math.pi;
    while (delta < -math.pi) delta += 2 * math.pi;
    return current + (delta * alpha);
  }

  void _triggerDeviationWarning() {
    final now = DateTime.now();
    final canPulse = _lastDeviationHaptic == null ||
        now.difference(_lastDeviationHaptic!).inMilliseconds >= 1400;
    if (!canPulse) return;

    _lastDeviationHaptic = now;
    HapticFeedback.heavyImpact();

    _deviationFlashTimer?.cancel();
    _showDeviationFlash = true;
    _deviationFlashTimer = Timer(const Duration(milliseconds: 170), () {
      if (!mounted) return;
      setState(() => _showDeviationFlash = false);
    });
  }

  ({double distanceMeters, double signedOffsetMeters}) _pointToSegmentMetrics(
    LatLng point,
    LatLng a,
    LatLng b,
  ) {
    final refLat = a.latitude;
    final refLng = a.longitude;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(refLat * math.pi / 180);

    final bx = (b.longitude - refLng) * metersPerDegLng;
    final by = (b.latitude - refLat) * metersPerDegLat;
    final px = (point.longitude - refLng) * metersPerDegLng;
    final py = (point.latitude - refLat) * metersPerDegLat;

    final segmentLengthSq = (bx * bx) + (by * by);
    if (segmentLengthSq < 1e-6) {
      final dist = math.sqrt((px * px) + (py * py));
      return (distanceMeters: dist, signedOffsetMeters: 0);
    }

    final t = ((px * bx) + (py * by)) / segmentLengthSq;
    final clampedT = t.clamp(0.0, 1.0);
    final projX = bx * clampedT;
    final projY = by * clampedT;

    final dx = px - projX;
    final dy = py - projY;
    final dist = math.sqrt((dx * dx) + (dy * dy));

    final cross = (bx * py) - (by * px);
    final signed = cross >= 0 ? dist : -dist;

    return (distanceMeters: dist, signedOffsetMeters: signed);
  }

  double _bearingRadians(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  List<Polyline> _buildGuidanceSegmentDashedPolylines() {
    if (_guidanceSegmentIndex < 0 ||
        _guidanceSegmentIndex >= _recommendedPath.length - 1) {
      return const [];
    }

    final start = _recommendedPath[_guidanceSegmentIndex];
    final end = _recommendedPath[_guidanceSegmentIndex + 1];
    const dashCount = 14;
    final lines = <Polyline>[];

    for (var i = 0; i < dashCount; i++) {
      if (i.isOdd) continue;
      final t1 = i / dashCount;
      final t2 = (i + 1) / dashCount;
      final p1 = LatLng(
        start.latitude + (end.latitude - start.latitude) * t1,
        start.longitude + (end.longitude - start.longitude) * t1,
      );
      final p2 = LatLng(
        start.latitude + (end.latitude - start.latitude) * t2,
        start.longitude + (end.longitude - start.longitude) * t2,
      );

      lines.add(
        Polyline(
          points: [p1, p2],
          strokeWidth: 7,
          color: const Color(0xFF1565C0),
        ),
      );
    }

    return lines;
  }

  double _effectiveReachHeadingDegrees() {
    if (_isCompassAvailable && _compassHeadingDegrees != null) {
      return (_compassHeadingDegrees! + _manualHeadingOffsetDegrees + 360) %
          360;
    }
    return (_manualHeadingDegrees + 360) % 360;
  }

  void _nudgeReachHeading(double deltaDegrees) {
    setState(() {
      if (_isCompassAvailable && _compassHeadingDegrees != null) {
        _manualHeadingOffsetDegrees =
            (_manualHeadingOffsetDegrees + deltaDegrees + 360) % 360;
      } else {
        _manualHeadingDegrees =
            (_manualHeadingDegrees + deltaDegrees + 360) % 360;
      }
    });
  }

  String _headingDirectionLabel(double degrees) {
    final normalized = (degrees + 360) % 360;
    if (normalized >= 337.5 || normalized < 22.5) return 'N';
    if (normalized < 67.5) return 'NE';
    if (normalized < 112.5) return 'E';
    if (normalized < 157.5) return 'SE';
    if (normalized < 202.5) return 'S';
    if (normalized < 247.5) return 'SW';
    if (normalized < 292.5) return 'W';
    return 'NW';
  }

  ({List<LatLng> raw, List<LatLng> clipped}) _buildReachFan(
    LatLng center,
    double headingDegrees,
    double reachFeet,
  ) {
    const fanSpanDegrees = 180.0;
    const fanSteps = 18;

    final radiusMeters = reachFeet * 0.3048;
    final raw = <LatLng>[center];

    final halfSpan = fanSpanDegrees / 2;
    for (var i = 0; i <= fanSteps; i++) {
      final t = i / fanSteps;
      final bearing = (headingDegrees - halfSpan) + (fanSpanDegrees * t);
      raw.add(const Distance().offset(center, radiusMeters, bearing));
    }
    raw.add(center);

    final clipped = raw.where((p) {
      final insideOuter = _outerBoundaryRing.length < 3
          ? true
          : _pointInPolygon(p, _outerBoundaryRing);
      if (!insideOuter) return false;
      if (!_isInsideActiveSprayZone(p)) return false;

      for (final ring in _exclusionRings) {
        if (ring.length >= 3 && _pointInPolygon(p, ring)) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);

    return (raw: raw, clipped: clipped);
  }

  List<List<LatLng>> _reachCoveragePolygons() {
    final polygons = <List<LatLng>>[];
    for (final sample in _reachSamples) {
      final fan = _buildReachFan(
        sample.point,
        sample.headingDegrees,
        sample.reachFeet,
      );
      if (fan.clipped.length >= 3) {
        polygons.add(fan.clipped);
      }
    }

    if (_latitude != 0 || _longitude != 0) {
      final liveFan = _buildReachFan(
        LatLng(_latitude, _longitude),
        _effectiveReachHeadingDegrees(),
        _swathWidthFeet,
      );
      if (liveFan.clipped.length >= 3) {
        polygons.add(liveFan.clipped);
      }
    }

    return polygons;
  }

  double _reachCoveredAreaSqMeters() {
    if (_reachSamples.isEmpty) return 0;

    var totalArea = 0.0;
    for (final sample in _reachSamples) {
      final fan = _buildReachFan(
        sample.point,
        sample.headingDegrees,
        sample.reachFeet,
      );
      final clippedRatio = fan.raw.isEmpty
          ? 0.0
          : (fan.clipped.length / fan.raw.length).clamp(0.0, 1.0);
      final radiusMeters = sample.reachFeet * 0.3048;
      final semiCircleArea = 0.5 * math.pi * radiusMeters * radiusMeters;
      totalArea += semiCircleArea * clippedRatio;
    }

    return totalArea;
  }

  List<LatLng> _coveragePolygonPoints() {
    if (_reachModeEnabled) {
      return const [];
    }

    final mapService = context.read<MapService>();
    final raw = mapService.generateCoveragePolygon(_paths, _swathWidthFeet);
    final points = raw.map((p) => LatLng(p[0], p[1])).toList();

    final clipped = points.where((p) {
      final insideOuter = _outerBoundaryRing.length < 3
          ? true
          : _pointInPolygon(p, _outerBoundaryRing);
      if (!insideOuter) return false;

      if (!_isInsideActiveSprayZone(p)) return false;

      for (final ring in _exclusionRings) {
        if (ring.length >= 3 && _pointInPolygon(p, ring)) {
          return false;
        }
      }

      return true;
    }).toList();

    if (clipped.length < 3) return const [];

    if (!_samePoint(clipped.first, clipped.last)) {
      clipped.add(clipped.first);
    }

    return clipped;
  }

  List<_OverlapHeatCell> _buildOverlapHeatCells() {
    if (_paths.length < 3) return const [];

    final gridMeters = math.max(0.6, _swathWidthFeet * 0.3048 * 0.55);
    final cells = <String, _OverlapHeatCell>{};

    for (final point in _paths) {
      final latMeters = point.latitude * 111320.0;
      final lngMeters = point.longitude *
          math.max(1e-6, 111320.0 * math.cos(point.latitude * math.pi / 180));
      final x = (lngMeters / gridMeters).floor();
      final y = (latMeters / gridMeters).floor();
      final key = '$x:$y';

      final existing = cells[key];
      if (existing == null) {
        cells[key] = _OverlapHeatCell(
          center: LatLng(point.latitude, point.longitude),
          passes: 1,
        );
      } else {
        cells[key] = _OverlapHeatCell(
          center: existing.center,
          passes: existing.passes + 1,
        );
      }
    }

    final hotCells = cells.values.where((c) => c.passes > 1).toList();
    hotCells.sort((a, b) => b.passes.compareTo(a.passes));
    return hotCells;
  }

  double _distanceMiles() {
    final mapService = context.read<MapService>();
    return mapService.calculateDistanceMiles(_paths);
  }

  double _liveCoveragePercent() {
    if (_paths.length < 2) return 0;

    final coveredSqMeters = _reachModeEnabled
        ? _reachCoveredAreaSqMeters()
        : ((_distanceMiles() * 1609.34) * (_swathWidthFeet * 0.3048));

    final sprayableZones = _sprayableZones();
    final activeZone = _activeSprayableZone();

    double sprayableAreaSqMeters;
    if (activeZone != null) {
      sprayableAreaSqMeters = _polygonAreaSqMeters(activeZone.ring);
    } else if (sprayableZones.isNotEmpty) {
      sprayableAreaSqMeters = sprayableZones.fold<double>(
        0,
        (sum, zone) => sum + _polygonAreaSqMeters(zone.ring),
      );
    } else {
      final hasOuterBoundary = _outerBoundaryRing.length >= 3;
      final mapAreaSqMeters = hasOuterBoundary
          ? _polygonAreaSqMeters(_outerBoundaryRing)
          : _boundsAreaSqMeters(_mapBounds);

      if (mapAreaSqMeters <= 0) return 0;

      final excludedAreaSqMeters = _exclusionRings.fold<double>(
        0,
        (sum, ring) => sum + _polygonAreaSqMeters(ring),
      );

      sprayableAreaSqMeters =
          math.max(1, mapAreaSqMeters - excludedAreaSqMeters);
    }

    sprayableAreaSqMeters = math.max(1, sprayableAreaSqMeters);

    final percent = (coveredSqMeters / sprayableAreaSqMeters) * 100;
    return percent.clamp(0, 100);
  }

  double _boundsAreaSqMeters(LatLngBounds? bounds) {
    if (bounds == null) return 0;
    final distance = const Distance();
    final midLat = (bounds.north + bounds.south) / 2;
    final widthMeters = distance(
      LatLng(midLat, bounds.west),
      LatLng(midLat, bounds.east),
    );
    final heightMeters = distance(
      LatLng(bounds.south, bounds.west),
      LatLng(bounds.north, bounds.west),
    );
    return widthMeters * heightMeters;
  }

  double _polygonAreaSqMeters(List<LatLng> polygon) {
    if (polygon.length < 3) return 0;

    final refLat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(refLat * math.pi / 180);

    final points = List<LatLng>.from(polygon);
    if (!_samePoint(points.first, points.last)) {
      points.add(points.first);
    }

    var area = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final x1 = points[i].longitude * metersPerDegLng;
      final y1 = points[i].latitude * metersPerDegLat;
      final x2 = points[i + 1].longitude * metersPerDegLng;
      final y2 = points[i + 1].latitude * metersPerDegLat;
      area += (x1 * y2) - (x2 * y1);
    }
    return area.abs() / 2;
  }

  LatLng _initialCenter() {
    if (_mapBounds != null) {
      return LatLng(
        (_mapBounds!.north + _mapBounds!.south) / 2,
        (_mapBounds!.east + _mapBounds!.west) / 2,
      );
    }

    if (_latitude != 0 || _longitude != 0) {
      return LatLng(_latitude, _longitude);
    }

    return const LatLng(0, 0);
  }

  String _elapsedLabel() {
    return AppFormat.durationSeconds(_elapsedSeconds);
  }

  Widget _statChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final coverage = _liveCoveragePercent();
    final distance = _distanceMiles();
    final sizeLabel = _reachModeEnabled ? 'Reach Depth' : 'Swath Width';
    final summary = _sessionSummary ?? _buildSessionSummary();
    final remainingPercent = _remainingProductPercent();
    final isCriticalProduct = _activeLowProductThreshold == 5;
    final isLowProduct = _activeLowProductThreshold == 10;
    final isHeadsUpProduct = _activeLowProductThreshold == 20;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_autoPausedByInactivity && !_isTracking) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.pause_circle_outline,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Paused - resume?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _togglePause,
                    child: const Text('Resume'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (summary.tankCapacityGallons != null &&
              summary.estimatedProductUsed != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCriticalProduct
                    ? Colors.red.withValues(alpha: 0.20)
                    : isLowProduct
                        ? Colors.orange.withValues(alpha: 0.18)
                        : isHeadsUpProduct
                            ? Colors.yellow.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCriticalProduct
                      ? Colors.red.withValues(alpha: 0.65)
                      : isLowProduct
                          ? Colors.orange.withValues(alpha: 0.5)
                          : isHeadsUpProduct
                              ? Colors.yellow.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _activeLowProductThreshold == null
                        ? 'Estimated product status'
                        : 'Low product - ~${(summary.remainingProduct ?? 0).clamp(0.0, summary.tankCapacityGallons ?? 0).toStringAsFixed(1)} gal left',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Used ${summary.estimatedProductUsed!.toStringAsFixed(2)} ${summary.applicationRateUnit} of ${summary.tankCapacityGallons!.toStringAsFixed(1)} gal capacity.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  if (summary.remainingProduct != null)
                    Text(
                      'Remaining: ${summary.remainingProduct!.toStringAsFixed(2)} ${summary.applicationRateUnit}${remainingPercent == null ? '' : ' (${remainingPercent.toStringAsFixed(0)}%)'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  if (isLowProduct || isCriticalProduct) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _savePartialSession,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.7),
                          ),
                        ),
                        child: const Text('Stop & Save'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$sizeLabel: ${AppFormat.feet(_swathWidthFeet)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isTracking ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isTracking
                      ? 'LIVE ${_elapsedLabel()}'
                      : 'PAUSED ${_elapsedLabel()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (_sprayableZones().isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _activeZoneSelection,
              dropdownColor: Colors.black.withValues(alpha: 0.92),
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'Active Spray Zone',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: _allSprayableSelectionId,
                  child: Text('All Sprayable Zones'),
                ),
                ..._sprayableZones().map(
                  (zone) => DropdownMenuItem<String>(
                    value: zone.id,
                    child: Text('Spraying ${zone.name}'),
                  ),
                ),
              ],
              onChanged: _isSessionEnded
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _activeZoneSelection = value);
                    },
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Reach Mode (Off-to-the-Side)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            subtitle: Text(
              _reachModeEnabled
                  ? 'Reach Mode - facing ${_headingDirectionLabel(_effectiveReachHeadingDegrees())}'
                  : 'Off - normal full circle coverage',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            value: _reachModeEnabled,
            onChanged: _isSessionEnded
                ? null
                : (enabled) {
                    setState(() {
                      _reachModeEnabled = enabled;
                    });
                  },
          ),
          if (_reachModeEnabled)
            Row(
              children: [
                IconButton(
                  onPressed: () => _nudgeReachHeading(-15),
                  icon: const Icon(Icons.rotate_left),
                  color: Colors.white,
                  tooltip: 'Rotate spray direction left',
                ),
                Expanded(
                  child: Text(
                    _isCompassAvailable
                        ? 'Compass + manual trim: ${_headingDirectionLabel(_effectiveReachHeadingDegrees())}'
                        : 'Manual direction: ${_headingDirectionLabel(_effectiveReachHeadingDegrees())}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => _nudgeReachHeading(15),
                  icon: const Icon(Icons.rotate_right),
                  color: Colors.white,
                  tooltip: 'Rotate spray direction right',
                ),
              ],
            ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              multiSelectionEnabled: false,
              selected: <String>{_swathSegmentSelection},
              segments: [
                ..._presetSwathFeet.map(
                  (feet) => ButtonSegment<String>(
                    value: feet.toStringAsFixed(1),
                    label: Text('${feet.toStringAsFixed(1)} ft'),
                  ),
                ),
                const ButtonSegment<String>(
                  value: 'custom',
                  label: Text('Custom'),
                ),
              ],
              onSelectionChanged: _isSessionEnded
                  ? null
                  : (selected) async {
                      final value = selected.first;
                      if (value == 'custom') {
                        await _openCustomSwathPicker();
                        return;
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null) return;
                      _setSwathWidthFeet(parsed);
                    },
            ),
          ),
          if (_isCustomSwathSelection)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Custom precision: ${_swathWidthFeet.toStringAsFixed(1)} ft',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Overlap Heatmap',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              'Highlights multi-pass zones in red for overlap correction.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            value: _showOverlapHeatmap,
            onChanged: _isSessionEnded
                ? null
                : (enabled) {
                    setState(() => _showOverlapHeatmap = enabled);
                  },
          ),
          Tooltip(
            message: _isRawGnssSupported
                ? 'Capture raw GNSS measurements and higher cadence GPS updates.'
                : _canUseHighPrecisionMode
                    ? 'Use higher cadence mobile GPS updates (raw GNSS unavailable in this runtime).'
                    : 'Use an Android device for high-precision mode.',
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'High-Precision GPS Mode',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _canUseHighPrecisionMode
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              subtitle: Text(
                _isCheckingGnssSupport
                    ? 'Checking device GNSS capability...'
                    : _isRawGnssSupported
                        ? 'Raw GNSS available on this device (best quality).'
                        : _canUseHighPrecisionMode
                            ? 'Using high-frequency device GPS (no raw GNSS channel).'
                            : 'Unsupported on this device or platform.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              value: _highAccuracyGnssEnabled,
              onChanged: (!_canUseHighPrecisionMode || _isSessionEnded)
                  ? null
                  : (enabled) => _setHighAccuracyGnssEnabled(enabled),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statChip(
                  label: 'Lat / Lng',
                  value: AppFormat.latLng(_latitude, _longitude),
                ),
                const SizedBox(width: 8),
                _statChip(
                  label: 'Accuracy',
                  value: AppFormat.meters(_accuracy),
                ),
                const SizedBox(width: 8),
                _statChip(
                  label: 'Coverage',
                  value: AppFormat.percent(coverage),
                ),
                const SizedBox(width: 8),
                _statChip(
                  label: 'Distance',
                  value: AppFormat.miles(distance),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _togglePause,
                  icon: Icon(_isTracking ? Icons.pause : Icons.play_arrow),
                  label: Text(_isTracking
                      ? 'Pause'
                      : (_autoPausedByInactivity
                          ? 'Resume (Auto-paused)'
                          : 'Resume')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _undoLast30Seconds,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Undo 30s'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF455A64),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _stopTracking,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('Stop & Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: SegmentedButton<TrackingViewMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<TrackingViewMode>(
            value: TrackingViewMode.map,
            icon: Icon(Icons.map_outlined),
            label: Text('Map Completion View'),
          ),
          ButtonSegment<TrackingViewMode>(
            value: TrackingViewMode.guidance,
            icon: Icon(Icons.navigation_outlined),
            label: Text('Line Guidance View'),
          ),
        ],
        selected: {_viewMode},
        onSelectionChanged: (selection) {
          setState(() => _viewMode = selection.first);
        },
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.black
                : Colors.white,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFFA5D6A7)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceStatusCard() {
    final onPath = _guidanceStatus == 'On path';
    final statusColor = _guidanceDeviationWarning
        ? const Color(0xFFFF5252)
        : (onPath ? const Color(0xFF66BB6A) : const Color(0xFFFFB300));

    return Container(
      width: 235,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Guidance',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Distance to line: ${AppFormat.meters(_distanceToLineMeters)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: statusColor),
              const SizedBox(width: 6),
              Text(
                _guidanceStatus,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          if (_guidanceDeviationWarning) ...[
            const SizedBox(height: 4),
            Text(
              'Deviation warning: more than half swath off line',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFFF8A80),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuidanceMissingPathCard() {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Generate path first for guidance',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'No recommended_path detected on this property.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _generateRecommendedPath,
            icon: const Icon(Icons.alt_route_outlined),
            label: const Text('Generate Path'),
          ),
        ],
      ),
    );
  }

  Widget _buildCoveragePreviewPanel() {
    final coverage = _liveCoveragePercent();
    final center = _initialCenter();
    final previewCoverage = _coveragePolygonPoints();
    final previewReachCoverage = _reachCoveragePolygons();

    return Container(
      width: 185,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coverage Mini-Map',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 120,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 16,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: _property?.hasOrthomosaic() == true
                        ? 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
                        : _satelliteUrlTemplate,
                    subdomains: _property?.hasOrthomosaic() == true
                        ? const ['a', 'b', 'c']
                        : const [],
                  ),
                  if (_outerBoundaryDashed.isNotEmpty)
                    PolylineLayer(polylines: _outerBoundaryDashed),
                  if (_specialZones.isNotEmpty)
                    PolygonLayer(
                      polygons: _specialZones
                          .map(
                            (zone) => Polygon(
                              points: zone.ring,
                              color: zone.color.withValues(alpha: 0.22),
                              borderColor: zone.color,
                              borderStrokeWidth: 2,
                              isFilled: true,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  if (_exclusionPolygons.isNotEmpty)
                    PolygonLayer(polygons: _exclusionPolygons),
                  if (!_reachModeEnabled && previewCoverage.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: previewCoverage,
                          color: Colors.green.withValues(alpha: 0.26),
                          borderColor: Colors.green,
                          borderStrokeWidth: 1,
                          holePointsList: _exclusionRings,
                          isFilled: true,
                        ),
                      ],
                    ),
                  if (_reachModeEnabled && previewReachCoverage.isNotEmpty)
                    PolygonLayer(
                      polygons: previewReachCoverage
                          .where((ring) => ring.length >= 3)
                          .map(
                            (ring) => Polygon(
                              points: ring,
                              color: Colors.green.withValues(alpha: 0.22),
                              borderColor: Colors.green,
                              borderStrokeWidth: 1,
                              isFilled: true,
                            ),
                          )
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppFormat.percent(coverage)} covered',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelJobButton() {
    final label = _cancelJobArmed
        ? 'Cancel ($_cancelJobTapsRemaining/3) ${_cancelJobSecondsLeft}s'
        : 'Cancel Job';

    return FloatingActionButton.extended(
      heroTag: 'cancel_job_btn',
      onPressed: _onCancelJobPressed,
      backgroundColor: const Color(0xCCD32F2F),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.cancel_outlined),
      label: Text(label),
    );
  }

  Future<void> _generateRecommendedPath() async {
    final property = _property;
    final boundary = property == null
        ? null
        : (property.outerBoundary ??
            _extractPolygonFromAnyGeoJson(property.mapGeojson));
    if (property == null || boundary == null) {
      if (!mounted) return;
      _showSnackBar(
        AppSnackBar.warning(
            'Import a map or set an outer boundary before generating a path.'),
      );
      return;
    }

    try {
      final result = RecommendedPathService().generate(
        boundaryGeoJson: boundary,
        exclusionZones: property.exclusionZones ?? const [],
        swathWidthFeet: _swathWidthFeet,
      );

      final supabase = context.read<SupabaseService>();
      await supabase.updateRecommendedPath(
        propertyId: widget.propertyId,
        recommendedPath: result.geoJson,
      );

      if (!mounted) return;
      setState(() {
        _property = Property(
          id: property.id,
          name: property.name,
          address: property.address,
          notes: property.notes,
          ownerId: property.ownerId,
          assignedTo: property.assignedTo,
          mapGeojson: property.mapGeojson,
          orthomosaicUrl: property.orthomosaicUrl,
          exclusionZones: property.exclusionZones,
          specialZones: property.specialZones,
          outerBoundary: property.outerBoundary,
          recommendedPath: result.geoJson,
          treatmentType: property.treatmentType,
          lastApplication: property.lastApplication,
          frequencyDays: property.frequencyDays,
          nextDue: property.nextDue,
          applicationRatePerAcre: property.applicationRatePerAcre,
          applicationRateUnit: property.applicationRateUnit,
          chemicalCostPerUnit: property.chemicalCostPerUnit,
          defaultTankCapacityGallons: property.defaultTankCapacityGallons,
          createdAt: property.createdAt,
        );
        _recommendedPath = _extractRecommendedPath(result.geoJson);
        _guidanceSegmentIndex = 0;
      });
      _showSnackBar(
        result.usedFallback
            ? AppSnackBar.warning(
                'Recommended path generated with fallback mode.')
            : AppSnackBar.success('Recommended path generated.'),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        AppSnackBar.error('Could not generate a recommended path.'),
      );
    }
  }

  Map<String, dynamic>? _extractPolygonFromAnyGeoJson(
    Map<String, dynamic>? rawGeoJson,
  ) {
    if (rawGeoJson == null) return null;

    final type = (rawGeoJson['type'] ?? '').toString();
    if (type == 'Polygon' && rawGeoJson['coordinates'] is List) {
      return rawGeoJson;
    }

    if (type == 'Feature' && rawGeoJson['geometry'] is Map) {
      final geometry = Map<String, dynamic>.from(
          rawGeoJson['geometry'] as Map<dynamic, dynamic>);
      if ((geometry['type'] ?? '').toString() == 'Polygon' &&
          geometry['coordinates'] is List) {
        return geometry;
      }
    }

    if (type == 'FeatureCollection' && rawGeoJson['features'] is List) {
      for (final feature in rawGeoJson['features'] as List) {
        if (feature is Map && feature['geometry'] is Map) {
          final geometry = Map<String, dynamic>.from(
              feature['geometry'] as Map<dynamic, dynamic>);
          if ((geometry['type'] ?? '').toString() == 'Polygon' &&
              geometry['coordinates'] is List) {
            return geometry;
          }
        }
      }
    }

    return null;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _connectivitySubscription?.cancel();
    _rawGnssSubscription?.cancel();
    _magnetometerStream?.cancel();
    _cancelJobTimer?.cancel();
    _elapsedTimer?.cancel();
    _deviationFlashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interactionFlags = _orientationLocked
        ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
        : InteractiveFlag.all;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.26),
        title: Text(widget.propertyName),
      ),
      body: _isLoadingMap
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: FlutterMap(
                      key: ValueKey(_viewMode),
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _initialCenter(),
                        initialZoom: _mapBounds != null ? 18 : 16,
                        interactionOptions:
                            InteractionOptions(flags: interactionFlags),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _property?.hasOrthomosaic() == true
                              ? 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
                              : _satelliteUrlTemplate,
                          subdomains: _property?.hasOrthomosaic() == true
                              ? const ['a', 'b', 'c']
                              : const [],
                        ),
                        if (_property?.hasOrthomosaic() == true &&
                            _mapBounds != null)
                          OverlayImageLayer(
                            overlayImages: [
                              OverlayImage(
                                bounds: _mapBounds!,
                                opacity: 0.9,
                                imageProvider:
                                    NetworkImage(_property!.orthomosaicUrl!),
                              ),
                            ],
                          ),
                        if (_propertyBoundary.length >= 3)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _propertyBoundary,
                                borderColor: Colors.blue,
                                borderStrokeWidth: 2,
                                color: Colors.blue.withValues(alpha: 0.08),
                                isFilled: true,
                              ),
                            ],
                          ),
                        if (_outerBoundaryDashed.isNotEmpty)
                          PolylineLayer(polylines: _outerBoundaryDashed),
                        if (_specialZones.isNotEmpty)
                          PolygonLayer(
                            polygons: _specialZones
                                .map(
                                  (zone) => Polygon(
                                    points: zone.ring,
                                    color: zone.color.withValues(alpha: 0.22),
                                    borderColor: zone.color,
                                    borderStrokeWidth: 1.4,
                                    isFilled: true,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        if (_exclusionPolygons.isNotEmpty)
                          PolygonLayer(polygons: _exclusionPolygons),
                        if (_viewMode == TrackingViewMode.guidance &&
                            _recommendedPath.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _recommendedPath,
                                strokeWidth: 3,
                                color: const Color(0xFF64B5F6)
                                    .withValues(alpha: 0.72),
                              ),
                            ],
                          ),
                        if (_viewMode == TrackingViewMode.guidance)
                          PolylineLayer(
                            polylines: _buildGuidanceSegmentDashedPolylines(),
                          ),
                        if ((_reachModeEnabled && _reachCoveragePolygons().isNotEmpty) || (!_reachModeEnabled && _paths.length >= 2))
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _paths
                                    .map((p) => LatLng(p.latitude, p.longitude))
                                    .toList(),
                                strokeWidth: 4,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        if (_showOverlapHeatmap)
                          Builder(
                            builder: (context) {
                              final heatCells = _buildOverlapHeatCells();
                              if (heatCells.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final maxPasses = heatCells
                                  .map((cell) => cell.passes)
                                  .reduce(math.max)
                                  .toDouble();
                              final radius =
                                  math.max(2.5, _swathWidthFeet * 2.6);

                              return CircleLayer(
                                circles: heatCells.map((cell) {
                                  final intensity = (cell.passes / maxPasses)
                                      .clamp(0.15, 1.0);
                                  final alpha = 0.14 + (0.42 * intensity);
                                  return CircleMarker(
                                    point: cell.center,
                                    radius: radius,
                                    color: Color.lerp(
                                      const Color(0xFFFFEE58),
                                      const Color(0xFFD50000),
                                      intensity,
                                    )!
                                        .withValues(alpha: alpha),
                                    borderColor:
                                        Colors.red.withValues(alpha: 0.28),
                                    borderStrokeWidth: 1,
                                    useRadiusInMeter: true,
                                  );
                                }).toList(growable: false),
                              );
                            },
                          ),
                        if ((_reachModeEnabled && _reachCoveragePolygons().isNotEmpty) || (!_reachModeEnabled && _paths.length >= 2))
                          Builder(
                            builder: (context) {
                              final coveragePoints = _coveragePolygonPoints();
                              final reachPolygons = _reachCoveragePolygons();
                              if (!_reachModeEnabled &&
                                  coveragePoints.length < 3) {
                                return const SizedBox.shrink();
                              }
                              if (_reachModeEnabled && reachPolygons.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return PolygonLayer(
                                polygons: _reachModeEnabled
                                    ? reachPolygons
                                        .where((ring) => ring.length >= 3)
                                        .map(
                                          (ring) => Polygon(
                                            points: ring,
                                            color: Colors.green
                                                .withValues(alpha: 0.22),
                                            borderColor: Colors.green,
                                            borderStrokeWidth: 1.4,
                                            isFilled: true,
                                          ),
                                        )
                                        .toList(growable: false)
                                    : [
                                        Polygon(
                                          points: coveragePoints,
                                          color: Colors.green
                                              .withValues(alpha: 0.22),
                                          borderColor: Colors.green,
                                          borderStrokeWidth: 1.4,
                                          holePointsList: _exclusionRings,
                                          isFilled: true,
                                        ),
                                      ],
                              ).animate().fadeIn(
                                    duration: 280.ms,
                                    curve: Curves.easeOut,
                                  );
                            },
                          ),
                        if (_latitude != 0 || _longitude != 0)
                          MarkerLayer(
                            markers: [
                              if (_viewMode == TrackingViewMode.guidance &&
                                  _recommendedPath.length >= 2)
                                Marker(
                                  point: LatLng(_latitude, _longitude),
                                  width: 54,
                                  height: 54,
                                  child: Center(
                                    child: Transform.rotate(
                                      angle: _displayArrowRadians,
                                      child: const Icon(
                                        Icons.navigation,
                                        color: Color(0xFF1565C0),
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              Marker(
                                point: LatLng(_latitude, _longitude),
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00C853),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: MediaQuery.of(context).padding.top + 8,
                  child: Center(child: _buildViewModeToggle()),
                ),
                if (_viewMode == TrackingViewMode.guidance)
                  Positioned(
                    left: 12,
                    top: MediaQuery.of(context).padding.top + 74,
                    child: _recommendedPath.length >= 2
                        ? _buildGuidanceStatusCard()
                        : _buildGuidanceMissingPathCard(),
                  ),
                if (_viewMode == TrackingViewMode.guidance &&
                    _recommendedPath.length >= 2)
                  Positioned(
                    right: 12,
                    top: MediaQuery.of(context).padding.top + 74,
                    child: _buildCoveragePreviewPanel(),
                  ),
                Positioned(
                  left: 14,
                  bottom: MediaQuery.of(context).padding.bottom + 190,
                  child: Opacity(
                    opacity: 0.86,
                    child: _buildCancelJobButton(),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showDeviationFlash ? 1 : 0,
                      duration: const Duration(milliseconds: 140),
                      child: Container(
                        color: const Color(0x66FF1744),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 64,
                  child: FloatingActionButton.small(
                    heroTag: 'orientation_lock_btn',
                    onPressed: () {
                      setState(() => _orientationLocked = !_orientationLocked);
                    },
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                    foregroundColor: Colors.white,
                    child: Icon(
                      _orientationLocked
                          ? Icons.explore_off_outlined
                          : Icons.explore,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildBottomOverlay(),
                ),
              ],
            ),
    );
  }
}

class _SpecialZoneOverlay {
  const _SpecialZoneOverlay({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.isSprayable,
    required this.ring,
  });

  final String id;
  final String name;
  final String type;
  final Color color;
  final bool isSprayable;
  final List<LatLng> ring;
}

class _SessionSummary {
  const _SessionSummary({
    required this.overlapPercent,
    required this.overlapThreshold,
    required this.applicationRateUnit,
    this.overlapSavingsEstimate,
    this.tankCapacityGallons,
    this.estimatedProductUsed,
    this.remainingProduct,
    this.partialCompletionReason,
    this.checklistData,
  });

  final double overlapPercent;
  final double overlapThreshold;
  final double? overlapSavingsEstimate;
  final double? tankCapacityGallons;
  final double? estimatedProductUsed;
  final double? remainingProduct;
  final String applicationRateUnit;
  final String? partialCompletionReason;
  final Map<String, dynamic>? checklistData;

  Map<String, dynamic> toSessionExtraData() {
    return {
      'overlap_percent': overlapPercent,
      'overlap_savings_estimate': overlapSavingsEstimate,
      'overlap_threshold': overlapThreshold,
      'tank_capacity_gallons': tankCapacityGallons,
      'application_rate_unit': applicationRateUnit,
      'partial_completion_reason': partialCompletionReason,
      'checklist_data': checklistData,
    };
  }

  _SessionSummary copyWith({
    Map<String, dynamic>? checklistData,
  }) {
    return _SessionSummary(
      overlapPercent: overlapPercent,
      overlapThreshold: overlapThreshold,
      overlapSavingsEstimate: overlapSavingsEstimate,
      tankCapacityGallons: tankCapacityGallons,
      estimatedProductUsed: estimatedProductUsed,
      remainingProduct: remainingProduct,
      applicationRateUnit: applicationRateUnit,
      partialCompletionReason: partialCompletionReason,
      checklistData: checklistData ?? this.checklistData,
    );
  }
}

class _ReachSpraySample {
  const _ReachSpraySample({
    required this.point,
    required this.headingDegrees,
    required this.reachFeet,
    required this.timestamp,
  });

  final LatLng point;
  final double headingDegrees;
  final double reachFeet;
  final DateTime timestamp;
}

class _OverlapHeatCell {
  const _OverlapHeatCell({
    required this.center,
    required this.passes,
  });

  final LatLng center;
  final int passes;
}













