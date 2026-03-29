import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NetworkStatusService {
  static DateTime? _lastConfirmedOnlineAt;
  static bool _lastKnownOnline = false;

  static bool hasTransport(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  static Future<bool> hasUsableConnection(
    List<ConnectivityResult> results, {
    Duration timeout = const Duration(seconds: 4),
    Duration successGrace = const Duration(seconds: 20),
  }) async {
    if (!hasTransport(results)) {
      _lastKnownOnline = false;
      return false;
    }

    final now = DateTime.now();
    if (_lastKnownOnline &&
        _lastConfirmedOnlineAt != null &&
        now.difference(_lastConfirmedOnlineAt!) <= successGrace) {
      return true;
    }

    final reachable = await _probeSupabase(timeout);
    if (reachable) {
      _lastKnownOnline = true;
      _lastConfirmedOnlineAt = now;
      return true;
    }

    if (_lastKnownOnline &&
        _lastConfirmedOnlineAt != null &&
        now.difference(_lastConfirmedOnlineAt!) <= successGrace) {
      return true;
    }

    _lastKnownOnline = false;
    return false;
  }

  static Future<bool> checkCurrentConnection(
    Connectivity connectivity, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final results = await connectivity.checkConnectivity();
    return hasUsableConnection(results, timeout: timeout);
  }

  static Future<bool> _probeSupabase(Duration timeout) async {
    try {
      // April 2026 hardening: avoid direct anon calls to PostgREST root (/rest/v1/).
      // We use the Supabase client API with a lightweight table query instead.
      await Supabase.instance.client
          .from('profiles')
          .select('id')
          .limit(1)
          .timeout(timeout);
      return true;
    } on PostgrestException {
      // 4xx from PostgREST still confirms network reachability.
      return true;
    } on AuthException {
      // Auth endpoint reachable but session/credentials invalid.
      return true;
    } catch (_) {
      return false;
    }
  }
}
