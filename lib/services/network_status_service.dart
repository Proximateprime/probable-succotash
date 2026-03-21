import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

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
    final uris = <Uri>[
      Uri.parse('${AppConstants.supabaseUrl}/auth/v1/settings'),
      Uri.parse('${AppConstants.supabaseUrl}/rest/v1/'),
    ];

    for (final uri in uris) {
      try {
        final response = await http.get(
          uri,
          headers: {
            'apikey': AppConstants.supabaseAnonKey,
            'Authorization': 'Bearer ${AppConstants.supabaseAnonKey}',
            'Accept': 'application/json',
          },
        ).timeout(timeout);

        if (response.statusCode > 0 && response.statusCode < 500) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    return false;
  }
}
