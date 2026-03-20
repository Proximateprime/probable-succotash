import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../utils/map_import_validator.dart';

class WebODMScreen extends StatefulWidget {
  final String propertyId;
  final String propertyName;
  final String userTier;
  final bool hadExistingMap;
  final VoidCallback onMapImported;

  const WebODMScreen({
    Key? key,
    required this.propertyId,
    required this.propertyName,
    required this.userTier,
    required this.hadExistingMap,
    required this.onMapImported,
  }) : super(key: key);

  @override
  State<WebODMScreen> createState() => _WebODMScreenState();
}

class _WebODMScreenState extends State<WebODMScreen> {
  static const String _webOdmUrl = 'https://webodm.net/cloud';

  WebViewController? _webViewController;
  bool _isImporting = false;
  PlatformFile? _selectedGeoFile;
  PlatformFile? _selectedOrthoFile;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(_webOdmUrl));
    }
  }

  Future<void> _openWebODMExternally() async {
    final uri = Uri.parse(_webOdmUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WebODM Lightning.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickGeoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['geojson', 'json'],
      dialogTitle: 'Select downloaded GeoJSON file',
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _selectedGeoFile = result.files.single;
    });
  }

  Future<void> _pickOrthomosaicFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'tif', 'tiff', 'webp'],
      dialogTitle: 'Select orthomosaic preview image',
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _selectedOrthoFile = result.files.single;
    });
  }

  Future<void> _importProcessedMap() async {
    if (_selectedGeoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a GeoJSON file first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isImporting = true);

    try {
      final supabase = context.read<SupabaseService>();
      final geoBytes = _selectedGeoFile!.bytes;
      if (geoBytes == null) {
        throw Exception('The selected map file could not be read.');
      }

      final validation = MapImportValidator.validate(
        tier: widget.userTier,
        geoFileBytes: geoBytes,
        geoFileExtension: _selectedGeoFile!.extension ?? '',
        orthomosaicBytes: _selectedOrthoFile?.bytes,
      );

      if (!validation.isValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              validation.errorMessage ??
                  'Map too large for your tier. Upgrade or use a smaller area.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      final geoText = utf8.decode(geoBytes);
      final extension = (_selectedGeoFile!.extension ?? '').toLowerCase();
      if (extension != 'geojson' && extension != 'json') {
        throw Exception('Only GeoJSON imports are supported in this build.');
      }

      final storedMapValue = jsonDecode(geoText);

      String? orthomosaicUrl;
      String? orthomosaicWarning;
      final orthoBytes = _selectedOrthoFile?.bytes;
      if (_selectedOrthoFile != null && orthoBytes != null) {
        final fileName =
            '${widget.propertyId}_${DateTime.now().millisecondsSinceEpoch}_${_selectedOrthoFile!.name}';
        final storagePath = fileName;

        try {
          await supabase.client.storage
              .from('orthomosaics')
              .uploadBinary(storagePath, orthoBytes);

          orthomosaicUrl = supabase.client.storage
              .from('orthomosaics')
              .getPublicUrl(storagePath);
        } catch (e) {
          orthomosaicWarning =
              'Boundary imported, but orthomosaic image could not be stored.';
          debugPrint('Orthomosaic upload error: $e');
        }
      }

      await supabase.updateProperty(
        widget.propertyId,
        {
          'map_geojson': storedMapValue,
          if (orthomosaicUrl != null) 'orthomosaic_url': orthomosaicUrl,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(orthomosaicWarning ?? 'Map ready for tracking!'),
          backgroundColor:
              orthomosaicWarning == null ? Colors.green : Colors.orange,
        ),
      );

      widget.onMapImported();
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Map import error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Widget _buildFilePickerButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required bool isCompactLayout,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (isCompactLayout) {
      return SizedBox(width: double.infinity, child: button);
    }

    return Flexible(child: button);
  }

  Widget _buildGuideCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload your drone video here. After processing, download the KML/GeoJSON and orthomosaic preview.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Quick guide:\n'
            '1. Upload the drone video to WebODM Lightning.\n'
            '2. Let processing finish.\n'
            '3. Download the KML or GeoJSON boundary output.\n'
            '4. Download the orthomosaic preview image if available.\n'
            '5. Come back here and import both files.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Tier limits apply by file size and map area. Large maps may require an upgrade.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Text(
            'Property: ${widget.propertyName}',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildImportPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompactLayout = constraints.maxWidth < 560;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Import Processed Map',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (isCompactLayout)
                Column(
                  children: [
                    _buildFilePickerButton(
                      onPressed: _pickGeoFile,
                      icon: Icons.map_outlined,
                      label: _selectedGeoFile == null
                          ? 'Choose GeoJSON'
                          : _selectedGeoFile!.name,
                      isCompactLayout: true,
                    ),
                    const SizedBox(height: 12),
                    _buildFilePickerButton(
                      onPressed: _pickOrthomosaicFile,
                      icon: Icons.image_outlined,
                      label: _selectedOrthoFile == null
                          ? 'Choose orthomosaic'
                          : _selectedOrthoFile!.name,
                      isCompactLayout: true,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _buildFilePickerButton(
                      onPressed: _pickGeoFile,
                      icon: Icons.map_outlined,
                      label: _selectedGeoFile == null
                          ? 'Choose GeoJSON'
                          : _selectedGeoFile!.name,
                      isCompactLayout: false,
                    ),
                    const SizedBox(width: 12),
                    _buildFilePickerButton(
                      onPressed: _pickOrthomosaicFile,
                      icon: Icons.image_outlined,
                      label: _selectedOrthoFile == null
                          ? 'Choose orthomosaic'
                          : _selectedOrthoFile!.name,
                      isCompactLayout: false,
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : _importProcessedMap,
                  icon: const Icon(Icons.download_done),
                  label: _isImporting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Import Processed Map'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Map'),
      ),
      body: Column(
        children: [
          _buildGuideCard(),
          Expanded(
            child: kIsWeb
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_in_browser, size: 64),
                          const SizedBox(height: 16),
                          const Text(
                            'WebODM Lightning opens in a separate browser tab on web.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Use the button below, finish processing there, then return here and import the downloaded files.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _openWebODMExternally,
                            icon: const Icon(Icons.launch),
                            label: const Text('Open WebODM Lightning'),
                          ),
                        ],
                      ),
                    ),
                  )
                : WebViewWidget(controller: _webViewController!),
          ),
          _buildImportPanel(),
        ],
      ),
    );
  }
}