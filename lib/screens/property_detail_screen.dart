// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/property_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../models/exclusion_zone_model.dart';
import '../services/recommended_path_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_ui.dart';
import 'tracking_screen.dart';
import 'webodm_screen.dart';
import 'plan_selection_screen.dart';
import 'exclusion_zone_draw_screen.dart';
import 'outer_boundary_draw_screen.dart';
import 'walk_boundary_setup.dart';

class PropertyDetailScreen extends StatefulWidget {
  final Property property;

  const PropertyDetailScreen({Key? key, required this.property})
      : super(key: key);

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  static const String _satelliteUrlTemplate =
      'https://mt.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  late Property _property;
  List<TrackingSession> _sessions = [];
  List<UserProfile> _availableWorkers = [];
  UserProfile? _currentUser;
  bool _isLoading = false;
  bool _isAssigning = false;
  bool _isGeneratingRecommendedPath = false;
  double _currentSwathWidthFeet = RecommendedPathService.defaultSwathWidthFeet;
  List<LatLng> _boundaryPoints = [];
  List<Polygon> _exclusionPolygons = [];
  List<_ExclusionNotePin> _exclusionNotePins = [];
  List<Polyline> _outerBoundaryDashed = [];
  List<Polyline> _recommendedPathDashed = [];
  LatLngBounds? _mapBounds;
  static const List<String> _treatmentTypeOptions = [
    'Preemergent',
    'Postemergent',
    'Fertilizer',
    'Insecticide',
    'Custom',
  ];

  String _selectedTreatmentType = 'Preemergent';
  final TextEditingController _customTreatmentTypeController =
      TextEditingController();
  final TextEditingController _amountUsedController = TextEditingController();
  final TextEditingController _amountWastedController = TextEditingController();
  final TextEditingController _acresCoveredController = TextEditingController();
  final TextEditingController _applicationRateController =
      TextEditingController();
  final TextEditingController _chemicalCostController = TextEditingController();
  final TextEditingController _defaultTankCapacityController =
      TextEditingController();
  String _amountUnit = 'gal';
  int _frequencyDays = 30;
  DateTime _lastApplicationDate = DateTime.now();
  double? _realUsagePerAcre;
  double? _estimatedRemainingAmount;
  bool _isSavingTreatment = false;

  @override
  void initState() {
    super.initState();
    _property = widget.property;
    _hydrateTreatmentFormFromProperty();
    _loadData();
  }

  @override
  void dispose() {
    _customTreatmentTypeController.dispose();
    _amountUsedController.dispose();
    _amountWastedController.dispose();
    _acresCoveredController.dispose();
    _applicationRateController.dispose();
    _chemicalCostController.dispose();
    _defaultTankCapacityController.dispose();
    super.dispose();
  }

  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final supabase = context.read<SupabaseService>();
      final profile = await supabase.fetchCurrentUserProfile();
      final updatedProperty = await supabase.fetchProperty(_property.id);
      final sessions = await supabase.fetchPropertySessions(_property.id);
      final latestSwathWidth =
          await supabase.fetchLatestPropertySwathWidthFeet(_property.id);

      List<UserProfile> workers = [];
      if ((profile?.role ?? '').toLowerCase() == 'corporate_admin') {
        workers = await supabase.fetchAssignableWorkers();
      }

      if (!mounted) return;

      setState(() {
        _currentUser = profile;
        _property = updatedProperty ?? _property;
        _sessions = sessions;
        _currentSwathWidthFeet =
            latestSwathWidth ?? RecommendedPathService.defaultSwathWidthFeet;
        _availableWorkers = workers;
        _prepareMapLayers();
        _hydrateTreatmentFormFromProperty();
        _prefillAcresCoveredFromSession();
      });
    } catch (e) {
      if (mounted) _showSnackBar(AppSnackBar.error('Failed to load property data.'));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _hydrateTreatmentFormFromProperty() {
    final treatmentType = _property.treatmentType?.trim();
    if (treatmentType == null || treatmentType.isEmpty) {
      _selectedTreatmentType = 'Preemergent';
      _customTreatmentTypeController.clear();
    } else if (_treatmentTypeOptions.contains(treatmentType)) {
      _selectedTreatmentType = treatmentType;
      _customTreatmentTypeController.clear();
    } else {
      _selectedTreatmentType = 'Custom';
      _customTreatmentTypeController.text = treatmentType;
    }

    _frequencyDays = _property.frequencyDays ?? 30;
    _lastApplicationDate = _property.lastApplication ?? DateTime.now();
    _amountUnit = _property.applicationRateUnit ?? 'gal';
    _applicationRateController.text =
        _property.applicationRatePerAcre?.toStringAsFixed(2) ?? '';
    _chemicalCostController.text =
        _property.chemicalCostPerUnit?.toStringAsFixed(2) ?? '';
    _defaultTankCapacityController.text =
        _property.defaultTankCapacityGallons?.toStringAsFixed(1) ?? '';
  }

  void _prefillAcresCoveredFromSession() {
    if (_acresCoveredController.text.trim().isNotEmpty) {
      return;
    }

    final estimatedAcres = _estimateAcres();
    if (estimatedAcres == null || estimatedAcres <= 0) {
      return;
    }

    double suggestedAcres = estimatedAcres;
    if (_sessions.isNotEmpty) {
      final latest = _sessions.first;
      final coverage = latest.coveragePercent;
      if (coverage != null && coverage > 0) {
        suggestedAcres = estimatedAcres * (coverage / 100);
      }
    }

    _acresCoveredController.text = suggestedAcres.toStringAsFixed(2);
  }

  double? _parsePositiveNumber(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _calculateTreatmentUsage() {
    final used = _parsePositiveNumber(_amountUsedController.text);
    final coveredAcres = _parsePositiveNumber(_acresCoveredController.text);
    final wastedRaw = double.tryParse(_amountWastedController.text.trim());
    final wasted = (wastedRaw == null || wastedRaw < 0) ? 0.0 : wastedRaw;

    if (used == null || coveredAcres == null) {
      _showSnackBar(
        AppSnackBar.warning(
            'Enter Amount Used and Acres Covered to calculate.'),
      );
      return;
    }

    final netUsed = (used - wasted).clamp(0.0, double.infinity);
    final usagePerAcre = netUsed / coveredAcres;
    final totalPropertyAcres = _estimateAcres() ?? coveredAcres;
    final remainingAcres =
        (totalPropertyAcres - coveredAcres).clamp(0.0, double.infinity);
    final remainingNeeded = usagePerAcre * remainingAcres;

    setState(() {
      _realUsagePerAcre = usagePerAcre;
      _estimatedRemainingAmount = remainingNeeded;
    });
  }

  Future<void> _saveTreatmentSchedule() async {
    final resolvedTreatmentType = _selectedTreatmentType == 'Custom'
        ? _customTreatmentTypeController.text.trim()
        : _selectedTreatmentType;

    final applicationRate =
        double.tryParse(_applicationRateController.text.trim());
    final chemicalCost = double.tryParse(_chemicalCostController.text.trim());
    final tankCapacity =
        double.tryParse(_defaultTankCapacityController.text.trim());

    if (resolvedTreatmentType.isEmpty) {
      _showSnackBar(
          AppSnackBar.warning('Enter a treatment type before saving.'));
      return;
    }

    if (_frequencyDays <= 0) {
      _showSnackBar(AppSnackBar.warning('Frequency must be at least 1 day.'));
      return;
    }

    final nextDue = _lastApplicationDate.add(Duration(days: _frequencyDays));

    try {
      setState(() => _isSavingTreatment = true);

      final payload = <String, dynamic>{
        'treatment_type': resolvedTreatmentType,
        'last_application':
            DateFormat('yyyy-MM-dd').format(_lastApplicationDate),
        'frequency_days': _frequencyDays,
        'next_due': DateFormat('yyyy-MM-dd').format(nextDue),
        'application_rate_per_acre': applicationRate,
        'application_rate_unit': _amountUnit,
        'chemical_cost_per_unit': chemicalCost,
        'default_tank_capacity_gallons': tankCapacity,
      };

      await context
          .read<SupabaseService>()
          .updateProperty(_property.id, payload);

      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: _property.assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: _property.exclusionZones,
          specialZones: _property.specialZones,
          outerBoundary: _property.outerBoundary,
          recommendedPath: _property.recommendedPath,
          treatmentType: resolvedTreatmentType,
          lastApplication: _lastApplicationDate,
          frequencyDays: _frequencyDays,
          nextDue: nextDue,
          applicationRatePerAcre: applicationRate,
          applicationRateUnit: _amountUnit,
          chemicalCostPerUnit: chemicalCost,
          defaultTankCapacityGallons: tankCapacity,
          createdAt: _property.createdAt,
        );
      });

      _showSnackBar(AppSnackBar.success('Treatment schedule saved.'));
    } catch (_) {
      _showSnackBar(AppSnackBar.error('Could not save treatment schedule.'));
    } finally {
      if (mounted) {
        setState(() => _isSavingTreatment = false);
      }
    }
  }

  Widget _buildTreatmentPlannerCard() {
    final nextDueText = _property.nextDue == null
        ? 'Not scheduled'
        : DateFormat.yMMMd().format(_property.nextDue!);

    return AppCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'Treatment Planner',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text('Next due: $nextDueText'),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedTreatmentType,
            decoration: const InputDecoration(labelText: 'Treatment Type'),
            items: _treatmentTypeOptions
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedTreatmentType = value);
            },
          ),
          if (_selectedTreatmentType == 'Custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customTreatmentTypeController,
              decoration: const InputDecoration(
                labelText: 'Custom Treatment Name',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountUsedController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount Used ($_amountUnit)',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 98,
                child: DropdownButtonFormField<String>(
                  initialValue: _amountUnit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: const [
                    DropdownMenuItem(value: 'gal', child: Text('gal')),
                    DropdownMenuItem(value: 'oz', child: Text('oz')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _amountUnit = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountWastedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount Wasted / Left ($_amountUnit) (optional)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _acresCoveredController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Property Acres Covered',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _applicationRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Chemical Rate ($_amountUnit per acre)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _chemicalCostController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Chemical Cost per $_amountUnit (optional)',
              prefixText: '\$',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _defaultTankCapacityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Default Tank Capacity (gal, optional)',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _prefillAcresCoveredFromSession,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Auto-fill Acres'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _calculateTreatmentUsage,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calculate Usage'),
                ),
              ),
            ],
          ),
          if (_realUsagePerAcre != null &&
              _estimatedRemainingAmount != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Real usage: ${_realUsagePerAcre!.toStringAsFixed(2)} $_amountUnit/acre'),
                  const SizedBox(height: 4),
                  Text(
                    'Estimated remaining needed: ${_estimatedRemainingAmount!.toStringAsFixed(2)} $_amountUnit for full property',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _lastApplicationDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    setState(() => _lastApplicationDate = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    'Last: ${DateFormat.yMMMd().format(_lastApplicationDate)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int>(
                  initialValue: _frequencyDays,
                  decoration: const InputDecoration(labelText: 'Every'),
                  items: const [30, 60, 90]
                      .map(
                        (days) => DropdownMenuItem<int>(
                          value: days,
                          child: Text('$days days'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _frequencyDays = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSavingTreatment ? null : _saveTreatmentSchedule,
              icon: _isSavingTreatment
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                  _isSavingTreatment ? 'Saving...' : 'Save Treatment Schedule'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSessions() async {
    try {
      final supabase = context.read<SupabaseService>();
      final sessions = await supabase.fetchPropertySessions(_property.id);
      setState(() {
        _sessions = sessions;
      });
    } catch (e) {
      // Error loading
    }
  }

  void _prepareMapLayers() {
    final mapPoints = _extractGeoPoints(_property.mapGeojson);
    final outerPoints = _extractPolygonVertices(_property.outerBoundary);
    final previewPoints = mapPoints.isNotEmpty ? mapPoints : outerPoints;

    _boundaryPoints = previewPoints;
    _mapBounds = _buildBounds(previewPoints);
    _exclusionPolygons = _buildExclusionPolygons(_property.exclusionZones);
    _exclusionNotePins = _buildExclusionNotePins(_property.exclusionZones);
    _outerBoundaryDashed =
        _buildDashedBoundary(_extractPolygonVertices(_property.outerBoundary));
    _recommendedPathDashed =
        _buildRecommendedPathPreview(_property.recommendedPath);
  }

  Future<void> _openBoundarySetupWizard() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalkBoundarySetupScreen(
          property: _property,
          onSaved: _loadData,
        ),
      ),
    );

    if (!mounted) return;
    await _loadData();
  }

  Future<void> _startTracking() async {
    try {
      setState(() => _isLoading = true);
      final supabase = context.read<SupabaseService>();
      if (supabase.currentUserId == null) return;

      final sessionConfig = await _showTrackingStartDialog();
      if (!mounted || sessionConfig == null) return;

      final sessionId = await supabase.createTrackingSession(
        propertyId: _property.id,
        userId: supabase.currentUserId!,
        tankCapacityGallons: sessionConfig.tankCapacityGallons,
        applicationRatePerAcre: sessionConfig.applicationRatePerAcre,
        applicationRateUnit: sessionConfig.applicationRateUnit,
        chemicalCostPerUnit: sessionConfig.chemicalCostPerUnit,
        overlapThreshold: _currentUser?.overlapThreshold,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrackingScreen(
              propertyId: _property.id,
              sessionId: sessionId,
              propertyName: _property.name,
              tankCapacityGallons: sessionConfig.tankCapacityGallons,
              applicationRatePerAcre: sessionConfig.applicationRatePerAcre,
              applicationRateUnit: sessionConfig.applicationRateUnit,
              chemicalCostPerUnit: sessionConfig.chemicalCostPerUnit,
              overlapThreshold: _currentUser?.overlapThreshold ?? 25,
            ),
          ),
        ).then((_) => _loadSessions());
      }
    } catch (e) {
      _showSnackBar(
        AppSnackBar.error('Could not start tracking for this property.'),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<_TrackingStartConfig?> _showTrackingStartDialog() async {
    final tankController = TextEditingController(
      text: _property.defaultTankCapacityGallons?.toStringAsFixed(1) ?? '',
    );
    final rateController = TextEditingController(
      text: _property.applicationRatePerAcre?.toStringAsFixed(2) ?? '',
    );
    final costController = TextEditingController(
      text: _property.chemicalCostPerUnit?.toStringAsFixed(2) ?? '',
    );
    var unit = _property.applicationRateUnit ?? 'gal';
    String? templateHint;

    final result = await showDialog<_TrackingStartConfig?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Session Setup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tankController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tank Capacity (gal, optional)',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Chemical Rate per Acre',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: const [
                          DropdownMenuItem(value: 'gal', child: Text('gal')),
                          DropdownMenuItem(value: 'oz', child: Text('oz')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => unit = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: costController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cost per $unit (optional)',
                    prefixText: '\$',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final saved = await _loadTrackingStartTemplate();
                        if (saved == null) {
                          setDialogState(() {
                            templateHint = 'No saved template yet.';
                          });
                          return;
                        }

                        setDialogState(() {
                          tankController.text =
                              saved.tankCapacityGallons?.toStringAsFixed(1) ??
                                  '';
                          rateController.text = saved.applicationRatePerAcre
                                  ?.toStringAsFixed(2) ??
                              '';
                          costController.text =
                              saved.chemicalCostPerUnit?.toStringAsFixed(2) ??
                                  '';
                          unit = saved.applicationRateUnit;
                          templateHint = 'Loaded saved template.';
                        });
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Load Template'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final config = _TrackingStartConfig(
                          tankCapacityGallons:
                              double.tryParse(tankController.text.trim()),
                          applicationRatePerAcre:
                              double.tryParse(rateController.text.trim()),
                          applicationRateUnit: unit,
                          chemicalCostPerUnit:
                              double.tryParse(costController.text.trim()),
                        );
                        await _saveTrackingStartTemplate(config);
                        setDialogState(() {
                          templateHint = 'Template saved for this property.';
                        });
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Template'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (_) {
                    final rate = double.tryParse(rateController.text.trim());
                    final suggestedGallons = _suggestedTankFillGallons(
                      applicationRatePerAcre: rate,
                    );
                    if (suggestedGallons == null) {
                      return const Text(
                        'Enter rate to see suggested tank fill for full coverage.',
                      );
                    }
                    return Text(
                      'Suggested fill: ${suggestedGallons.toStringAsFixed(2)} gal for full-property treatment.',
                    );
                  },
                ),
                if (templateHint != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    templateHint!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                Navigator.pop(
                  context,
                  _TrackingStartConfig(
                    tankCapacityGallons:
                        double.tryParse(tankController.text.trim()),
                    applicationRatePerAcre:
                        double.tryParse(rateController.text.trim()),
                    applicationRateUnit: unit,
                    chemicalCostPerUnit:
                        double.tryParse(costController.text.trim()),
                  ),
                );
              },
              child: const Text('Start Tracking'),
            ),
          ],
        ),
      ),
    );

    tankController.dispose();
    rateController.dispose();
    costController.dispose();
    return result;
  }

  String _trackingTemplateKey() {
    return 'tracking_start_template_${_property.id}';
  }

  Future<void> _saveTrackingStartTemplate(_TrackingStartConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _trackingTemplateKey(),
      '${config.tankCapacityGallons ?? ''}|${config.applicationRatePerAcre ?? ''}|${config.applicationRateUnit}|${config.chemicalCostPerUnit ?? ''}',
    );
  }

  Future<_TrackingStartConfig?> _loadTrackingStartTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trackingTemplateKey());
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 4) return null;

    return _TrackingStartConfig(
      tankCapacityGallons: double.tryParse(parts[0]),
      applicationRatePerAcre: double.tryParse(parts[1]),
      applicationRateUnit: parts[2].trim().isEmpty ? 'gal' : parts[2],
      chemicalCostPerUnit: double.tryParse(parts[3]),
    );
  }

  double? _suggestedTankFillGallons({required double? applicationRatePerAcre}) {
    if (applicationRatePerAcre == null || applicationRatePerAcre <= 0) {
      return null;
    }

    final acres = _estimateAcres();
    if (acres == null || acres <= 0) {
      return null;
    }

    return acres * applicationRatePerAcre;
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanSelectionScreen(onPlanSelected: _loadData),
                ),
              );
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
  Future<void> _openWebODMBuilder() async {
    if (_currentUser == null) return;

    final hasExistingMap = _property.hasMapData();

    if (!hasExistingMap) {
      final supabase = context.read<SupabaseService>();
      final limit = await supabase.checkCurrentUserMapLimit();
      if (!limit.allowed) {
        await _showMapLimitUpgradeDialog(limit);
        return;
      }
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebODMScreen(
            propertyId: _property.id,
            propertyName: _property.name,
            userTier: _currentUser!.tier,
            hadExistingMap: hasExistingMap,
            onMapImported: () {
              _loadData();
            },
          ),
        ),
      );
    }
  }

  Future<void> _openExclusionZoneDrawer() async {
    if (!_property.hasMapData()) {
      _showSnackBar(
        AppSnackBar.warning('Import a map first to draw exclusion zones.'),
      );
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExclusionZoneDrawScreen(
            property: _property,
            onZonesSaved: (zones) {
              _saveExclusionZones(zones);
            },
          ),
        ),
      ).then((_) => _loadData());
    }
  }

  Future<void> _openOuterBoundaryDrawer() async {
    if (!_property.hasMapData()) {
      _showSnackBar(
        AppSnackBar.warning('Import a map first to set an outer boundary.'),
      );
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OuterBoundaryDrawScreen(
            property: _property,
            onBoundarySaved: _saveOuterBoundary,
          ),
        ),
      ).then((_) => _loadData());
    }
  }

  Future<void> _showEditPropertyDialog() async {
    final nameController = TextEditingController(text: _property.name);
    final addressController =
        TextEditingController(text: _property.address ?? '');
    final notesController = TextEditingController(text: _property.notes ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Property'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final trimmedName = nameController.text.trim();
              if (trimmedName.isEmpty) return;

              try {
                final supabase = context.read<SupabaseService>();
                await supabase.updateProperty(
                  _property.id,
                  {
                    'name': trimmedName,
                    'address': addressController.text.trim(),
                    'notes': notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                  },
                );

                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
              } catch (e) {
                if (!mounted) return;
                _showSnackBar(
                  AppSnackBar.error('Could not update this property.'),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    nameController.dispose();
    addressController.dispose();
    notesController.dispose();
  }

  Future<void> _showAssignWorkersSheet() async {
    if (_availableWorkers.isEmpty) {
      _showSnackBar(
        AppSnackBar.info('No workers are available to assign right now.'),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final selectedWorkerIds = List<String>.from(_property.assignedTo);
        String? workerToAdd;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableToAdd = _availableWorkers
                .where((w) => !selectedWorkerIds.contains(w.id))
                .toList();

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign to Worker',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: workerToAdd,
                    decoration: const InputDecoration(
                      labelText: 'Select worker',
                    ),
                    items: availableToAdd
                        .map(
                          (worker) => DropdownMenuItem<String>(
                            value: worker.id,
                            child: Text(worker.email),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setModalState(() {
                        workerToAdd = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: workerToAdd == null
                          ? null
                          : () {
                              setModalState(() {
                                selectedWorkerIds.add(workerToAdd!);
                                workerToAdd = null;
                              });
                            },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add Worker'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (selectedWorkerIds.isEmpty)
                    const Text('No workers assigned yet.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedWorkerIds.map((workerId) {
                        final worker = _availableWorkers
                            .where((w) => w.id == workerId)
                            .cast<UserProfile?>()
                            .firstWhere((_) => true, orElse: () => null);

                        return InputChip(
                          label: Text(worker?.email ?? workerId),
                          onDeleted: () {
                            setModalState(() {
                              selectedWorkerIds.remove(workerId);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    label: _isAssigning ? 'Saving...' : 'Save Assignments',
                    isLoading: _isAssigning,
                    onPressed: _isAssigning
                        ? null
                        : () async {
                            await _saveAssignments(selectedWorkerIds);
                            if (mounted) Navigator.pop(context);
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveExclusionZones(List<ExclusionZone> zones) async {
    try {
      final supabase = context.read<SupabaseService>();
      final geoJsonZones = zones
          .map((zone) => zone.toStorageMap(zoneType: 'exclusion_zone'))
          .toList();

      await supabase.updateExclusionZones(
        propertyId: _property.id,
        zones: geoJsonZones,
      );

      // Update local property object
      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: _property.assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: geoJsonZones,
          specialZones: _property.specialZones,
          outerBoundary: _property.outerBoundary,
          recommendedPath: _property.recommendedPath,
          treatmentType: _property.treatmentType,
          lastApplication: _property.lastApplication,
          frequencyDays: _property.frequencyDays,
          nextDue: _property.nextDue,
          applicationRatePerAcre: _property.applicationRatePerAcre,
          applicationRateUnit: _property.applicationRateUnit,
          chemicalCostPerUnit: _property.chemicalCostPerUnit,
          defaultTankCapacityGallons: _property.defaultTankCapacityGallons,
          createdAt: _property.createdAt,
        );
        _prepareMapLayers();
      });

      if (mounted) {
        _showSnackBar(
          AppSnackBar.success(
            '${zones.length} exclusion zone${zones.length != 1 ? 's' : ''} saved.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(AppSnackBar.error('Could not save exclusion zones.'));
      }
    }
  }

  Future<void> _saveOuterBoundary(List<LatLng>? boundaryPoints) async {
    try {
      final supabase = context.read<SupabaseService>();
      final geoJsonBoundary =
          (boundaryPoints == null || boundaryPoints.length < 3)
              ? null
              : {
                  'type': 'Polygon',
                  'coordinates': [
                    boundaryPoints
                        .map((p) => [p.longitude, p.latitude])
                        .toList(growable: false),
                  ],
                };

      await supabase.updateOuterBoundary(
        propertyId: _property.id,
        outerBoundary: geoJsonBoundary,
      );

      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: _property.assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: _property.exclusionZones,
          specialZones: _property.specialZones,
          outerBoundary: geoJsonBoundary,
          recommendedPath: _property.recommendedPath,
          treatmentType: _property.treatmentType,
          lastApplication: _property.lastApplication,
          frequencyDays: _property.frequencyDays,
          nextDue: _property.nextDue,
          applicationRatePerAcre: _property.applicationRatePerAcre,
          applicationRateUnit: _property.applicationRateUnit,
          chemicalCostPerUnit: _property.chemicalCostPerUnit,
          defaultTankCapacityGallons: _property.defaultTankCapacityGallons,
          createdAt: _property.createdAt,
        );
        _prepareMapLayers();
      });

      if (mounted) {
        _showSnackBar(
          AppSnackBar.success(
            geoJsonBoundary == null
                ? 'Outer boundary cleared.'
                : 'Outer boundary saved.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(AppSnackBar.error('Could not save the outer boundary.'));
      }
    }
  }

  Future<void> _saveAssignments(List<String> assignedTo) async {
    try {
      setState(() => _isAssigning = true);
      final supabase = context.read<SupabaseService>();

      await supabase.updatePropertyAssignments(
        propertyId: _property.id,
        assignedTo: assignedTo,
      );

      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: _property.exclusionZones,
          specialZones: _property.specialZones,
          outerBoundary: _property.outerBoundary,
          recommendedPath: _property.recommendedPath,
          treatmentType: _property.treatmentType,
          lastApplication: _property.lastApplication,
          frequencyDays: _property.frequencyDays,
          nextDue: _property.nextDue,
          applicationRatePerAcre: _property.applicationRatePerAcre,
          applicationRateUnit: _property.applicationRateUnit,
          chemicalCostPerUnit: _property.chemicalCostPerUnit,
          defaultTankCapacityGallons: _property.defaultTankCapacityGallons,
          createdAt: _property.createdAt,
        );
      });

      if (mounted) {
        _showSnackBar(
          AppSnackBar.success(
            'Assignments saved for ${assignedTo.length} worker${assignedTo.length == 1 ? '' : 's'}.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(AppSnackBar.error('Could not save worker assignments.'));
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  bool get _canManageRecommendedPath {
    if (_currentUser == null || !_property.hasMapData()) return false;

    final role = (_currentUser!.role).toLowerCase();
    if (role == 'corporate_admin') return true;
    if (role == 'worker') return false;
    return _property.ownerId == _currentUser!.id;
  }

  bool get _hasRecommendedPath => _recommendedPathDashed.isNotEmpty;

  Future<void> _generateRecommendedPath() async {
    final boundary = _effectiveBoundaryGeoJson();
    if (boundary == null) {
      if (!mounted) return;
      _showSnackBar(
        AppSnackBar.warning(
          'Set an outer boundary or import a polygon map before generating a path.',
        ),
      );
      return;
    }

    try {
      setState(() => _isGeneratingRecommendedPath = true);
      final service = RecommendedPathService();
      final result = service.generate(
        boundaryGeoJson: boundary,
        exclusionZones: _property.exclusionZones ?? const [],
        swathWidthFeet: _currentSwathWidthFeet,
      );

      final supabase = context.read<SupabaseService>();
      await supabase.updateRecommendedPath(
        propertyId: _property.id,
        recommendedPath: result.geoJson,
      );

      if (!mounted) return;
      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: _property.assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: _property.exclusionZones,
          specialZones: _property.specialZones,
          outerBoundary: _property.outerBoundary,
          recommendedPath: result.geoJson,
          treatmentType: _property.treatmentType,
          lastApplication: _property.lastApplication,
          frequencyDays: _property.frequencyDays,
          nextDue: _property.nextDue,
          applicationRatePerAcre: _property.applicationRatePerAcre,
          applicationRateUnit: _property.applicationRateUnit,
          chemicalCostPerUnit: _property.chemicalCostPerUnit,
          defaultTankCapacityGallons: _property.defaultTankCapacityGallons,
          createdAt: _property.createdAt,
        );
        _prepareMapLayers();
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
          AppSnackBar.error('Path generation failed. Please try again.'));
    } finally {
      if (mounted) {
        setState(() => _isGeneratingRecommendedPath = false);
      }
    }
  }

  Future<void> _clearRecommendedPath() async {
    try {
      setState(() => _isGeneratingRecommendedPath = true);
      final supabase = context.read<SupabaseService>();
      await supabase.clearRecommendedPath(propertyId: _property.id);

      if (!mounted) return;
      setState(() {
        _property = Property(
          id: _property.id,
          name: _property.name,
          address: _property.address,
          notes: _property.notes,
          ownerId: _property.ownerId,
          assignedTo: _property.assignedTo,
          mapGeojson: _property.mapGeojson,
          orthomosaicUrl: _property.orthomosaicUrl,
          exclusionZones: _property.exclusionZones,
          specialZones: _property.specialZones,
          outerBoundary: _property.outerBoundary,
          recommendedPath: null,
          treatmentType: _property.treatmentType,
          lastApplication: _property.lastApplication,
          frequencyDays: _property.frequencyDays,
          nextDue: _property.nextDue,
          applicationRatePerAcre: _property.applicationRatePerAcre,
          applicationRateUnit: _property.applicationRateUnit,
          chemicalCostPerUnit: _property.chemicalCostPerUnit,
          defaultTankCapacityGallons: _property.defaultTankCapacityGallons,
          createdAt: _property.createdAt,
        );
        _prepareMapLayers();
      });

      _showSnackBar(AppSnackBar.success('Recommended path cleared.'));
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(AppSnackBar.error('Could not clear the recommended path.'));
    } finally {
      if (mounted) {
        setState(() => _isGeneratingRecommendedPath = false);
      }
    }
  }

  Map<String, dynamic>? _effectiveBoundaryGeoJson() {
    if (_property.outerBoundary != null) {
      return _property.outerBoundary;
    }
    return _extractPolygonFromAnyGeoJson(_property.mapGeojson);
  }

  Map<String, dynamic>? _extractPolygonFromAnyGeoJson(
      Map<String, dynamic>? rawGeoJson) {
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
      final features = rawGeoJson['features'] as List;
      for (final feature in features) {
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

  List<Polyline> _buildRecommendedPathPreview(dynamic rawPath) {
    final segments = _extractRecommendedPathSegments(rawPath);
    if (segments.isEmpty) return const [];

    final dashes = <Polyline>[];
    for (final segment in segments) {
      dashes.addAll(_dashPolyline(segment));
    }
    return dashes;
  }

  List<List<LatLng>> _extractRecommendedPathSegments(dynamic rawPath) {
    if (rawPath == null) return const [];

    final segments = <List<LatLng>>[];

    void readLineCoordinates(dynamic coordinates) {
      if (coordinates is! List) return;
      final points = <LatLng>[];
      for (final c in coordinates) {
        if (c is List && c.length >= 2) {
          final a = c[0];
          final b = c[1];
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
      if (points.length >= 2) {
        segments.add(points);
      }
    }

    if (rawPath is Map) {
      final map = Map<String, dynamic>.from(rawPath);
      final type = (map['type'] ?? '').toString();

      if (type == 'LineString') {
        readLineCoordinates(map['coordinates']);
      } else if (type == 'MultiLineString' && map['coordinates'] is List) {
        for (final line in map['coordinates'] as List) {
          readLineCoordinates(line);
        }
      } else if (type == 'FeatureCollection' && map['features'] is List) {
        for (final feature in map['features'] as List) {
          if (feature is Map && feature['geometry'] is Map) {
            final geometry = Map<String, dynamic>.from(
                feature['geometry'] as Map<dynamic, dynamic>);
            final geometryType = (geometry['type'] ?? '').toString();
            if (geometryType == 'LineString') {
              readLineCoordinates(geometry['coordinates']);
            } else if (geometryType == 'MultiLineString' &&
                geometry['coordinates'] is List) {
              for (final line in geometry['coordinates'] as List) {
                readLineCoordinates(line);
              }
            }
          }
        }
      }
    } else if (rawPath is List) {
      readLineCoordinates(rawPath);
    }

    return segments;
  }

  List<Polyline> _dashPolyline(List<LatLng> points) {
    if (points.length < 2) return const [];

    const dashMeters = 9.0;
    const gapMeters = 7.0;
    const distance = Distance();
    final output = <Polyline>[];

    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final totalMeters = distance(start, end);
      if (totalMeters <= 0) continue;

      final dashT = (dashMeters / totalMeters).clamp(0.0, 1.0);
      final stepT = ((dashMeters + gapMeters) / totalMeters).clamp(0.0, 1.0);
      if (stepT <= 0) continue;

      for (double t = 0; t < 1; t += stepT) {
        final t2 = (t + dashT).clamp(0.0, 1.0);
        output.add(
          Polyline(
            points: [_lerpLatLng(start, end, t), _lerpLatLng(start, end, t2)],
            strokeWidth: 3,
            color: const Color(0xFF26A69A),
          ),
        );
      }
    }

    return output;
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + ((b.latitude - a.latitude) * t),
      a.longitude + ((b.longitude - a.longitude) * t),
    );
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
            color: Colors.red.withValues(alpha: 0.2),
            borderColor: Colors.red,
            borderStrokeWidth: 2,
            isFilled: true,
          ),
        );
      }
    }

    return polygons;
  }

  List<_ExclusionNotePin> _buildExclusionNotePins(
      List<Map<String, dynamic>>? zones) {
    if (zones == null || zones.isEmpty) return const [];

    final pins = <_ExclusionNotePin>[];
    for (final zone in zones) {
      final note = zone['note']?.toString().trim();
      if (note == null || note.isEmpty) continue;

      final polygonGeoJson = _extractExclusionPolygonGeoJson(zone);
      if (polygonGeoJson == null) continue;
      final ring = _extractPolygonVertices(polygonGeoJson);
      if (ring.length < 3) continue;

      final centroid = _centroid(ring);
      pins.add(
        _ExclusionNotePin(
          point: centroid,
          note: note,
        ),
      );
    }

    return pins;
  }

  Map<String, dynamic>? _extractExclusionPolygonGeoJson(
      Map<String, dynamic> zone) {
    if (zone['polygon'] is Map) {
      final polygon =
          Map<String, dynamic>.from(zone['polygon'] as Map<dynamic, dynamic>);
      if ((polygon['type'] ?? '').toString() == 'Polygon') {
        return polygon;
      }
    }

    if ((zone['type'] ?? '').toString() == 'Polygon') {
      return zone;
    }

    return null;
  }

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    final lat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lng =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(lat, lng);
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
        vertices.add(
          LatLng((vertex[1] as num).toDouble(), (vertex[0] as num).toDouble()),
        );
      }
    }
    return vertices;
  }

  List<Polyline> _buildDashedBoundary(List<LatLng> points) {
    if (points.length < 2) return const [];

    final closed = List<LatLng>.from(points);
    if (closed.first.latitude != closed.last.latitude ||
        closed.first.longitude != closed.last.longitude) {
      closed.add(closed.first);
    }

    final segments = <Polyline>[];
    for (var i = 0; i < closed.length - 1; i++) {
      if (i.isEven) {
        segments.add(
          Polyline(
            points: [closed[i], closed[i + 1]],
            strokeWidth: 3,
            color: const Color(0xFFFBC02D),
          ),
        );
      }
    }
    return segments;
  }

  double? _estimateAcres() {
    if (_mapBounds == null) return null;
    const distance = Distance();
    final midLat = (_mapBounds!.north + _mapBounds!.south) / 2;

    final widthMeters = distance(
      LatLng(midLat, _mapBounds!.west),
      LatLng(midLat, _mapBounds!.east),
    );
    final heightMeters = distance(
      LatLng(_mapBounds!.south, _mapBounds!.west),
      LatLng(_mapBounds!.north, _mapBounds!.west),
    );

    final areaSqMeters = widthMeters * heightMeters;
    return areaSqMeters / 4046.8564224;
  }

  DateTime? _lastTrackedDate() {
    if (_sessions.isEmpty) return null;
    final latest = _sessions
        .map((s) => s.startTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return latest;
  }

  Widget _buildHeroImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 230,
        width: double.infinity,
        child: _property.hasOrthomosaic()
            ? Image.network(
                _property.orthomosaicUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _heroFallback(),
              )
            : _heroFallback(),
      ),
    );
  }

  Widget _heroFallback() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.secondaryContainer.withValues(alpha: 0.42),
            scheme.surfaceContainerHighest.withValues(alpha: 0.88),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
              ),
              child: Text(
                'Preview',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 48,
            bottom: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.16)),
              ),
              child: Stack(
                children: [
                  for (int i = 0; i < 6; i++)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 16 + (i * 24),
                      child: Container(
                        height: 2,
                        color: scheme.primary.withValues(alpha: 0.14),
                      ),
                    ),
                  for (int i = 0; i < 5; i++)
                    Positioned(
                      top: 14,
                      bottom: 14,
                      left: 18 + (i * 52),
                      child: Container(
                        width: 2,
                        color: scheme.tertiary.withValues(alpha: 0.14),
                      ),
                    ),
                  Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.map_outlined,
                      size: 38,
                      color: scheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Icon(
                      Icons.navigation,
                      size: 20,
                      color: scheme.secondary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({required String label, required String value}) {
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPanel() {
    if (_mapBounds == null) {
      return AppCard(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              SizedBox(
                height: 360,
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(34.1656, -84.7999),
                    initialZoom: 18,
                    interactionOptions:
                        InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _satelliteUrlTemplate,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Setup - Walk Boundaries',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Walk the edge, tap Finish when done. Drone import is still the preferred and most accurate mode when available.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openBoundarySetupWizard,
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('Quick Setup - Walk Boundaries'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              _currentUser == null ? null : _openWebODMBuilder,
                          icon: const Icon(Icons.add_chart_outlined),
                          label: const Text('Import Drone Map (Preferred)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(
            (_mapBounds!.south + _mapBounds!.north) / 2,
            (_mapBounds!.west + _mapBounds!.east) / 2,
          ),
          initialZoom: 18,
        ),
        children: [
          TileLayer(
            urlTemplate: _property.hasOrthomosaic()
                ? 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
                : _satelliteUrlTemplate,
            subdomains:
                _property.hasOrthomosaic() ? const ['a', 'b', 'c'] : const [],
          ),
          if (_property.hasOrthomosaic())
            OverlayImageLayer(
              overlayImages: [
                OverlayImage(
                  bounds: _mapBounds!,
                  opacity: 0.9,
                  imageProvider: NetworkImage(_property.orthomosaicUrl!),
                ),
              ],
            ),
          if (_boundaryPoints.length >= 3)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: _boundaryPoints,
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderColor: Colors.blue,
                  borderStrokeWidth: 2,
                  isFilled: true,
                ),
              ],
            ),
          if (_outerBoundaryDashed.isNotEmpty)
            PolylineLayer(polylines: _outerBoundaryDashed),
          if (_exclusionPolygons.isNotEmpty)
            PolygonLayer(polygons: _exclusionPolygons),
          if (_exclusionNotePins.isNotEmpty)
            MarkerLayer(
              markers: _exclusionNotePins
                  .map(
                    (pin) => Marker(
                      point: pin.point,
                      width: 26,
                      height: 26,
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Exclusion Zone Note'),
                              content: Text(pin.note),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.8),
                          ),
                          child: const Icon(
                            Icons.sticky_note_2_outlined,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (_recommendedPathDashed.isNotEmpty)
            PolylineLayer(polylines: _recommendedPathDashed),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isCompactLayout) {
    final mapButton = OutlinedButton.icon(
      onPressed: _currentUser == null ? null : _openWebODMBuilder,
      icon: const Icon(Icons.map_outlined),
      label: Text(
        _property.hasMapData()
            ? 'Update Drone Map (Preferred)'
            : 'Import Drone Map (Preferred)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final exclusionButton = OutlinedButton.icon(
      onPressed: _openExclusionZoneDrawer,
      icon: const Icon(Icons.edit_location_alt_outlined),
      label: const Text(
        'Draw Exclusion Zones',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (isCompactLayout) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: mapButton),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: exclusionButton),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openBoundarySetupWizard,
              icon: const Icon(Icons.directions_walk),
              label: const Text(
                'Quick Setup - Walk Boundaries',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: mapButton),
            const SizedBox(width: 16),
            Expanded(child: exclusionButton),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openBoundarySetupWizard,
            icon: const Icon(Icons.directions_walk),
            label: const Text(
              'Quick Setup - Walk Boundaries',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final estimatedAcres = _estimateAcres();
    final lastTracked = _lastTrackedDate();

    return Scaffold(
      appBar: AppBar(
        title: Text(_property.name),
        actions: [
          IconButton(
            onPressed: _showEditPropertyDialog,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit property',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      _buildHeroImage(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _statCard(
                            label: 'Acres',
                            value: estimatedAcres == null
                                ? 'N/A'
                                : AppFormat.acres(estimatedAcres),
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            label: 'Last Tracked',
                            value: lastTracked == null
                                ? 'Never'
                                : DateFormat.yMMMd().format(lastTracked),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTreatmentPlannerCard(),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 260.ms)
                    .slideY(begin: 0.04, end: 0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _buildMapPanel(),
                  ),
                ).animate().fadeIn(delay: 90.ms, duration: 260.ms),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactLayout = constraints.maxWidth < 640;

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FloatingActionButton.extended(
                      heroTag: 'start_tracking_fab',
                      onPressed: _isLoading ? null : _startTracking,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Tracking'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButtons(isCompactLayout),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _property.hasMapData()
                          ? _openOuterBoundaryDrawer
                          : null,
                      icon: const Icon(Icons.polyline_outlined),
                      label: Text(
                        _property.hasOuterBoundary()
                            ? 'Update Outer Boundary'
                            : 'Set Outer Boundary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_canManageRecommendedPath) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isGeneratingRecommendedPath
                            ? null
                            : _generateRecommendedPath,
                        icon: Icon(
                          _hasRecommendedPath
                              ? Icons.refresh_outlined
                              : Icons.route_outlined,
                        ),
                        label: Text(
                          _isGeneratingRecommendedPath
                              ? 'Generating...'
                              : (_hasRecommendedPath
                                  ? 'Regenerate Recommended Path'
                                  : 'Generate Recommended Path'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_hasRecommendedPath) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isGeneratingRecommendedPath
                              ? null
                              : _clearRecommendedPath,
                          icon: const Icon(Icons.layers_clear_outlined),
                          label: const Text('Clear Path'),
                        ),
                      ),
                    ],
                  ],
                  if ((_currentUser?.role ?? '').toLowerCase() ==
                      'corporate_admin') ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showAssignWorkersSheet,
                        icon: const Icon(Icons.group_outlined),
                        label: Text(
                          'Assign to Worker (${_property.assignedTo.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackingStartConfig {
  const _TrackingStartConfig({
    required this.tankCapacityGallons,
    required this.applicationRatePerAcre,
    required this.applicationRateUnit,
    required this.chemicalCostPerUnit,
  });

  final double? tankCapacityGallons;
  final double? applicationRatePerAcre;
  final String applicationRateUnit;
  final double? chemicalCostPerUnit;
}

class _ExclusionNotePin {
  const _ExclusionNotePin({
    required this.point,
    required this.note,
  });

  final LatLng point;
  final String note;
}







