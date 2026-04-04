import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/property_model.dart';
import '../services/supabase_service.dart';
import 'outer_boundary_draw_screen.dart';
import 'package:covertrack/screens/setup_boundary_screen.dart';

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

  // Option 1: GPS walk using the full SetupBoundaryScreen wizard.
  Future<void> _openGpsWalk() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetupBoundaryScreen(
          property: widget.property,
          onSaved: () async {
            await widget.onSaved();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  // Option 2: tap two diagonal corners → axis-aligned rectangle.
  Future<void> _openBoxBoundary() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoxBoundaryDrawScreen(
          property: widget.property,
          onBoundarySaved: _saveOuterBoundary,
        ),
      ),
    );
    if (!mounted) return;
    await widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  // Option 3: legacy tap-to-draw polygon (kept for power users).
  Future<void> _openTapDraw() async {
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
    if (mounted) Navigator.of(context).pop();
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
              'Choose how you want to define the outer property boundary.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            // ── Option 1: Walk GPS perimeter ─────────────────────────────
            _BoundaryOptionCard(
              icon: Icons.directions_walk,
              title: 'Walked GPS Perimeter',
              subtitle: 'Walk around the property edge while GPS records the boundary.',
              color: const Color(0xFF2E7D32),
              onTap: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await _openGpsWalk();
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
            ),
            const SizedBox(height: 12),
            // ── Option 2: Box / property boundary ────────────────────────
            _BoundaryOptionCard(
              icon: Icons.crop_square_outlined,
              title: 'Box / Property Boundary',
              subtitle:
                  'Tap two diagonal corners on the satellite map to define a rectangle.',
              color: const Color(0xFF1565C0),
              onTap: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await _openBoxBoundary();
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
            ),
            const SizedBox(height: 12),
            // ── Option 3: Manual tap-draw (advanced) ────────────────────
            _BoundaryOptionCard(
              icon: Icons.edit_location_alt_outlined,
              title: 'Manual Tap-Draw',
              subtitle: 'Tap individual points on the map to trace any boundary shape.',
              color: const Color(0xFF6A1B9A),
              onTap: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await _openTapDraw();
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
            ),
            if (_saving) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator())],
          ],
        ),
      ),
    );
  }
}

// ── Helper card widget ─────────────────────────────────────────────────────────
class _BoundaryOptionCard extends StatelessWidget {
  const _BoundaryOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDisabled ? Colors.grey.shade300 : color.withValues(alpha: 0.6),
            ),
            borderRadius: BorderRadius.circular(14),
            color: isDisabled ? Colors.grey.shade100 : color.withValues(alpha: 0.07),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDisabled
                      ? Colors.grey.shade300
                      : color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isDisabled ? Colors.grey : color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDisabled ? Colors.grey : null,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDisabled
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDisabled ? Colors.grey.shade300 : color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
