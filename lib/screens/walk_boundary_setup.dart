import 'package:flutter/material.dart';

import '../models/property_model.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Walk Boundary Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Boundary setup for ${property.name} is temporarily unavailable in this build.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await onSaved();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Back to Property'),
            ),
          ],
        ),
      ),
    );
  }
}
