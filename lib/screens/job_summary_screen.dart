import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';

class JobSummaryResult {
  const JobSummaryResult({
    required this.generatePdf,
    required this.discard,
    required this.notes,
    this.photoUrl,
  });

  final bool generatePdf;
  final bool discard;
  final String notes;
  final String? photoUrl;
}

class JobSummaryScreen extends StatefulWidget {
  const JobSummaryScreen({
    Key? key,
    required this.propertyName,
    required this.propertyId,
    required this.sessionId,
    required this.acresCovered,
    required this.coveragePercent,
    required this.timeTakenSeconds,
    required this.overlapPercent,
    required this.estimatedChemicalUsed,
    required this.potentialSavings,
    required this.applicationRateUnit,
  }) : super(key: key);

  final String propertyName;
  final String propertyId;
  final String sessionId;
  final double acresCovered;
  final double coveragePercent;
  final int timeTakenSeconds;
  final double overlapPercent;
  final double? estimatedChemicalUsed;
  final double? potentialSavings;
  final String applicationRateUnit;

  @override
  State<JobSummaryScreen> createState() => _JobSummaryScreenState();
}

class _JobSummaryScreenState extends State<JobSummaryScreen> {
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final Connectivity _connectivity = Connectivity();
  bool _isOffline = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
  String? _photoName;

  @override
  void initState() {
    super.initState();
    _loadConnectivity();
  }

  Future<void> _loadConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (!mounted) return;
    setState(() => _isOffline = result.contains(ConnectivityResult.none));
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${remaining}s';
    }
    return '${minutes}m ${remaining}s';
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_isUploadingPhoto) return;

    if (_isOffline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline: photo upload requires internet connection.'),
        ),
      );
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 2048,
    );
    if (picked == null) return;

    setState(() {
      _isUploadingPhoto = true;
      _photoName = picked.name;
    });

    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final url = await StorageService().uploadSessionPhoto(
        imageBytes: Uint8List.fromList(bytes),
        propertyId: widget.propertyId,
        sessionId: widget.sessionId,
        extension: ext,
      );

      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo upload failed. Please retry.')),
        );
      } else {
        setState(() => _photoUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo uploaded successfully.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final potential = widget.potentialSavings;

    return Scaffold(
      appBar: AppBar(
        title: Text('Job Summary - ${widget.propertyName}'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isOffline)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.orange.withValues(alpha: 0.14),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.38)),
                  ),
                  child: const Text(
                    'You are offline. Summary stays available; photo upload needs internet.',
                  ),
                ),
              Text(
                'Job Summary - ${widget.propertyName}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _line('Acres covered', widget.acresCovered.toStringAsFixed(2)),
              _line('Coverage %', '${widget.coveragePercent.toStringAsFixed(1)}%'),
              _line('Time taken', _formatDuration(widget.timeTakenSeconds)),
              _line('Estimated overlap %', '${widget.overlapPercent.toStringAsFixed(1)}%'),
              _line(
                'Estimated chemical used',
                widget.estimatedChemicalUsed == null
                    ? 'Unavailable'
                    : '${widget.estimatedChemicalUsed!.toStringAsFixed(2)} ${widget.applicationRateUnit}',
              ),
              if (widget.overlapPercent > 15 && potential != null)
                _line(
                  'Potential savings opportunity',
                  '~\$${potential.toStringAsFixed(2)}',
                ),
              const SizedBox(height: 18),
              TextField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Add Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                icon: _isUploadingPhoto
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(_photoUrl == null ? 'Add Photo' : 'Photo Added'),
              ),
              if (_photoName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Selected: $_photoName'),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(
                          JobSummaryResult(
                            generatePdf: true,
                            discard: false,
                            notes: _notesController.text.trim(),
                            photoUrl: _photoUrl,
                          ),
                        );
                      },
                      child: const Text('Generate PDF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade400),
                        foregroundColor: Colors.red.shade600,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(
                          JobSummaryResult(
                            generatePdf: false,
                            discard: true,
                            notes: _notesController.text.trim(),
                            photoUrl: _photoUrl,
                          ),
                        );
                      },
                      child: const Text('Discard'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}
