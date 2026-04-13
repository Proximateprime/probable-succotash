// ignore_for_file: unused_element
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/property_model.dart';
import '../utils/map_tile_defaults.dart';

class OuterBoundaryDrawScreen extends StatefulWidget {
  const OuterBoundaryDrawScreen({
    Key? key,
    required this.property,
    required this.onBoundarySaved,
  }) : super(key: key);

  final Property property;
  final Future<void> Function(List<LatLng>? boundaryPoints) onBoundarySaved;

  @override
  State<OuterBoundaryDrawScreen> createState() =>
      _OuterBoundaryDrawScreenState();
}

class _OuterBoundaryDrawScreenState extends State<OuterBoundaryDrawScreen> {
    bool _editMode = false;
    int? _draggingIdx;
  late final MapController _mapController;

  final List<LatLng> _outerBoundaryPoints = [];
  bool _isSaving = false;
  double _bufferFeet = 0.0;

  late LatLng _mapCenter;
  late double _mapZoom;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _bufferFeet = widget.property.outerBoundaryBufferFeet ?? 0.0;
    _initializeMapCenter();
    _loadExistingBoundary();
  }

  void _initializeMapCenter() {
    final mapPoints = _extractGeoPoints(widget.property.mapGeojson);
    final boundaryPoints =
        _extractPolygonVertices(widget.property.outerBoundary);
    final seedPoints = mapPoints.isNotEmpty ? mapPoints : boundaryPoints;

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

  void _loadExistingBoundary() {
    final current = _extractPolygonVertices(widget.property.outerBoundary);
    if (current.isNotEmpty) {
      _outerBoundaryPoints
        ..clear()
        ..addAll(current);
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
      if (_editMode) return; // Disable tap-to-add in edit mode
    setState(() {
      _appendSmoothedPoint(point);
    });
  }

  void _appendSmoothedPoint(LatLng point) {
    if (_outerBoundaryPoints.isEmpty) {
      _outerBoundaryPoints.add(point);
      return;
    }

    final prev = _outerBoundaryPoints.last;
    final distance = const Distance().as(LengthUnit.Meter, prev, point);

    if (distance < 1.5) {
      return;
    }

    final steps = (distance / 5.0).floor();
    for (var i = 1; i <= steps; i++) {
      final t = i / (steps + 1);
      _outerBoundaryPoints.add(
        LatLng(
          prev.latitude + (point.latitude - prev.latitude) * t,
          prev.longitude + (point.longitude - prev.longitude) * t,
        ),
      );
    }

    _outerBoundaryPoints.add(point);
  }

  void _undoLastPoint() {
    if (_outerBoundaryPoints.isEmpty) return;
    setState(() => _outerBoundaryPoints.removeLast());
  }

  void _clearBoundary() {
    setState(() => _outerBoundaryPoints.clear());
  }

  Future<void> _saveBoundary() async {
    if (_outerBoundaryPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least 3 points to save an outer boundary.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      var points = List<LatLng>.from(_outerBoundaryPoints);
      if (!_samePoint(points.first, points.last)) {
        points.add(points.first);
      }
      if (_bufferFeet > 0) {
        points = _applyBuffer(points, _bufferFeet * 0.3048);
      }

      await widget.onBoundarySaved(points);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving outer boundary: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-8 &&
        (a.longitude - b.longitude).abs() < 1e-8;
  }

  /// Expands every vertex outward from the centroid by [bufferMeters].
  List<LatLng> _applyBuffer(List<LatLng> ring, double bufferMeters) {
    if (ring.isEmpty || bufferMeters <= 0) return ring;
    // Drop duplicate closing point for centroid computation.
    final pts =
        (ring.length >= 2 && _samePoint(ring.first, ring.last))
            ? ring.sublist(0, ring.length - 1)
            : ring;
    if (pts.isEmpty) return ring;
    const metersPerDegLat = 111320.0;
    final centLat =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final centLng =
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    final cosLat = math.cos(centLat * math.pi / 180);
    final expanded = pts.map((p) {
      final dLatM = (p.latitude - centLat) * metersPerDegLat;
      final dLngM = (p.longitude - centLng) * metersPerDegLat * cosLat;
      final dist = math.sqrt(dLatM * dLatM + dLngM * dLngM);
      if (dist < 1e-6) return p;
      final scale = (dist + bufferMeters) / dist;
      return LatLng(
        centLat + (p.latitude - centLat) * scale,
        centLng + (p.longitude - centLng) * scale,
      );
    }).toList();
    expanded.add(expanded.first); // re-close ring
    return expanded;
  }

  List<LatLng> _closedBoundary() {
    if (_outerBoundaryPoints.length < 3) {
      return List<LatLng>.from(_outerBoundaryPoints);
    }
    final points = List<LatLng>.from(_outerBoundaryPoints);
    if (!_samePoint(points.first, points.last)) {
      points.add(points.first);
    }
    return points;
  }

  List<Polyline> _dashedLines(List<LatLng> points) {
    if (points.length < 2) return const [];

    final lines = <Polyline>[];
    for (var i = 0; i < points.length - 1; i++) {
      if (i.isEven) {
        lines.add(
          Polyline(
            points: [points[i], points[i + 1]],
            strokeWidth: 3,
            color: const Color(0xFF2E7D32),
          ),
        );
      }
    }
    return lines;
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

  @override
  Widget build(BuildContext context) {
    final closedBoundary = _closedBoundary();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Outer Boundary'),
      ),
      body: Stack(
        children: [
          Listener(
            onPointerMove: (event) {
              if (_editMode && _draggingIdx != null) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final local = box.globalToLocal(event.position);
                  final latLng = _mapController.camera.pointToLatLng(math.Point(local.dx, local.dy));
                  setState(() {
                    _outerBoundaryPoints[_draggingIdx!] = latLng;
                  });
                }
              }
            },
            onPointerUp: (_) {
              if (_editMode && _draggingIdx != null) {
                setState(() {
                  _draggingIdx = null;
                });
              }
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: MapTileDefaults.userAgent,
                  errorImage: MapTileDefaults.offlineTileImage,
                  evictErrorTileStrategy:
                      EvictErrorTileStrategy.notVisibleRespectMargin,
                ),
                if (closedBoundary.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: closedBoundary,
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.16),
                        borderColor: const Color(0xFF2E7D32),
                        borderStrokeWidth: 2,
                        isFilled: true,
                      ),
                    ],
                  ),
                // Dashed preview outline in edit mode
                if (_editMode && closedBoundary.length >= 3)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: closedBoundary,
                        strokeWidth: 3,
                        color: Colors.blueAccent,
                        isDotted: true,
                      ),
                    ],
                  ),
                if (_outerBoundaryPoints.isNotEmpty)
                  MarkerLayer(
                    markers: _outerBoundaryPoints.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final pt = entry.value;
                      return Marker(
                        point: pt,
                        width: _editMode ? 32 : 12,
                        height: _editMode ? 32 : 12,
                        child: GestureDetector(
                          onPanStart: _editMode
                              ? (_) {
                                  setState(() {
                                    _draggingIdx = idx;
                                  });
                                }
                              : null,
                          onPanEnd: _editMode
                              ? (_) {
                                  setState(() {
                                    _draggingIdx = null;
                                  });
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _editMode ? Colors.amber : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _editMode ? Colors.amber : const Color(0xFF2E7D32),
                                width: _editMode ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Points: ${_outerBoundaryPoints.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _editMode
                          ? 'Drag points to adjust boundary'
                          : 'Tap to draw the max spray area',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (_outerBoundaryPoints.length >= 3)
                      ElevatedButton.icon(
                        icon: Icon(_editMode ? Icons.check : Icons.edit),
                        label: Text(_editMode ? 'Done Adjusting' : 'Adjust Boundary'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _editMode ? Colors.green : Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 36),
                        ),
                        onPressed: () {
                          setState(() {
                            _editMode = !_editMode;
                            _draggingIdx = null;
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 88,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: _undoLastPoint,
                  tooltip: 'Undo last point',
                  heroTag: 'boundary_undo',
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.undo),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  onPressed: _clearBoundary,
                  tooltip: 'Clear boundary',
                  heroTag: 'boundary_clear',
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.clear),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Buffer slider ────────────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.expand_outlined,
                          color: Colors.white70, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Outward buffer: ${_bufferFeet.toStringAsFixed(0)} ft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _bufferFeet,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          label: '${_bufferFeet.toStringAsFixed(0)} ft',
                          onChanged: (v) => setState(() => _bufferFeet = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
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
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveBoundary,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save Boundary'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                          ),
                        ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// BoxBoundaryDrawScreen — tap two diagonal corners → axis-aligned rectangle
// ═══════════════════════════════════════════════════════════════════════════════

class BoxBoundaryDrawScreen extends StatefulWidget {
  const BoxBoundaryDrawScreen({
    Key? key,
    required this.property,
    required this.onBoundarySaved,
  }) : super(key: key);

  final Property property;
  final Future<void> Function(List<LatLng>? boundaryPoints) onBoundarySaved;

  @override
  State<BoxBoundaryDrawScreen> createState() => _BoxBoundaryDrawScreenState();
}

class _BoxBoundaryDrawScreenState extends State<BoxBoundaryDrawScreen> {
  late final MapController _mapController;

  final List<LatLng> _corners = []; // 0, 1, or 2 points
  bool _isSaving = false;
  double _bufferFeet = 0.0;
  bool _editMode = false;
  int? _draggingCornerIdx;

  late LatLng _mapCenter;
  late double _mapZoom;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _bufferFeet = widget.property.outerBoundaryBufferFeet ?? 0.0;
    _initializeMapCenter();
  }

  void _initializeMapCenter() {
    final outer = _extractPolygonVertices(widget.property.outerBoundary);
    final seed = outer.isNotEmpty
        ? outer
        : _extractGeoPoints(widget.property.mapGeojson);

    if (seed.isNotEmpty) {
      var minLat = seed.first.latitude;
      var maxLat = seed.first.latitude;
      var minLng = seed.first.longitude;
      var maxLng = seed.first.longitude;
      for (final p in seed) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      _mapZoom = 18;
      return;
    }
    _mapCenter = const LatLng(34.1656, -84.7999);
    _mapZoom = 15;
  }

  void _onMapTap(TapPosition _, LatLng point) {
    if (_editMode) return; // Disable tap-to-set in edit mode
    setState(() {
      if (_corners.length >= 2) _corners.clear();
      _corners.add(point);
    });
  }

  /// Returns a closed 5-point ring for the axis-aligned rectangle.
  List<LatLng> _rectangleRing() {
    if (_corners.length < 2) return const [];
    final p1 = _corners[0];
    final p2 = _corners[1];
    final minLat = p1.latitude < p2.latitude ? p1.latitude : p2.latitude;
    final maxLat = p1.latitude > p2.latitude ? p1.latitude : p2.latitude;
    final minLng = p1.longitude < p2.longitude ? p1.longitude : p2.longitude;
    final maxLng = p1.longitude > p2.longitude ? p1.longitude : p2.longitude;
    final sw = LatLng(minLat, minLng);
    return [
      sw,
      LatLng(maxLat, minLng),
      LatLng(maxLat, maxLng),
      LatLng(minLat, maxLng),
      sw, // close ring
    ];
  }

  /// Expands each vertex outward from the centroid by [bufferMeters].
  List<LatLng> _applyBuffer(List<LatLng> ring, double bufferMeters) {
    if (ring.isEmpty || bufferMeters <= 0) return ring;
    final pts = (ring.length >= 2 &&
            (ring.first.latitude - ring.last.latitude).abs() < 1e-10 &&
            (ring.first.longitude - ring.last.longitude).abs() < 1e-10)
        ? ring.sublist(0, ring.length - 1)
        : ring;
    if (pts.isEmpty) return ring;
    const metersPerDegLat = 111320.0;
    final centLat =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final centLng =
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    final cosLat = math.cos(centLat * math.pi / 180);
    final expanded = pts.map((p) {
      final dLatM = (p.latitude - centLat) * metersPerDegLat;
      final dLngM = (p.longitude - centLng) * metersPerDegLat * cosLat;
      final dist = math.sqrt(dLatM * dLatM + dLngM * dLngM);
      if (dist < 1e-6) return p;
      final scale = (dist + bufferMeters) / dist;
      return LatLng(
        centLat + (p.latitude - centLat) * scale,
        centLng + (p.longitude - centLng) * scale,
      );
    }).toList();
    expanded.add(expanded.first);
    return expanded;
  }

  Future<void> _saveBoundary() async {
    if (_corners.length < 2) return;
    setState(() => _isSaving = true);
    try {
      var ring = _rectangleRing();
      if (_bufferFeet > 0) ring = _applyBuffer(ring, _bufferFeet * 0.3048);
      await widget.onBoundarySaved(ring);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving boundary: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<LatLng> _extractPolygonVertices(Map<String, dynamic>? geo) {
    if (geo == null || geo['type'] != 'Polygon') return [];
    final coords = geo['coordinates'];
    if (coords is! List || coords.isEmpty || coords.first is! List) return [];
    final ring = coords.first as List;
    return ring
        .whereType<List>()
        .where((v) => v.length >= 2)
        .map((v) =>
            LatLng((v[1] as num).toDouble(), (v[0] as num).toDouble()))
        .toList();
  }

  List<LatLng> _extractGeoPoints(Map<String, dynamic>? geoJson) {
    if (geoJson == null) return [];
    final points = <LatLng>[];
    void collect(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('coordinates')) collect(node['coordinates']);
        if (node.containsKey('features') && node['features'] is List) {
          for (final f in node['features'] as List) { collect(f); }
        }
        if (node.containsKey('geometry')) collect(node['geometry']);
        return;
      }
      if (node is List) {
        if (node.length >= 2 && node[0] is num && node[1] is num) {
          points.add(
              LatLng((node[1] as num).toDouble(), (node[0] as num).toDouble()));
          return;
        }
        for (final child in node) { collect(child); }
      }
    }
    collect(geoJson);
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rectangleRing();
    final String instruction = _editMode
      ? 'Drag corners to adjust boundary'
      : _corners.isEmpty
        ? 'Tap corner 1 (any diagonal corner)'
        : _corners.length == 1
          ? 'Tap corner 2 (the opposite diagonal corner)'
          : 'Rectangle ready — save or tap to reset';

    return Scaffold(
      appBar: AppBar(title: const Text('Box / Property Boundary')),
      body: Stack(
        children: [
          Listener(
            onPointerMove: (event) {
              if (_editMode && _draggingCornerIdx != null) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final local = box.globalToLocal(event.position);
                  final latLng = _mapController.camera.pointToLatLng(math.Point(local.dx, local.dy));
                  setState(() {
                    _corners[_draggingCornerIdx!] = latLng;
                  });
                }
              }
            },
            onPointerUp: (_) {
              if (_editMode && _draggingCornerIdx != null) {
                setState(() {
                  _draggingCornerIdx = null;
                });
              }
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: MapTileDefaults.userAgent,
                  errorImage: MapTileDefaults.offlineTileImage,
                  evictErrorTileStrategy:
                      EvictErrorTileStrategy.notVisibleRespectMargin,
                ),
                if (rect.length >= 4)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: rect,
                        color: const Color(0xFF1565C0).withValues(alpha: 0.16),
                        borderColor: const Color(0xFF1565C0),
                        borderStrokeWidth: 2.5,
                        isFilled: true,
                      ),
                    ],
                  ),
                // Dashed preview outline in edit mode
                if (_editMode && rect.length >= 4)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: rect,
                        strokeWidth: 3,
                        color: Colors.blueAccent,
                        isDotted: true,
                      ),
                    ],
                  ),
                if (_corners.isNotEmpty)
                  MarkerLayer(
                    markers: _corners.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final pt = entry.value;
                      return Marker(
                        point: pt,
                        width: _editMode ? 52 : 30,
                        height: _editMode ? 52 : 30,
                        child: GestureDetector(
                          onPanStart: _editMode
                              ? (_) {
                                  setState(() {
                                    _draggingCornerIdx = idx;
                                  });
                                }
                              : null,
                          onPanEnd: _editMode
                              ? (_) {
                                  setState(() {
                                    _draggingCornerIdx = null;
                                  });
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: idx == 0
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF00796B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _editMode ? Colors.amber : Colors.white,
                                  width: _editMode ? 3 : 2),
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _editMode ? 16 : 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          // Info card and Adjust button
          Positioned(
            left: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instruction,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Corners: ${_corners.length}/2',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (_corners.length == 2)
                      ElevatedButton.icon(
                        icon: Icon(_editMode ? Icons.check : Icons.edit),
                        label: Text(_editMode ? 'Done Adjusting' : 'Adjust Boundary'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _editMode ? Colors.green : Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 36),
                        ),
                        onPressed: () {
                          setState(() {
                            _editMode = !_editMode;
                            _draggingCornerIdx = null;
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Buffer slider ────────────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.expand_outlined,
                          color: Colors.white70, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Outward buffer: ${_bufferFeet.toStringAsFixed(0)} ft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _bufferFeet,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          label: '${_bufferFeet.toStringAsFixed(0)} ft',
                          onChanged: (v) => setState(() => _bufferFeet = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSaving
                              ? null
                              : () => setState(() => _corners.clear()),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey),
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isSaving || _corners.length < 2)
                              ? null
                              : _saveBoundary,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save Boundary'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                          ),
                        ),
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











