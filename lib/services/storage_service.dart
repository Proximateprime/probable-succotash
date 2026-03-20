import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final supabase = Supabase.instance.client;
  final Logger _logger = Logger();

  /// Upload PDF to 'proof-pdfs' bucket and return 24-hour signed URL.
  Future<String?> uploadPdf({
    required Uint8List pdfBytes,
    required String propertyId,
    required String sessionId,
  }) async {
    try {
      final fileName = 'proof_${propertyId}_$sessionId.pdf';
      final path = 'proof-pdfs/$fileName';

      _logger.i('Uploading PDF: $path (${pdfBytes.length} bytes)');

      await supabase.storage.from('proof-pdfs').uploadBinary(path, pdfBytes);

      _logger.i('PDF uploaded successfully: $fileName');

      final signedUrl =
          await supabase.storage.from('proof-pdfs').createSignedUrl(path, 86400);

      _logger.i('Signed URL created for: $fileName (valid 24 hours)');
      return signedUrl;
    } catch (e) {
      _logger.e('PDF upload error: $e');
      return null;
    }
  }

  /// Upload a session photo and return a signed URL.
  Future<String?> uploadSessionPhoto({
    required Uint8List imageBytes,
    required String propertyId,
    required String sessionId,
    String extension = 'jpg',
  }) async {
    try {
      final safeExt = extension
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toLowerCase();
      final ext = safeExt.isEmpty ? 'jpg' : safeExt;
      final fileName =
          'session_photo_${propertyId}_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'session-photos/$fileName';

      await supabase.storage.from('proof-pdfs').uploadBinary(path, imageBytes);
      final signedUrl =
          await supabase.storage.from('proof-pdfs').createSignedUrl(path, 604800);
      return signedUrl;
    } catch (e) {
      _logger.e('Session photo upload error: $e');
      return null;
    }
  }
}
