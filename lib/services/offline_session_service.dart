import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

class OfflineSyncReport {
  const OfflineSyncReport({
    required this.syncedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.attemptedCount,
  });

  final int syncedCount;
  final int pendingCount;
  final int failedCount;
  final int attemptedCount;
}

class OfflineSessionService {
  OfflineSessionService._internal();
  static final OfflineSessionService _instance =
      OfflineSessionService._internal();
  factory OfflineSessionService() => _instance;

  static const String _legacyPendingSessionsKey = 'pending_tracking_sessions_v1';
  static const String _boxName = 'offline_tracking_sessions_v2';
  static const int _maxRetries = 3;

  final Logger _logger = Logger();
  Future<void> _writeLock = Future.value();
  bool _isInitialized = false;
  Box<Map>? _box;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>(_boxName);
    await _migrateLegacySharedPrefsData();
    _isInitialized = true;
  }

  Future<T> _withWriteLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    _writeLock = _writeLock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized && _box != null) return;
    await initialize();
  }

  Future<List<Map<String, dynamic>>> getPendingSessions() async {
    await _ensureInitialized();

    try {
      final entries = _allEntries();
      final unsynced = entries
          .where((entry) => _statusOf(entry) != 'synced')
          .map(_payloadOf)
          .toList();

      unsynced.sort((a, b) {
        final aQueued = DateTime.tryParse(a['queued_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bQueued = DateTime.tryParse(b['queued_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bQueued.compareTo(aQueued);
      });

      return unsynced;
    } catch (e) {
      _logger.e('Read pending sessions error: $e');
      return const [];
    }
  }

  Future<int> getPendingCount() async {
    await _ensureInitialized();
    return _allEntries()
        .where((entry) => _statusOf(entry) == 'queued')
        .length;
  }

  Future<int> getFailedCount() async {
    await _ensureInitialized();
    return _allEntries()
        .where((entry) => _statusOf(entry) == 'failed')
        .length;
  }

  Future<void> enqueueSession(Map<String, dynamic> sessionPayload) async {
    await _withWriteLock(() async {
      await _ensureInitialized();

      final payload = Map<String, dynamic>.from(sessionPayload);
      final nowIso = DateTime.now().toIso8601String();
      payload['queued_at'] ??= nowIso;

      final sessionId = payload['id']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        _logger.w('Skipping enqueue with missing session id.');
        return;
      }

      final record = <String, dynamic>{
        'id': sessionId,
        'status': 'queued',
        'retry_count': 0,
        'queued_at': payload['queued_at'],
        'last_error': null,
        'last_attempt_at': null,
        'updated_at': nowIso,
        'payload': payload,
      };

      await _box!.put(sessionId, record);
    });
  }

  Future<void> removePendingSession(String sessionId) async {
    await _withWriteLock(() async {
      await _ensureInitialized();
      await _box!.delete(sessionId);
    });
  }

  Future<OfflineSyncReport> syncPendingSessionsWithReport(
    SupabaseService supabase, {
    bool includeFailed = false,
  }) async {
    return _withWriteLock(() async {
      await _ensureInitialized();
      final records = _allEntries();

      final syncable = records.where((entry) {
        final status = _statusOf(entry);
        if (status == 'queued') return true;
        return includeFailed && status == 'failed';
      }).toList();

      if (syncable.isEmpty) {
        return OfflineSyncReport(
          syncedCount: 0,
          pendingCount: await getPendingCount(),
          failedCount: await getFailedCount(),
          attemptedCount: 0,
        );
      }

      syncable.sort((a, b) {
        final aPayload = _payloadOf(a);
        final bPayload = _payloadOf(b);
        final aQueued =
            DateTime.tryParse(aPayload['queued_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final bQueued =
            DateTime.tryParse(bPayload['queued_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        return aQueued.compareTo(bQueued);
      });

      var synced = 0;
      final attemptAt = DateTime.now().toIso8601String();

      for (final record in syncable) {
        final sessionId = _idOf(record);
        if (sessionId == null || sessionId.isEmpty) continue;

        final retryCount = (record['retry_count'] as num?)?.toInt() ?? 0;
        final payload = _toSupabasePayload(_payloadOf(record));

        try {
          await supabase.client
              .from('tracking_sessions')
              .upsert(payload, onConflict: 'id');
          await _box!.delete(sessionId);
          synced++;
        } catch (e) {
          final nextRetry = retryCount + 1;
          final nextStatus = nextRetry >= _maxRetries ? 'failed' : 'queued';
          await _box!.put(sessionId, {
            ...record,
            'status': nextStatus,
            'retry_count': nextRetry,
            'last_error': e.toString(),
            'last_attempt_at': attemptAt,
            'updated_at': DateTime.now().toIso8601String(),
          });
          _logger.w(
            'Pending session sync failed for $sessionId. retry=$nextRetry status=$nextStatus error=$e',
          );
        }
      }

      return OfflineSyncReport(
        syncedCount: synced,
        pendingCount: await getPendingCount(),
        failedCount: await getFailedCount(),
        attemptedCount: syncable.length,
      );
    });
  }

  Future<int> syncPendingSessions(
    SupabaseService supabase, {
    bool includeFailed = false,
  }) async {
    final report = await syncPendingSessionsWithReport(
      supabase,
      includeFailed: includeFailed,
    );
    return report.syncedCount;
  }

  List<Map<String, dynamic>> _allEntries() {
    final box = _box;
    if (box == null) return const [];

    return box.values
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  String _statusOf(Map<String, dynamic> entry) {
    return entry['status']?.toString() ?? 'queued';
  }

  String? _idOf(Map<String, dynamic> entry) {
    return entry['id']?.toString();
  }

  Map<String, dynamic> _payloadOf(Map<String, dynamic> entry) {
    final payload = entry['payload'];
    if (payload is Map) {
      final normalized = Map<String, dynamic>.from(payload);
      normalized['queued_at'] ??= entry['queued_at'];
      return normalized;
    }

    return {
      ...entry,
      'queued_at': entry['queued_at'],
    };
  }

  Future<void> _migrateLegacySharedPrefsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyPendingSessionsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final nowIso = DateTime.now().toIso8601String();
      for (final item in decoded.whereType<Map>()) {
        final payload = Map<String, dynamic>.from(item);
        final sessionId = payload['id']?.toString();
        if (sessionId == null || sessionId.isEmpty) continue;

        final record = <String, dynamic>{
          'id': sessionId,
          'status': 'queued',
          'retry_count': 0,
          'queued_at': payload['queued_at'] ?? nowIso,
          'last_error': null,
          'last_attempt_at': null,
          'updated_at': nowIso,
          'payload': payload,
        };

        await _box!.put(sessionId, record);
      }

      await prefs.remove(_legacyPendingSessionsKey);
    } catch (e) {
      _logger.w('Legacy offline queue migration failed: $e');
    }
  }

  Map<String, dynamic> _toSupabasePayload(Map<String, dynamic> source) {
    const allowed = {
      'id',
      'property_id',
      'user_id',
      'start_time',
      'end_time',
      'coverage_percent',
      'paths',
      'proof_pdf_url',
      'created_at',
      'raw_gnss_data',
      'swath_width_feet',
      'tank_capacity_gallons',
      'application_rate_per_acre',
      'application_rate_unit',
      'chemical_cost_per_unit',
      'overlap_percent',
      'overlap_savings_estimate',
      'overlap_threshold',
      'partial_completion_reason',
      'checklist_data',
    };

    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (allowed.contains(entry.key)) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }
}
