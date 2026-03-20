import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/session_model.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class ExportScreen extends StatefulWidget {
  final String sessionId;
  final String propertyId;
  final String propertyName;
  final List<TrackingPath> paths;
  final double coverage;
  final double distance;
  final double? acresCovered;
  final int? timeTakenSeconds;
  final String? summaryNotes;
  final String? summaryPhotoUrl;
  final double? overlapPercent;
  final double? estimatedChemicalUsed;
  final double? potentialSavings;
  final String? applicationRateUnit;

  const ExportScreen({
    Key? key,
    required this.sessionId,
    required this.propertyId,
    required this.propertyName,
    required this.paths,
    required this.coverage,
    required this.distance,
    this.acresCovered,
    this.timeTakenSeconds,
    this.summaryNotes,
    this.summaryPhotoUrl,
    this.overlapPercent,
    this.estimatedChemicalUsed,
    this.potentialSavings,
    this.applicationRateUnit,
  }) : super(key: key);

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m ${remaining}s';
    return '${minutes}m ${remaining}s';
  }

  static const String _savedSignatureKey = 'export_saved_signature_png_b64';
  static const String _savedSignatureNameKey = 'export_saved_signature_name';

  bool _isGenerating = false;
  bool _success = false;
  bool _isLoadingSavedSignature = true;
  bool _useSavedSignature = true;
  String? _pdfUrl;
  String? _savedApplicatorName;
  Uint8List? _savedSignatureBytes;
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2.2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final TextEditingController _applicatorNameController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedSignatureProfile();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _applicatorNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSignatureProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString(_savedSignatureKey);
      final savedName = prefs.getString(_savedSignatureNameKey);
      Uint8List? bytes;

      if (b64 != null && b64.trim().isNotEmpty) {
        bytes = base64Decode(b64);
      }

      if (!mounted) return;
      setState(() {
        _savedSignatureBytes = bytes;
        _savedApplicatorName = savedName;
        _isLoadingSavedSignature = false;
      });

      if (_applicatorNameController.text.trim().isEmpty &&
          (savedName?.trim().isNotEmpty ?? false)) {
        _applicatorNameController.text = savedName!.trim();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSavedSignature = false);
    }
  }

  Future<void> _saveCurrentSignatureProfile() async {
    if (_signatureController.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Draw a signature before saving profile.')),
      );
      return;
    }

    final bytes =
        await _signatureController.toPngBytes(height: 180, width: 900);
    if (bytes == null || bytes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedSignatureKey, base64Encode(bytes));
    await prefs.setString(
      _savedSignatureNameKey,
      _applicatorNameController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _savedSignatureBytes = bytes;
      _savedApplicatorName = _applicatorNameController.text.trim();
      _useSavedSignature = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Saved signature profile for one-tap reuse.')),
    );
  }

  Future<void> _clearSavedSignatureProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedSignatureKey);
    await prefs.remove(_savedSignatureNameKey);

    if (!mounted) return;
    setState(() {
      _savedSignatureBytes = null;
      _savedApplicatorName = null;
      _useSavedSignature = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved signature profile removed.')),
    );
  }

  List<_ExclusionZonePdfInfo> _parseExclusionZoneEntries(dynamic entries) {
    if (entries is! List) {
      return const [];
    }

    final zones = <_ExclusionZonePdfInfo>[];

    for (final entry in entries) {
      if (entry is! Map) {
        continue;
      }

      final mapEntry = Map<String, dynamic>.from(entry);
      Map<String, dynamic>? polygon;
      String? note;

      final wrappedPolygon = mapEntry['polygon'];
      if (wrappedPolygon is Map) {
        polygon = Map<String, dynamic>.from(wrappedPolygon);
        final wrappedNote = mapEntry['note'];
        if (wrappedNote is String && wrappedNote.trim().isNotEmpty) {
          note = wrappedNote.trim();
        }
      } else if (mapEntry['type'] == 'Polygon') {
        polygon = mapEntry;
      }

      if (polygon == null || polygon['type'] != 'Polygon') {
        continue;
      }

      final coordinates = polygon['coordinates'];
      if (coordinates is! List || coordinates.isEmpty) {
        continue;
      }

      final firstRing = coordinates.first;
      if (firstRing is! List) {
        continue;
      }

      zones.add(
        _ExclusionZonePdfInfo(pointCount: firstRing.length, note: note),
      );
    }

    return zones;
  }

  Future<Uint8List?> _buildPathPreviewImage() async {
    if (widget.paths.length < 2) return null;

    const width = 880.0;
    const height = 460.0;
    const padding = 28.0;

    final lats = widget.paths.map((p) => p.latitude).toList(growable: false);
    final lngs = widget.paths.map((p) => p.longitude).toList(growable: false);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    final latSpan = math.max(1e-6, maxLat - minLat);
    final lngSpan = math.max(1e-6, maxLng - minLng);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const rect = ui.Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(rect, ui.Paint()..color = const Color(0xFFF7F8FA));

    final gridPaint = ui.Paint()
      ..color = const Color(0xFFE6E8EC)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = (height / 5) * i;
      final x = (width / 5) * i;
      canvas.drawLine(ui.Offset(0, y), ui.Offset(width, y), gridPaint);
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, height), gridPaint);
    }

    ui.Offset normalize(TrackingPath p) {
      final nx = (p.longitude - minLng) / lngSpan;
      final ny = (p.latitude - minLat) / latSpan;
      final x = padding + (nx * (width - (padding * 2)));
      final y = height - (padding + (ny * (height - (padding * 2))));
      return ui.Offset(x, y);
    }

    final path = ui.Path();
    final start = normalize(widget.paths.first);
    path.moveTo(start.dx, start.dy);
    for (final point in widget.paths.skip(1)) {
      final offset = normalize(point);
      path.lineTo(offset.dx, offset.dy);
    }

    canvas.drawPath(
      path,
      ui.Paint()
        ..color = const Color(0xFF2E7D32)
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = 3,
    );

    final startPaint = ui.Paint()..color = const Color(0xFF1565C0);
    final endPaint = ui.Paint()..color = const Color(0xFFD32F2F);
    canvas.drawCircle(start, 6, startPaint);
    final end = normalize(widget.paths.last);
    canvas.drawCircle(end, 6, endPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);

    try {
      // Safety checks
      if (widget.propertyId.isEmpty || widget.sessionId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Create a session first'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final supabase = context.read<SupabaseService>();
      final property = await supabase.fetchProperty(widget.propertyId);
      final session = await supabase.fetchTrackingSession(widget.sessionId);
      final exclusionZoneInfos =
          _parseExclusionZoneEntries(property?.exclusionZones);
      final signatureBytes = _signatureController.isNotEmpty
          ? await _signatureController.toPngBytes(height: 180, width: 900)
          : (_useSavedSignature ? _savedSignatureBytes : null);
      final pathPreviewBytes = await _buildPathPreviewImage();
      final typedName = _applicatorNameController.text.trim();
      final applicatorName = typedName.isNotEmpty
          ? typedName
          : (_useSavedSignature ? (_savedApplicatorName ?? '') : '');

      final pdf = pw.Document();
      final timestamp = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Text(
              'CoverTrack Proof of Coverage',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Property: ${widget.propertyName}'),
                  pw.SizedBox(height: 8),
                  pw.Text('Session: ${widget.sessionId.substring(0, 16)}'),
                  pw.SizedBox(height: 8),
                  pw.Text('Date: $timestamp'),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Coverage: ${widget.coverage.toStringAsFixed(1)}%'),
                  pw.SizedBox(height: 8),
                  pw.Text(
                      'Distance: ${widget.distance.toStringAsFixed(2)} miles'),
                  if (widget.acresCovered != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Acres covered: ${widget.acresCovered!.toStringAsFixed(2)}',
                    ),
                  ],
                  if (widget.timeTakenSeconds != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Time taken: ${_formatDuration(widget.timeTakenSeconds!)}',
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Text('GPS Points: ${widget.paths.length}'),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: (session?.overlapPercent ?? 0) >=
                          (session?.overlapThreshold ?? 25)
                      ? PdfColors.red300
                      : PdfColors.grey300,
                ),
                color: (session?.overlapPercent ?? 0) >=
                        (session?.overlapThreshold ?? 25)
                    ? PdfColors.red50
                    : PdfColors.white,
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Overlap Review',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Estimated overlap: ${(widget.overlapPercent ?? session?.overlapPercent ?? 0).toStringAsFixed(1)}%',
                  ),
                  if (widget.estimatedChemicalUsed != null) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Estimated chemical used: ${widget.estimatedChemicalUsed!.toStringAsFixed(2)} ${widget.applicationRateUnit}',
                    ),
                  ],
                  pw.SizedBox(height: 6),
                  pw.Text(
                    widget.potentialSavings == null
                        ? ((session?.overlapSavingsEstimate == null)
                            ? 'Potential savings opportunity: unavailable'
                            : 'Potential savings opportunity: \$${session!.overlapSavingsEstimate!.toStringAsFixed(2)}')
                        : 'Potential savings opportunity: \$${widget.potentialSavings!.toStringAsFixed(2)}',
                  ),
                  if (session?.partialCompletionReason != null) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Partial completion note: ${session!.partialCompletionReason}',
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Coverage Path Snapshot',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (pathPreviewBytes == null)
              pw.Text('No GPS path data available for preview.')
            else
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Image(
                  pw.MemoryImage(pathPreviewBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Treatment Checklist',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (session?.checklistData == null)
              pw.Text('No checklist was saved.')
            else if ((session!.checklistData!['skipped'] ?? false) == true)
              pw.Text(
                'Checklist skipped${((session.checklistData!['notes'] ?? '') as String).trim().isEmpty ? '' : ' | Notes: ${session.checklistData!['notes']}'}',
              )
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Covered all intended bare soil: ${session.checklistData!['covered_bare_soil'] == true ? 'Yes' : 'No'}',
                  ),
                  pw.Text(
                    'Avoided all green areas: ${session.checklistData!['avoided_green_areas'] == true ? 'Yes' : 'No'}',
                  ),
                  pw.Text(
                    'No product left in tank: ${session.checklistData!['no_product_left'] == true ? 'Yes' : 'No'}',
                  ),
                  if (((session.checklistData!['notes'] ?? '') as String)
                      .trim()
                      .isNotEmpty)
                    pw.Text('Notes: ${session.checklistData!['notes']}'),
                ],
              ),
            if ((widget.summaryNotes ?? '').trim().isNotEmpty ||
                (widget.summaryPhotoUrl ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                'Job Summary Notes',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              if ((widget.summaryNotes ?? '').trim().isNotEmpty)
                pw.Text('Notes: ${widget.summaryNotes}'),
              if ((widget.summaryPhotoUrl ?? '').trim().isNotEmpty)
                pw.UrlLink(
                  destination: widget.summaryPhotoUrl!,
                  child: pw.Text(
                    'Photo: ${widget.summaryPhotoUrl}',
                    style: const pw.TextStyle(color: PdfColors.blue),
                  ),
                ),
            ],
            pw.SizedBox(height: 20),
            pw.Text(
              'Exclusion Zones',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (exclusionZoneInfos.isEmpty)
              pw.Text('No exclusion zones recorded.')
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < exclusionZoneInfos.length; i++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Text(
                        'Zone ${i + 1}: ${exclusionZoneInfos[i].pointCount} points | Note: ${exclusionZoneInfos[i].note ?? 'No note'}',
                      ),
                    ),
                ],
              ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Applicator Sign-Off',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                      'Applicator: ${applicatorName.isEmpty ? 'Not provided' : applicatorName}'),
                  pw.SizedBox(height: 6),
                  pw.Text('Signed at: ${DateTime.now()}'),
                  pw.SizedBox(height: 10),
                  if (signatureBytes != null)
                    pw.Container(
                      height: 80,
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(signatureBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    )
                  else
                    pw.Text('No signature captured.'),
                ],
              ),
            ),
          ],
        ),
      );

      final Uint8List pdfBytes = await pdf.save();

      debugPrint(
        'Uploading PDF for property ${widget.propertyId}, session ${widget.sessionId}',
      );

      // Upload PDF to Supabase Storage
      final storage = StorageService();
      final pdfUrl = await storage.uploadPdf(
        pdfBytes: pdfBytes,
        propertyId: widget.propertyId,
        sessionId: widget.sessionId,
      );

      if (pdfUrl != null) {
        debugPrint('PDF upload successful.');

        // Save signed URL to tracking_sessions table
        await supabase.updateSessionProofPdfUrl(
          sessionId: widget.sessionId,
          proofPdfUrl: pdfUrl,
        );

        debugPrint('PDF URL stored on session ${widget.sessionId}.');

        setState(() {
          _success = true;
          _pdfUrl = pdfUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Proof PDF generated, uploaded, and saved!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('PDF upload failed.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✗ Failed to upload PDF to storage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _copyPdfUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDF link copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchPdfUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open PDF link'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Property: ${widget.propertyName}'),
                    const SizedBox(height: 8),
                    Text('Coverage: ${widget.coverage.toStringAsFixed(1)}%'),
                    const SizedBox(height: 8),
                    Text(
                        'Distance: ${widget.distance.toStringAsFixed(2)} miles'),
                    const SizedBox(height: 8),
                    Text('Points: ${widget.paths.length}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Applicator Signature',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _applicatorNameController,
                      decoration: const InputDecoration(
                        labelText: 'Applicator Name (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Signature(
                        controller: _signatureController,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _signatureController.clear,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Signature'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_isLoadingSavedSignature)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _savedSignatureBytes == null
                                ? null
                                : () {
                                    setState(() {
                                      _useSavedSignature = true;
                                      if (_applicatorNameController.text
                                              .trim()
                                              .isEmpty &&
                                          (_savedApplicatorName
                                                  ?.trim()
                                                  .isNotEmpty ??
                                              false)) {
                                        _applicatorNameController.text =
                                            _savedApplicatorName!.trim();
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.person_pin_outlined),
                            label: const Text('Use Saved Signature'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saveCurrentSignatureProfile,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save as Profile'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _savedSignatureBytes == null
                                ? null
                                : _clearSavedSignatureProfile,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear Saved'),
                          ),
                        ],
                      ),
                    if (_savedSignatureBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _useSavedSignature
                              ? 'Saved signature will be used if no new signature is drawn.'
                              : 'Saved signature is available.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGenerating ? null : _generatePdf,
                child: _isGenerating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Generate PDF'),
              ),
            ),
            if (_success)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  color: Colors.green[50],
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PDF Generated Successfully!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_pdfUrl != null) ...[
                        const Text('Proof stored in Supabase Storage:'),
                        const SizedBox(height: 8),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              _pdfUrl!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _launchPdfUrl(_pdfUrl!),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('View PDF'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _copyPdfUrl(_pdfUrl!),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy Link'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExclusionZonePdfInfo {
  final int pointCount;
  final String? note;

  const _ExclusionZonePdfInfo({required this.pointCount, this.note});
}








