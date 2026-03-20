import 'package:flutter/material.dart';

import '../models/property_model.dart';
import 'setup_boundary_screen.dart';

class WalkBoundarySetupScreen extends StatelessWidget {
  const WalkBoundarySetupScreen({
    Key? key,
    required this.property,
    required this.onSaved,
  }) : super(key: key);

  final Property property;
  final Future<void> Function() onSaved;

  @override
  Widget build(BuildContext context) {
    return SetupBoundaryScreen(
      property: property,
      onSaved: onSaved,
    );
  }
}
