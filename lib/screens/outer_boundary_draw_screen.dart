import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/property_model.dart';

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
  late final MapController _mapController;

  final List<LatLng> _outerBoundaryPoints = [];
  bool _isSaving = false;

  late LatLng _mapCenter;
  late double _mapZoom;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
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
      final points = List<LatLng>.from(_outerBoundaryPoints);
      if (!_samePoint(points.first, points.last)) {
        points.add(points.first);
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
            color: const Color(0xFFFBC02D),
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
              if (closedBoundary.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: closedBoundary,
                      color: const Color(0xFFFBC02D).withValues(alpha: 0.18),
                      borderColor: const Color(0xFFFBC02D),
                      borderStrokeWidth: 2,
                      isFilled: true,
                    ),
                  ],
                ),
              if (closedBoundary.length >= 2)
                PolylineLayer(
                  polylines: _dashedLines(closedBoundary),
                ),
              if (_outerBoundaryPoints.isNotEmpty)
                MarkerLayer(
                  markers: _outerBoundaryPoints
                      .asMap()
                      .entries
                      .map(
                        (entry) => Marker(
                          point: entry.value,
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFBC02D),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.7),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${entry.key + 1}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
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
                    const Text(
                      'Tap to draw the max spray area',
                      style: TextStyle(fontSize: 12),
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
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveBoundary,
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
                      label: const Text('Save Boundary'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBC02D),
                        foregroundColor: Colors.black,
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
}
