import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/property_model.dart';
import '../models/exclusion_zone_model.dart';
import 'package:uuid/uuid.dart';

class ExclusionZoneDrawScreen extends StatefulWidget {
  final Property property;
  final Function(List<ExclusionZone>) onZonesSaved;

  const ExclusionZoneDrawScreen({
    Key? key,
    required this.property,
    required this.onZonesSaved,
  }) : super(key: key);

  @override
  State<ExclusionZoneDrawScreen> createState() =>
      _ExclusionZoneDrawScreenState();
}

class _ExclusionZoneDrawScreenState extends State<ExclusionZoneDrawScreen> {
  late MapController _mapController;
  final List<ExclusionZone> _completedZones = [];
  final List<LatLng> _currentPolygon = [];
  bool _isDrawing = false;
  bool _isSaving = false;

  // For map projection (estimate bounds from map geojson if available)
  late LatLng _mapCenter;
  late double _mapZoom;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeMapCenter();
    // Load existing zones if any
    _loadExistingZones();
  }

  void _initializeMapCenter() {
    final mapPoints = _extractGeoPoints(widget.property.mapGeojson);
    final zonePoints = _extractZoneVertices(widget.property.exclusionZones);
    final seedPoints = mapPoints.isNotEmpty ? mapPoints : zonePoints;

    if (seedPoints.isNotEmpty) {
      final bounds = _buildBounds(seedPoints);
      if (bounds != null) {
        _mapCenter = LatLng(
          (bounds.north + bounds.south) / 2,
          (bounds.east + bounds.west) / 2,
        );
        _mapZoom = 18;
        return;
      }
    }

    _mapCenter = const LatLng(34.1656, -84.7999);
    _mapZoom = 15;
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
          points.add(
              LatLng((node[1] as num).toDouble(), (node[0] as num).toDouble()));
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

  List<LatLng> _extractZoneVertices(List<Map<String, dynamic>>? zones) {
    if (zones == null || zones.isEmpty) return const [];
    final points = <LatLng>[];
    for (final zone in zones) {
      final existingZone = ExclusionZone.fromGeoJSON(zone);
      points.addAll(existingZone.vertices);
    }
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

  void _loadExistingZones() {
    if (widget.property.hasExclusionZones()) {
      for (final zone in widget.property.exclusionZones!) {
        final existingZone = ExclusionZone.fromGeoJSON(zone);
        if (existingZone.vertices.length >= 3) {
          _completedZones.add(existingZone);
        }
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      if (!_isDrawing) {
        _isDrawing = true;
        _currentPolygon.clear();
      }
      _appendSmoothedPoint(point);
    });
  }

  void _appendSmoothedPoint(LatLng point) {
    if (_currentPolygon.isEmpty) {
      _currentPolygon.add(point);
      return;
    }

    final previous = _currentPolygon.last;
    final distanceMeters =
        const Distance().as(LengthUnit.Meter, previous, point);

    if (distanceMeters < 1.5) {
      return;
    }

    final steps = (distanceMeters / 5.0).floor();
    for (var i = 1; i <= steps; i++) {
      final t = i / (steps + 1);
      _currentPolygon.add(
        LatLng(
          previous.latitude + (point.latitude - previous.latitude) * t,
          previous.longitude + (point.longitude - previous.longitude) * t,
        ),
      );
    }

    _currentPolygon.add(point);
  }

  void _undoLastPoint() {
    if (_currentPolygon.isNotEmpty) {
      setState(() {
        _currentPolygon.removeLast();
      });
    }
  }

  Future<void> _finishPolygon() async {
    if (_currentPolygon.length >= 3) {
      // Close polygon by adding first point again if not already
      if (!_samePoint(_currentPolygon.last, _currentPolygon.first)) {
        _currentPolygon.add(_currentPolygon.first);
      }

      final note = await _promptZoneNote();
      if (!mounted) return;

      final zone = ExclusionZone(
        id: const Uuid().v4(),
        vertices: List.from(_currentPolygon),
        createdAt: DateTime.now(),
        notes: note,
      );

      setState(() {
        _completedZones.add(zone);
        _currentPolygon.clear();
        _isDrawing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zone ${_completedZones.length} saved'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least 3 points to create a zone'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _promptZoneNote() async {
    final controller = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add note for this exclusion zone?'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText:
                'e.g. Septic field - no spray, Bee hive - keep 50 ft away',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save Note'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-8 &&
        (a.longitude - b.longitude).abs() < 1e-8;
  }

  void _removeLastZone() {
    if (_completedZones.isEmpty) return;
    setState(() {
      _completedZones.removeLast();
    });
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Zones?'),
        content: Text(
          'Delete all ${_completedZones.length} completed zones and current drawing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _completedZones.clear();
                _currentPolygon.clear();
                _isDrawing = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All zones cleared')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _saveZones() async {
    if (_isDrawing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish current drawing first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_completedZones.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await Future.delayed(const Duration(milliseconds: 300)); // Simulate save
      widget.onZonesSaved(_completedZones);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${_completedZones.length} zones saved'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Exclusion Zones'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                '${_completedZones.length} zone${_completedZones.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map with zones and current drawing
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: _mapZoom,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              // Render completed zones as red polygons
              if (_completedZones.isNotEmpty)
                PolygonLayer(
                  polygons: _completedZones
                      .map(
                        (zone) => Polygon(
                          points: zone.vertices,
                          color: Colors.red.withValues(alpha: 0.3),
                          borderStrokeWidth: 2,
                          borderColor: Colors.red,
                          isFilled: true,
                        ),
                      )
                      .toList(),
                ),
              // Render current drawing polygon
              if (_currentPolygon.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _currentPolygon,
                      color: Colors.orange.withValues(alpha: 0.3),
                      borderStrokeWidth: 2,
                      borderColor: Colors.orange,
                      isFilled: true,
                    ),
                  ],
                ),
              // Render current drawing points as markers
              if (_currentPolygon.isNotEmpty)
                MarkerLayer(
                  markers: _currentPolygon
                      .asMap()
                      .entries
                      .map(
                        (entry) => Marker(
                          point: entry.value,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.orangeAccent,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${entry.key + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
          // Drawing controls panel (bottom-left)
          Positioned(
            left: 12,
            bottom: 80,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: _undoLastPoint,
                  tooltip: 'Undo last point',
                  heroTag: 'undo',
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.undo),
                ),
                const SizedBox(height: 8),
                if (_isDrawing)
                  FloatingActionButton.small(
                    onPressed: _finishPolygon,
                    tooltip: 'Finish polygon',
                    heroTag: 'finish',
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.check),
                  ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  onPressed: _removeLastZone,
                  tooltip: 'Remove last completed zone',
                  heroTag: 'remove_last_zone',
                  backgroundColor: Colors.deepOrange,
                  child: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          // Info panel (top-left)
          Positioned(
            left: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDrawing ? 'Drawing...' : 'Ready',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Points: ${_currentPolygon.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap map to draw. Finish to save polygon.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _clearAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Clear All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveZones,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save Zones'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
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

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
