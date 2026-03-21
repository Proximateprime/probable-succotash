import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:turf/turf.dart' as turf;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/property_model.dart';
import '../services/supabase_service.dart';

enum BoundarySetupStep { outer, zones }

enum WalkSegmentType { outer, fullZone, sliceZone, exclusion }

class SetupBoundaryScreen extends StatefulWidget {
  const SetupBoundaryScreen({
    Key? key,
    required this.property,
    required this.onSaved,
  }) : super(key: key);

  final Property property;
  final Future<void> Function() onSaved;

  @override
  State<SetupBoundaryScreen> createState() => _SetupBoundaryScreenState();
}

class _SetupBoundaryScreenState extends State<SetupBoundaryScreen> {
  static const String _satelliteUrlTemplate =
      'https://mt.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  BoundarySetupStep _step = BoundarySetupStep.outer;
  WalkSegmentType? _activeWalkType;

  bool _isSaving = false;
  bool _isWalking = false;

  LatLng _mapCenter = const LatLng(34.1656, -84.7999);
  final double _mapZoom = 18;
  LatLng? _currentGps;

  List<LatLng> _outerBoundary = [];
  final List<_WalkSpecialZone> _specialZones = [];
  final List<_WalkExclusionZone> _exclusionZones = [];
  final List<LatLng> _activeTrail = [];
  _SlicePreview? _slicePreview;
  int? _selectedSliceSide;

  static const List<_SpecialZoneTypeOption> _specialZoneTypeOptions = [
    _SpecialZoneTypeOption(
      id: 'sprayable',
      label: 'Sprayable',
      color: Color(0xFF2E7D32),
      isSprayable: true,
    ),
    _SpecialZoneTypeOption(
      id: 'no_spray',
      label: 'No Spray',
      color: Color(0xFFD32F2F),
      isSprayable: false,
    ),
    _SpecialZoneTypeOption(
      id: 'caution',
      label: 'Caution',
      color: Color(0xFFF9A825),
      isSprayable: true,
    ),
  ];

  static const double _walkAutoAddAccuracyThresholdMeters = 6;
  static const double _walkPoorGpsWarningThresholdMeters = 8;
  static const double _walkJumpThresholdMeters = 5;
  static const double _walkMaxSpeedMph = 10;
  static const double _walkAutoCloseDistanceMeters = 10;
  static const int _walkPoorGpsConsecutiveLimit = 5;
  static const int _walkSmoothingWindow = 4;

  static const List<_ExclusionTypeOption> _exclusionTypeOptions = [
    _ExclusionTypeOption(
      id: 'septic_field',
      label: 'Septic Field',
      color: Color(0xFFD32F2F),
    ),
    _ExclusionTypeOption(
      id: 'bee_hive',
      label: 'Bee Hive',
      color: Color(0xFFFFA000),
    ),
    _ExclusionTypeOption(
      id: 'flower_bed',
      label: 'Flower Bed',
      color: Color(0xFF8E24AA),
    ),
    _ExclusionTypeOption(
      id: 'tree_cluster',
      label: 'Tree Cluster',
      color: Color(0xFF2E7D32),
    ),
    _ExclusionTypeOption(
      id: 'custom_exclusion',
      label: 'Custom Exclusion',
      color: Color(0xFFE53935),
    ),
  ];

  StreamSubscription<Position>? _positionSubscription;
  DateTime? _lastAcceptedSampleAt;
  final List<LatLng> _recentGoodWalkPoints = [];
  int _filteredWalkPoints = 0;
  int _poorGpsStreak = 0;
  bool _manualPointMode = false;
  bool _showGpsDebug = false;
  bool _poorGpsPromptShown = false;
  bool _pathNotClosedWarning = false;
  LatLng? _rejectedJumpPoint;


  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _loadExistingGeometry();
    _primeCurrentLocation();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  void _loadExistingGeometry() {
    _outerBoundary = _extractPolygonVertices(widget.property.outerBoundary);

    final specialZones = widget.property.specialZones ?? const [];
    for (final zone in specialZones) {
      final polygon = _extractZonePolygon(zone);
      final points = _extractPolygonVertices(polygon);
      if (points.length < 4) continue;

      final zoneName = (zone['name'] ?? 'Unnamed Zone').toString().trim();
      final zoneType = (zone['type'] ?? 'sprayable').toString().trim();
      final color =
          _colorFromHex(zone['color']?.toString()) ?? const Color(0xFF2E7D32);
      final sprayableValue = zone['sprayable'];
      final isSprayable = sprayableValue is bool
          ? sprayableValue
          : (zoneType == 'sprayable' || zoneType == 'caution');

      _specialZones.add(
        _WalkSpecialZone(
          name: zoneName.isEmpty ? 'Unnamed Zone' : zoneName,
          type: zoneType.isEmpty ? 'sprayable' : zoneType,
          color: color,
          isSprayable: isSprayable,
          ring: points,
        ),
      );
    }

    final zones = widget.property.exclusionZones ?? const [];
    for (final zone in zones) {
      final polygon = _extractZonePolygon(zone);
      final points = _extractPolygonVertices(polygon);
      if (points.length < 4) continue;

      final zoneType = (zone['zone_type'] ??
              ((polygon?['properties'] is Map)
                  ? polygon!['properties']['zone_type']
                  : null) ??
              '')
          .toString();
      final note = zone['note']?.toString();
      final label = zone['label']?.toString();
      final colorHex = zone['color']?.toString();

      _exclusionZones.add(
        _WalkExclusionZone(
          ring: points,
          note: (note == null || note.trim().isEmpty) ? null : note.trim(),
          exclusionType:
              zoneType.isEmpty ? 'custom_exclusion' : zoneType.trim(),
          label: (label == null || label.trim().isEmpty)
              ? 'Custom Exclusion'
              : label.trim(),
          color: _colorFromHex(colorHex) ?? const Color(0xFFE53935),
        ),
      );
    }

    final seedPoints = _outerBoundary.isNotEmpty
        ? _outerBoundary
        : _extractGeoPoints(widget.property.mapGeojson);

    if (_outerBoundary.length >= 4) {
      _step = BoundarySetupStep.zones;
    }

    if (seedPoints.isNotEmpty) {
      final bounds = _buildBounds(seedPoints);
      if (bounds != null) {
        _mapCenter = LatLng(
          (bounds.north + bounds.south) / 2,
          (bounds.east + bounds.west) / 2,
        );
      }
    }
  }

  Future<void> _primeCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      var granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (!granted) {
        final requested = await Geolocator.requestPermission();
        granted = requested == LocationPermission.always ||
            requested == LocationPermission.whileInUse;
      }

      if (!granted) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentGps = point;
      });
      _mapController.move(point, _mapZoom);
    } catch (_) {
      // Keep map centered on boundary seed/default fallback.
    }
  }

  Future<void> _startWalk(
    WalkSegmentType type, {
    List<LatLng>? seedTrail,
  }) async {
    if (_isWalking) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Enable location services to use walk setup.',
            color: Colors.orange.shade800);
        return;
      }

      final permission = await Geolocator.checkPermission();
      var granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) {
        final request = await Geolocator.requestPermission();
        granted = request == LocationPermission.always ||
            request == LocationPermission.whileInUse;
      }

      if (!granted) {
        _showSnack('Location permission is required for walking setup.',
            color: Colors.red.shade700);
        return;
      }

      await _positionSubscription?.cancel();

      final preparedSeed = List<LatLng>.from(seedTrail ?? const []);
      if (preparedSeed.length >= 2 &&
          _samePoint(preparedSeed.first, preparedSeed.last)) {
        preparedSeed.removeLast();
      }

      setState(() {
        _activeWalkType = type;
        _activeTrail
          ..clear()
          ..addAll(preparedSeed);
        _isWalking = true;
        _manualPointMode = false;
        _pathNotClosedWarning = false;
        _rejectedJumpPoint = null;
        _lastAcceptedSampleAt = null;
        _filteredWalkPoints = 0;
        _poorGpsStreak = 0;
        _poorGpsPromptShown = false;
        _recentGoodWalkPoints
          ..clear()
          ..addAll(preparedSeed.take(_walkSmoothingWindow));
      });

      await WakelockPlus.enable();

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      _acceptSample(current, force: true);

      _showSnack(
        'For best accuracy, use High-Accuracy GPS mode (Android only) or external receiver.',
        color: Colors.blueGrey.shade800,
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen(
        (position) {
          _acceptSample(position);
        },
        onError: (_) {
          _positionSubscription?.cancel();
          if (mounted) {
            setState(() {
              _isWalking = false;
              _activeWalkType = null;
              _activeTrail.clear();
              _lastAcceptedSampleAt = null;
              _recentGoodWalkPoints.clear();
            });
          }
          WakelockPlus.disable();
          _showSnack('GPS stream interrupted. Try starting the walk again.',
              color: Colors.red.shade700);
        },
      );
    } catch (_) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      if (mounted) {
        setState(() {
          _isWalking = false;
          _activeWalkType = null;
          _activeTrail.clear();
          _lastAcceptedSampleAt = null;
          _recentGoodWalkPoints.clear();
        });
      }
      WakelockPlus.disable();
      _showSnack('Could not start walk mode. Please try again.',
          color: Colors.red.shade700);
    }
  }

  bool _acceptSample(
    Position position, {
    bool force = false,
    bool manualTap = false,
  }) {
    if (!mounted) return false;

    final rawPoint = LatLng(position.latitude, position.longitude);

    setState(() {
      _currentGps = rawPoint;
    });

    if (!_isWalking) return false;

    final now = DateTime.now();
    if (!manualTap && !force && _lastAcceptedSampleAt != null) {
      final elapsedMs = now.difference(_lastAcceptedSampleAt!).inMilliseconds;
      if (elapsedMs < 1200) {
        return false;
      }
    }

    final accuracy = position.accuracy.isFinite
        ? position.accuracy
        : _walkPoorGpsWarningThresholdMeters + 1;

    if (accuracy > _walkPoorGpsWarningThresholdMeters) {
      _poorGpsStreak += 1;
      if (_poorGpsStreak >= _walkPoorGpsConsecutiveLimit &&
          !_poorGpsPromptShown) {
        _poorGpsPromptShown = true;
        _showSnack(
          'Poor GPS - points may be off. Switch to manual point add?',
          color: Colors.orange.shade800,
        );
      }
    } else {
      _poorGpsStreak = 0;
      _poorGpsPromptShown = false;
    }

    final speedMph = (position.speed.isFinite ? position.speed : 0) * 2.236936;
    if (!force && accuracy > _walkAutoAddAccuracyThresholdMeters) {
      setState(() {
        _filteredWalkPoints += 1;
      });
      return false;
    }

    if (!force && speedMph > _walkMaxSpeedMph) {
      setState(() {
        _filteredWalkPoints += 1;
      });
      return false;
    }

    final lastAccepted = _activeTrail.isEmpty ? null : _activeTrail.last;
    if (lastAccepted != null) {
      final movedMeters = _distance.as(LengthUnit.Meter, lastAccepted, rawPoint);
      if (!force && movedMeters > _walkJumpThresholdMeters) {
        setState(() {
          _filteredWalkPoints += 1;
          _rejectedJumpPoint = rawPoint;
        });
        return false;
      }

      final minMoveMeters = math.max(0.8, math.min(2.5, accuracy * 0.22));
      if (!force && !manualTap && movedMeters < minMoveMeters) {
        return false;
      }
    }

    _recentGoodWalkPoints.add(rawPoint);
    while (_recentGoodWalkPoints.length > _walkSmoothingWindow) {
      _recentGoodWalkPoints.removeAt(0);
    }

    final smooth = _smoothedPoint(_recentGoodWalkPoints);

    if (_manualPointMode && !manualTap) {
      return false;
    }

    _lastAcceptedSampleAt = now;
    setState(() {
      _rejectedJumpPoint = null;
      _pathNotClosedWarning = false;
      _activeTrail.add(smooth);
    });

    return true;
  }

  LatLng _smoothedPoint(List<LatLng> points) {
    if (points.isEmpty) return _currentGps ?? _mapCenter;
    var lat = 0.0;
    var lng = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    final count = points.length.toDouble();
    return LatLng(lat / count, lng / count);
  }

  Future<void> _addPointHere() async {
    if (!_isWalking) return;

    try {
      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      final recorded = _acceptSample(current, manualTap: true);
      if (!recorded) {
        _showSnack(
          'Point not added. Wait for a better GPS fix (< ${_walkAutoAddAccuracyThresholdMeters.toStringAsFixed(0)} m).',
          color: Colors.orange.shade800,
        );
      }
    } catch (_) {
      _showSnack('Could not add point from current GPS fix.',
          color: Colors.red.shade700);
    }
  }

  void _snapTrailToFirst() {
    if (_activeTrail.length < 3) return;
    final first = _activeTrail.first;
    setState(() {
      if (_samePoint(_activeTrail.last, first)) {
        _activeTrail[_activeTrail.length - 1] = first;
      } else {
        _activeTrail.add(first);
      }
      _pathNotClosedWarning = false;
    });
  }

  Future<void> _fixOuterPath() async {
    if (_outerBoundary.length < 3) return;
    final seed = List<LatLng>.from(_outerBoundary);
    if (seed.length >= 2 && _samePoint(seed.first, seed.last)) {
      seed.removeLast();
    }
    await _startWalk(WalkSegmentType.outer, seedTrail: seed);
  }
  void _undoLastPoint() {
    if (!_isWalking || _activeTrail.isEmpty) return;
    setState(() {
      _activeTrail.removeLast();
    });
  }

  void _cancelWalk() {
    _positionSubscription?.cancel();
    WakelockPlus.disable();
    setState(() {
      _isWalking = false;
      _activeWalkType = null;
      _activeTrail.clear();
      _lastAcceptedSampleAt = null;
    });
  }

  Future<void> _finishWalk() async {
    if (!_isWalking || _activeWalkType == null) return;
    final minPoints = _activeWalkType == WalkSegmentType.sliceZone ? 2 : 3;
    if (_activeTrail.length < minPoints) {
      _showSnack('Walk a little more before finishing this polygon.',
          color: Colors.orange.shade800);
      return;
    }

    if (_activeWalkType != WalkSegmentType.sliceZone &&
        _activeTrail.length >= 3) {
      final first = _activeTrail.first;
      final last = _activeTrail.last;
      final closeDistance = _distance.as(LengthUnit.Meter, first, last);
      if (closeDistance > _walkAutoCloseDistanceMeters) {
        setState(() => _pathNotClosedWarning = true);
        _showSnack(
          'Path not closed - bad GPS at end?',
          color: Colors.orange.shade800,
        );
        return;
      }
    }

    final closed = _activeWalkType == WalkSegmentType.sliceZone
        ? List<LatLng>.from(_activeTrail)
        : _closedPolygon(
            _activeTrail,
            autoCloseDistanceMeters: _walkAutoCloseDistanceMeters,
          );
    _ExclusionZoneDraft? exclusionDraft;
    if (_activeWalkType == WalkSegmentType.exclusion) {
      exclusionDraft = await _promptExclusionNote();
      if (!mounted) return;
    }

    _SpecialZoneDraft? specialZoneDraft;
    _SlicePreview? generatedSlicePreview;
    if (_activeWalkType == WalkSegmentType.fullZone) {
      specialZoneDraft = await _promptSpecialZoneDetails();
      if (!mounted || specialZoneDraft == null) return;
    } else if (_activeWalkType == WalkSegmentType.sliceZone) {
      if (_outerBoundary.length < 4) {
        _showSnack('Save the outer perimeter before slicing.',
            color: Colors.orange.shade800);
        return;
      }
      generatedSlicePreview = _buildSlicePreview(_outerBoundary, closed);
      if (generatedSlicePreview == null) {
        _showSnack(
          'Slice must start and end on the outer perimeter. Try a longer line.',
          color: Colors.orange.shade800,
        );
        return;
      }
    }

    setState(() {
      switch (_activeWalkType!) {
        case WalkSegmentType.outer:
          _outerBoundary = closed;
          _step = BoundarySetupStep.zones;
          break;
        case WalkSegmentType.fullZone:
          if (specialZoneDraft != null) {
            _specialZones.add(
              _WalkSpecialZone(
                name: specialZoneDraft.name,
                type: specialZoneDraft.type.id,
                color: specialZoneDraft.color,
                isSprayable: specialZoneDraft.type.isSprayable,
                ring: closed,
              ),
            );
          }
          break;
        case WalkSegmentType.sliceZone:
          if (generatedSlicePreview != null) {
            _slicePreview = generatedSlicePreview;
            _selectedSliceSide = null;
          }
          break;
        case WalkSegmentType.exclusion:
          _exclusionZones.add(
            _WalkExclusionZone(
              ring: closed,
              note: exclusionDraft?.note,
              exclusionType: exclusionDraft?.typeId ?? 'custom_exclusion',
              label: exclusionDraft?.label ?? 'Custom Exclusion',
              color: exclusionDraft?.color ?? const Color(0xFFE53935),
            ),
          );
          break;
      }
      _isWalking = false;
      _activeWalkType = null;
      _activeTrail.clear();
      _recentGoodWalkPoints.clear();
      _manualPointMode = false;
      _lastAcceptedSampleAt = null;
      _pathNotClosedWarning = false;
      _rejectedJumpPoint = null;
    });

    _positionSubscription?.cancel();
    WakelockPlus.disable();
  }
  Future<_ExclusionZoneDraft?> _promptExclusionNote() async {
    final controller = TextEditingController();
    var selected = _exclusionTypeOptions.first;

    final result = await showDialog<_ExclusionZoneDraft?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exclusion Zone Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Type'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _exclusionTypeOptions
                      .map(
                        (option) => ChoiceChip(
                          selected: selected.id == option.id,
                          avatar: CircleAvatar(
                            radius: 6,
                            backgroundColor: option.color,
                          ),
                          label: Text(option.label),
                          onSelected: (_) {
                            setDialogState(() {
                              selected = option;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    hintText:
                        'e.g. Septic field - no spray, Bee hive - keep 50 ft away',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Skip Note'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _ExclusionZoneDraft(
                  typeId: selected.id,
                  label: selected.label,
                  color: selected.color,
                  note: controller.text.trim(),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  Future<_SpecialZoneDraft?> _promptSpecialZoneDetails() async {
    final nameController = TextEditingController();
    var selected = _specialZoneTypeOptions.first;

    final result = await showDialog<_SpecialZoneDraft?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Zone Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Zone name',
                    hintText: 'Front Lawn, Back Pasture, Flower Bed',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Type / Color'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _specialZoneTypeOptions
                      .map(
                        (option) => ChoiceChip(
                          selected: selected.id == option.id,
                          avatar: CircleAvatar(
                            radius: 6,
                            backgroundColor: option.color,
                          ),
                          label: Text(option.label),
                          onSelected: (_) {
                            setDialogState(() {
                              selected = option;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = nameController.text.trim();
                if (normalized.isEmpty) return;
                Navigator.pop(
                  context,
                  _SpecialZoneDraft(
                    name: normalized,
                    type: selected,
                    color: selected.color,
                  ),
                );
              },
              child: const Text('Save Zone'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    return result;
  }

  Future<void> _saveSelectedSliceZone() async {
    final preview = _slicePreview;
    final selectedSide = _selectedSliceSide;
    if (preview == null || selectedSide == null) return;

    final ring = selectedSide == 0 ? preview.zoneA : preview.zoneB;
    if (ring.length < 4) return;

    final draft = await _promptSpecialZoneDetails();
    if (!mounted || draft == null) return;

    setState(() {
      _specialZones.add(
        _WalkSpecialZone(
          name: draft.name,
          type: draft.type.id,
          color: draft.color,
          isSprayable: draft.type.isSprayable,
          ring: ring,
        ),
      );
      _slicePreview = null;
      _selectedSliceSide = null;
    });
  }

  void _clearSlicePreview() {
    setState(() {
      _slicePreview = null;
      _selectedSliceSide = null;
    });
  }

  _SlicePreview? _buildSlicePreview(
    List<LatLng> outerRing,
    List<LatLng> slicePath,
  ) {
    final closedOuter = _closedPolygon(outerRing);
    final cleanOuter = List<LatLng>.from(closedOuter);
    if (cleanOuter.isNotEmpty &&
        _samePoint(cleanOuter.first, cleanOuter.last)) {
      cleanOuter.removeLast();
    }

    if (cleanOuter.length < 3 || slicePath.length < 2) return null;

    // Use Turf intersection as the primary split eligibility check.
    final turfIntersections = turf.lineIntersect(
      turf.LineString(
        coordinates: slicePath
            .map((p) => turf.Position.of([p.longitude, p.latitude]))
            .toList(growable: false),
      ),
      turf.Polygon(
        coordinates: [
          _closedPolygon(cleanOuter)
              .map((p) => turf.Position.of([p.longitude, p.latitude]))
              .toList(growable: false),
        ],
      ),
    );
    if (turfIntersections.features.length < 2) {
      return null;
    }

    final hits = <_SliceHit>[];
    for (var i = 0; i < slicePath.length - 1; i++) {
      final a1 = slicePath[i];
      final a2 = slicePath[i + 1];
      for (var j = 0; j < cleanOuter.length; j++) {
        final b1 = cleanOuter[j];
        final b2 = cleanOuter[(j + 1) % cleanOuter.length];
        final hit = _segmentIntersection(a1, a2, b1, b2);
        if (hit == null) continue;

        final duplicate = hits.any(
          (existing) =>
              _distance.as(LengthUnit.Meter, existing.point, hit.point) < 0.2,
        );
        if (duplicate) continue;

        hits.add(
          _SliceHit(
            point: hit.point,
            sliceSegmentIndex: i,
            sliceT: hit.t1,
            boundaryEdgeIndex: j,
          ),
        );
      }
    }

    if (hits.length < 2) return null;

    hits.sort((a, b) {
      final aProgress = a.sliceSegmentIndex + a.sliceT;
      final bProgress = b.sliceSegmentIndex + b.sliceT;
      return aProgress.compareTo(bProgress);
    });

    final first = hits.first;
    final last = hits.last;

    final slicedPath = _slicePathBetweenIntersections(slicePath, first, last);
    if (slicedPath.length < 2) return null;

    final arcForward =
        _boundaryArcBetween(cleanOuter, last, first, forward: true);
    final arcBackward =
        _boundaryArcBetween(cleanOuter, last, first, forward: false);

    final zoneA = _closedPolygon([
      ...slicedPath,
      ...arcForward.skip(1),
    ]);
    final zoneB = _closedPolygon([
      ...slicedPath,
      ...arcBackward.skip(1),
    ]);

    if (zoneA.length < 4 || zoneB.length < 4) return null;
    if (_polygonAreaSqMeters(zoneA) < 4 || _polygonAreaSqMeters(zoneB) < 4) {
      return null;
    }

    return _SlicePreview(zoneA: zoneA, zoneB: zoneB, line: slicedPath);
  }

  List<LatLng> _slicePathBetweenIntersections(
    List<LatLng> path,
    _SliceHit first,
    _SliceHit last,
  ) {
    final points = <LatLng>[first.point];
    for (var i = first.sliceSegmentIndex + 1;
        i <= last.sliceSegmentIndex;
        i++) {
      points.add(path[i]);
    }
    points.add(last.point);
    return points;
  }

  List<LatLng> _boundaryArcBetween(
    List<LatLng> ring,
    _SliceHit from,
    _SliceHit to, {
    required bool forward,
  }) {
    final n = ring.length;
    if (n < 3) return const [];

    final arc = <LatLng>[from.point];
    var edge = from.boundaryEdgeIndex;

    while (edge != to.boundaryEdgeIndex) {
      if (forward) {
        final nextVertex = ring[(edge + 1) % n];
        if (!_samePoint(arc.last, nextVertex)) {
          arc.add(nextVertex);
        }
        edge = (edge + 1) % n;
      } else {
        final prevVertex = ring[edge % n];
        if (!_samePoint(arc.last, prevVertex)) {
          arc.add(prevVertex);
        }
        edge = (edge - 1 + n) % n;
      }
    }

    if (!_samePoint(arc.last, to.point)) {
      arc.add(to.point);
    }
    return arc;
  }

  _IntersectionResult? _segmentIntersection(
    LatLng p,
    LatLng p2,
    LatLng q,
    LatLng q2,
  ) {
    final rX = p2.longitude - p.longitude;
    final rY = p2.latitude - p.latitude;
    final sX = q2.longitude - q.longitude;
    final sY = q2.latitude - q.latitude;

    final denominator = (rX * sY) - (rY * sX);
    if (denominator.abs() < 1e-12) return null;

    final qpx = q.longitude - p.longitude;
    final qpy = q.latitude - p.latitude;

    final t = ((qpx * sY) - (qpy * sX)) / denominator;
    final u = ((qpx * rY) - (qpy * rX)) / denominator;

    if (t < 0 || t > 1 || u < 0 || u > 1) return null;

    return _IntersectionResult(
      point: LatLng(p.latitude + (t * rY), p.longitude + (t * rX)),
      t1: t,
    );
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-8 &&
        (a.longitude - b.longitude).abs() < 1e-8;
  }

  bool _ringsSimilar(List<LatLng> a, List<LatLng> b) {
    final closedA = _closedPolygon(a);
    final closedB = _closedPolygon(b);
    if (closedA.length != closedB.length) return false;

    for (var i = 0; i < closedA.length; i++) {
      if (!_samePoint(closedA[i], closedB[i])) {
        return false;
      }
    }
    return true;
  }

  double _polygonAreaSqMeters(List<LatLng> polygon) {
    if (polygon.length < 3) return 0;

    final refLat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    const metersPerDegLat = 111320.0;
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

  List<LatLng> _closedPolygon(
    List<LatLng> points, {
    double autoCloseDistanceMeters = double.infinity,
  }) {
    if (points.isEmpty) return const [];

    final closed = List<LatLng>.from(points);
    if (closed.length < 2) return closed;

    final first = closed.first;
    final last = closed.last;
    final alreadyClosed = _samePoint(first, last);
    if (alreadyClosed) {
      return closed;
    }

    final closeDistance = _distance.as(LengthUnit.Meter, first, last);
    if (closeDistance <= autoCloseDistanceMeters) {
      closed.add(first);
    }

    return closed;
  }

  Future<void> _saveSetup() async {
    if (_outerBoundary.length < 4) {
      _showSnack('Outer perimeter is required before saving.',
          color: Colors.orange.shade800);
      return;
    }

    try {
      setState(() => _isSaving = true);

      final outerBoundaryJson = _toGeoJsonPolygon(_outerBoundary);
      final specialZonesJson = <Map<String, dynamic>>[];
      final exclusionJson = <Map<String, dynamic>>[];

      for (final zone in _specialZones) {
        final polygon = _toGeoJsonPolygon(zone.ring);
        final colorHex = _hexFromColor(zone.color);
        specialZonesJson.add(
          {
            'name': zone.name,
            'polygon': polygon,
            'type': zone.type,
            'color': colorHex,
            'sprayable': zone.isSprayable,
          },
        );

        if (!zone.isSprayable) {
          exclusionJson.add(
            {
              'polygon': polygon,
              'zone_type': zone.type,
              'label': zone.name,
              'color': colorHex,
            },
          );
        }
      }

      for (final zone in _exclusionZones) {
        final existsInSpecial = _specialZones.any(
          (special) => _ringsSimilar(special.ring, zone.ring),
        );
        if (existsInSpecial) {
          continue;
        }

        final trimmed = zone.note?.trim();
        exclusionJson.add(
          {
            'polygon': _toGeoJsonPolygon(zone.ring),
            'zone_type': zone.exclusionType,
            'label': zone.label,
            'color': _hexFromColor(zone.color),
            if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
          },
        );
      }

      final updatePayload = <String, dynamic>{
        'outer_boundary': outerBoundaryJson,
        'special_zones': specialZonesJson,
        'exclusion_zones': exclusionJson,
      };

      if (widget.property.mapGeojson == null) {
        updatePayload['map_geojson'] = outerBoundaryJson;
      }

      await _saveSetupWithFallback(
        outerBoundaryJson: outerBoundaryJson,
        fullPayload: updatePayload,
      );

      await widget.onSaved();
      if (!mounted) return;

      _showSnack(
        'Boundary setup saved. Import orthomosaic later when ready.',
        color: Colors.green.shade700,
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      _showSnack('Could not save boundary setup. Please try again.',
          color: Colors.red.shade700);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveSetupWithFallback({
    required Map<String, dynamic> outerBoundaryJson,
    required Map<String, dynamic> fullPayload,
  }) async {
    final supabase = context.read<SupabaseService>();

    try {
      await supabase.updateProperty(widget.property.id, fullPayload);
      return;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final likelySchemaMismatch =
          msg.contains('column') || msg.contains('does not exist') || msg.contains("could not find");

      if (!likelySchemaMismatch) {
        rethrow;
      }
    }

    final fallbackPayloads = <Map<String, dynamic>>[
      {
        'outer_boundary': outerBoundaryJson,
        'exclusion_zones': fullPayload['exclusion_zones'],
        'map_geojson': outerBoundaryJson,
      },
      {
        'outer_boundary': outerBoundaryJson,
        'map_geojson': outerBoundaryJson,
      },
      {
        'map_geojson': outerBoundaryJson,
      },
    ];

    for (final payload in fallbackPayloads) {
      try {
        await supabase.updateProperty(widget.property.id, payload);
        if (mounted) {
          _showSnack(
            'Boundary saved with compatibility mode. Some zone fields may need a DB migration.',
            color: Colors.orange.shade800,
          );
        }
        return;
      } catch (_) {
        continue;
      }
    }

    throw Exception('Could not save any boundary payload to the backend');
  }

  Map<String, dynamic> _toGeoJsonPolygon(
    List<LatLng> ring,
  ) {
    final closed = _closedPolygon(ring);
    return {
      'type': 'Polygon',
      'coordinates': [
        closed.map((p) => [p.longitude, p.latitude]).toList(growable: false),
      ],
    };
  }

  Map<String, dynamic>? _extractZonePolygon(Map<String, dynamic> zone) {
    if (zone['polygon'] is Map) {
      return Map<String, dynamic>.from(zone['polygon'] as Map);
    }
    if (zone['type'] == 'Polygon') {
      return zone;
    }
    return null;
  }

  String _hexFromColor(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  String _stepTitle() {
    switch (_step) {
      case BoundarySetupStep.outer:
        return 'Step 1 of 2: Walk Outer Perimeter';
      case BoundarySetupStep.zones:
        return 'Step 2 of 2: Add Named Zones';
    }
  }

  String _stepHint() {
    switch (_step) {
      case BoundarySetupStep.outer:
        return 'Walk the outside edge of the property. Tap Finish Outer when done.';
      case BoundarySetupStep.zones:
        return 'Use Slice Zone for fast splits or Walk Full Zone for custom boundaries.';
    }
  }

  String _activeWalkLabel() {
    switch (_activeWalkType) {
      case WalkSegmentType.outer:
        return 'Finish Outer';
      case WalkSegmentType.fullZone:
        return 'Finish Full Zone';
      case WalkSegmentType.sliceZone:
        return 'Finish Slice';
      case WalkSegmentType.exclusion:
        return 'Finish Exclusion';
      case null:
        return 'Finish';
    }
  }

  double? _outerAreaAcres() {
    if (_outerBoundary.length < 4) return null;
    try {
      final polygon = turf.Polygon(
        coordinates: [
          _outerBoundary
              .map((p) => turf.Position.of([p.longitude, p.latitude]))
              .toList(growable: false),
        ],
      );
      final sqMeters = turf.area(polygon);
      if (sqMeters == null) return null;
      return sqMeters / 4046.8564224;
    } catch (_) {
      return null;
    }
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    try {
      final ring = _closedPolygon(polygon)
          .map((p) => turf.Position.of([p.longitude, p.latitude]))
          .toList(growable: false);
      final poly = turf.Polygon(coordinates: [ring]);
      return turf.booleanPointInPolygon(
        turf.Position.of([point.longitude, point.latitude]),
        poly,
      );
    } catch (_) {
      return false;
    }
  }

  List<Polyline> _walkPreviewDashes() {
    if (!_isWalking || _activeTrail.isEmpty) return const [];

    final target = _rejectedJumpPoint ?? _currentGps;
    if (target == null) return const [];

    final start = _activeTrail.last;
    final isJump = _rejectedJumpPoint != null;
    final color = isJump ? const Color(0xFFD32F2F) : const Color(0xFF00BCD4);

    return _dashSegment(start, target, color);
  }

  List<Polyline> _dashSegment(LatLng start, LatLng end, Color color) {
    const dashMeters = 2.0;
    const gapMeters = 1.2;

    final total = _distance.as(LengthUnit.Meter, start, end);
    if (total <= 0.01) {
      return [
        Polyline(points: [start, end], strokeWidth: 3, color: color),
      ];
    }

    final heading = _distance.bearing(start, end);
    final lines = <Polyline>[];
    var traveled = 0.0;
    while (traveled < total) {
      final dashStart = _distance.offset(start, traveled, heading);
      final dashEnd = _distance.offset(
        start,
        math.min(total, traveled + dashMeters),
        heading,
      );
      lines.add(
        Polyline(
          points: [dashStart, dashEnd],
          strokeWidth: 3,
          color: color,
        ),
      );
      traveled += dashMeters + gapMeters;
    }

    return lines;
  }
  List<LatLng> _extractPolygonVertices(Map<String, dynamic>? polygonGeoJson) {
    if (polygonGeoJson == null || polygonGeoJson['type'] != 'Polygon') {
      return [];
    }

    final coordinates = polygonGeoJson['coordinates'];
    if (coordinates is! List ||
        coordinates.isEmpty ||
        coordinates.first is! List) {
      return [];
    }

    final ring = coordinates.first as List;
    final vertices = <LatLng>[];
    for (final vertex in ring) {
      if (vertex is List && vertex.length >= 2) {
        final lng = vertex[0];
        final lat = vertex[1];
        if (lng is num && lat is num) {
          vertices.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return vertices;
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

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final outerAcres = _outerAreaAcres();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Define Boundaries by Walking'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.55),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stepTitle(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(_stepHint()),
                const SizedBox(height: 6),
                Text(
                  'Outer: ${_outerBoundary.length >= 4 ? 'Saved' : 'Pending'} GÇó Zones: ${_specialZones.length} GÇó Exclusions: ${_exclusionZones.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (outerAcres != null)
                  Text(
                    'Approx. outer area: ${outerAcres.toStringAsFixed(2)} acres',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
                onTap: (_, tappedPoint) {
                  final preview = _slicePreview;
                  if (preview == null) return;

                  final selected = _pointInPolygon(tappedPoint, preview.zoneA)
                      ? 0
                      : (_pointInPolygon(tappedPoint, preview.zoneB)
                          ? 1
                          : null);
                  if (selected == null) return;

                  setState(() {
                    _selectedSliceSide = selected;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _satelliteUrlTemplate,
                ),
                if (_outerBoundary.length >= 4)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _outerBoundary,
                        borderColor: const Color(0xFFFBC02D),
                        borderStrokeWidth: 2.4,
                        color: const Color(0xFFFBC02D).withValues(alpha: 0.15),
                        isFilled: true,
                      ),
                    ],
                  ),
                if (_specialZones.isNotEmpty)
                  PolygonLayer(
                    polygons: _specialZones
                        .map(
                          (zone) => Polygon(
                            points: zone.ring,
                            borderColor: zone.color,
                            borderStrokeWidth: 2,
                            color: zone.color.withValues(alpha: 0.22),
                            isFilled: true,
                          ),
                        )
                        .toList(),
                  ),
                if (_exclusionZones.isNotEmpty)
                  PolygonLayer(
                    polygons: _exclusionZones
                        .map(
                          (zone) => Polygon(
                            points: zone.ring,
                            borderColor: zone.color,
                            borderStrokeWidth: 2,
                            color: zone.color.withValues(alpha: 0.22),
                            isFilled: true,
                          ),
                        )
                        .toList(),
                  ),
                if (_activeTrail.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _activeTrail,
                        strokeWidth: 4,
                        color: const Color(0xFF00BCD4),
                      ),
                    ],
                  ),
                if (_walkPreviewDashes().isNotEmpty)
                  PolylineLayer(polylines: _walkPreviewDashes()),
                if (_slicePreview != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _slicePreview!.zoneA,
                        borderColor: _selectedSliceSide == 0
                            ? const Color(0xFF1E88E5)
                            : const Color(0xFF90CAF9),
                        borderStrokeWidth: _selectedSliceSide == 0 ? 2.8 : 1.8,
                        color: (_selectedSliceSide == 0
                                ? const Color(0xFF1E88E5)
                                : const Color(0xFF90CAF9))
                            .withValues(alpha: 0.24),
                        isFilled: true,
                      ),
                      Polygon(
                        points: _slicePreview!.zoneB,
                        borderColor: _selectedSliceSide == 1
                            ? const Color(0xFF43A047)
                            : const Color(0xFFA5D6A7),
                        borderStrokeWidth: _selectedSliceSide == 1 ? 2.8 : 1.8,
                        color: (_selectedSliceSide == 1
                                ? const Color(0xFF43A047)
                                : const Color(0xFFA5D6A7))
                            .withValues(alpha: 0.24),
                        isFilled: true,
                      ),
                    ],
                  ),
                if (_activeTrail.length >= 3 &&
                    _activeWalkType != WalkSegmentType.sliceZone)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _closedPolygon(_activeTrail),
                        borderColor: const Color(0xFF00BCD4),
                        borderStrokeWidth: 1.8,
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.16),
                        isFilled: true,
                      ),
                    ],
                  ),
                if (_currentGps != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentGps!,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isWalking && _step == BoundarySetupStep.outer)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _startWalk(WalkSegmentType.outer),
                            icon: const Icon(Icons.directions_walk),
                            label: const Text('Start Outer Walk'),
                          ),
                        ),
                        if (_outerBoundary.length >= 4) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _fixOuterPath,
                              icon: const Icon(Icons.build_circle_outlined),
                              label: const Text('Fix Path'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (!_isWalking && _step == BoundarySetupStep.zones)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _slicePreview != null
                                    ? null
                                    : () =>
                                        _startWalk(WalkSegmentType.sliceZone),
                                icon: const Icon(Icons.linear_scale),
                                label: const Text('Add Slice Zone'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _slicePreview != null
                                    ? null
                                    : () =>
                                        _startWalk(WalkSegmentType.fullZone),
                                icon: const Icon(Icons.gesture_outlined),
                                label: const Text('Add Full Zone'),
                              ),
                            ),
                          ],
                        ),
                        if (_slicePreview != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _selectedSliceSide == null
                                  ? 'Tap one side of the slice line to select the new zone.'
                                  : 'Side ${_selectedSliceSide == 0 ? 'A' : 'B'} selected. Save it as a named zone.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _selectedSliceSide == null
                                      ? null
                                      : _saveSelectedSliceZone,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Create Zone From Side'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: _clearSlicePreview,
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _saveSetup,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_isSaving
                                ? 'Saving...'
                                : 'Save Boundary + Zones'),
                          ),
                        ),
                      ],
                    ),
                  if (_isWalking)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _finishWalk,
                                icon: const Icon(Icons.check),
                                label: Text(_activeWalkLabel()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _undoLastPoint,
                                icon: const Icon(Icons.undo),
                                label: const Text('Undo Last Point'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          value: _manualPointMode,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Manual Point Mode'),
                          subtitle: const Text('Disable auto-add and tap Add Point Here.'),
                          onChanged: (value) => setState(() => _manualPointMode = value),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _addPointHere,
                                icon: const Icon(Icons.add_location_alt_outlined),
                                label: const Text('Add Point Here'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (_activeWalkType == WalkSegmentType.sliceZone || _activeTrail.length < 3) ? null : _snapTrailToFirst,
                                icon: const Icon(Icons.link_outlined),
                                label: const Text('Snap to First'),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile.adaptive(
                          value: _showGpsDebug,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Show GPS Debug'),
                          subtitle: Text('Filtered ${_filteredWalkPoints} bad points'),
                          onChanged: (value) => setState(() => _showGpsDebug = value),
                        ),
                        if (_pathNotClosedWarning)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Path not closed - bad GPS at end?',
                              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700),
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: _cancelWalk,
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel'),
                          ),
                        ),
                        Text(
                          'Walking points: ${_activeTrail.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkExclusionZone {
  const _WalkExclusionZone({
    required this.ring,
    required this.exclusionType,
    required this.label,
    required this.color,
    this.note,
  });

  final List<LatLng> ring;
  final String exclusionType;
  final String label;
  final Color color;
  final String? note;
}

class _WalkSpecialZone {
  const _WalkSpecialZone({
    required this.name,
    required this.type,
    required this.color,
    required this.isSprayable,
    required this.ring,
  });

  final String name;
  final String type;
  final Color color;
  final bool isSprayable;
  final List<LatLng> ring;
}

class _SpecialZoneTypeOption {
  const _SpecialZoneTypeOption({
    required this.id,
    required this.label,
    required this.color,
    required this.isSprayable,
  });

  final String id;
  final String label;
  final Color color;
  final bool isSprayable;
}

class _SpecialZoneDraft {
  const _SpecialZoneDraft({
    required this.name,
    required this.type,
    required this.color,
  });

  final String name;
  final _SpecialZoneTypeOption type;
  final Color color;
}

class _SlicePreview {
  const _SlicePreview({
    required this.zoneA,
    required this.zoneB,
    required this.line,
  });

  final List<LatLng> zoneA;
  final List<LatLng> zoneB;
  final List<LatLng> line;
}

class _SliceHit {
  const _SliceHit({
    required this.point,
    required this.sliceSegmentIndex,
    required this.sliceT,
    required this.boundaryEdgeIndex,
  });

  final LatLng point;
  final int sliceSegmentIndex;
  final double sliceT;
  final int boundaryEdgeIndex;
}

class _IntersectionResult {
  const _IntersectionResult({
    required this.point,
    required this.t1,
  });

  final LatLng point;
  final double t1;
}

class _ExclusionTypeOption {
  const _ExclusionTypeOption({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
}

class _ExclusionZoneDraft {
  const _ExclusionZoneDraft({
    required this.typeId,
    required this.label,
    required this.color,
    this.note,
  });

  final String typeId;
  final String label;
  final Color color;
  final String? note;
}













