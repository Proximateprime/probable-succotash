import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/property_model.dart';
import '../services/supabase_service.dart';
import 'outer_boundary_draw_screen.dart';

class WalkBoundarySetupScreen extends StatefulWidget {
  const WalkBoundarySetupScreen({
    Key? key,
    required this.property,
    required this.onSaved,
  }) : super(key: key);

  final Property property;
  final Future<void> Function() onSaved;

  @override
  State<WalkBoundarySetupScreen> createState() => _WalkBoundarySetupScreenState();
}

class _WalkBoundarySetupScreenState extends State<WalkBoundarySetupScreen> {
  bool _saving = false;

  Future<void> _openOuterBoundaryDrawer() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OuterBoundaryDrawScreen(
          property: widget.property,
          onBoundarySaved: _saveOuterBoundary,
        ),
      ),
    );

    if (!mounted) return;
    await widget.onSaved();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveOuterBoundary(List<LatLng>? boundaryPoints) async {
    final supabase = context.read<SupabaseService>();

    if (boundaryPoints == null || boundaryPoints.length < 4) {
      await supabase.updateOuterBoundary(
        propertyId: widget.property.id,
        outerBoundary: null,
      );
      return;
    }

    final geoJsonBoundary = {
      'type': 'Polygon',
      'coordinates': [
        boundaryPoints
            .map((p) => [p.longitude, p.latitude])
            .toList(growable: false),
      ],
    };

    await supabase.updateOuterBoundary(
      propertyId: widget.property.id,
      outerBoundary: geoJsonBoundary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk Boundary Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use this tool to draw and save the outer property boundary.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          await _openOuterBoundaryDrawer();
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.directions_walk),
                label: const Text('Open Boundary Drawer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
