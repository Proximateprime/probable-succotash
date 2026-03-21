import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureF,
    required this.windMph,
    required this.rainChancePercent,
    required this.weatherCode,
    required this.description,
    required this.fetchedAt,
  });

  final double temperatureF;
  final double windMph;
  final int rainChancePercent;
  final int weatherCode;
  final String description;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() {
    return {
      'temperature_f': temperatureF,
      'wind_mph': windMph,
      'rain_chance_percent': rainChancePercent,
      'weather_code': weatherCode,
      'description': description,
      'fetched_at': fetchedAt.toIso8601String(),
    };
  }

  static WeatherSnapshot? fromJson(Map<String, dynamic> json) {
    final temp = json['temperature_f'];
    final wind = json['wind_mph'];
    final rain = json['rain_chance_percent'];
    final code = json['weather_code'];
    final description = json['description']?.toString();
    final fetchedAtRaw = json['fetched_at']?.toString();

    if (temp is! num ||
        wind is! num ||
        rain is! num ||
        code is! num ||
        description == null ||
        description.isEmpty ||
        fetchedAtRaw == null ||
        fetchedAtRaw.isEmpty) {
      return null;
    }

    final fetchedAt = DateTime.tryParse(fetchedAtRaw);
    if (fetchedAt == null) return null;

    return WeatherSnapshot(
      temperatureF: temp.toDouble(),
      windMph: wind.toDouble(),
      rainChancePercent: rain.toInt().clamp(0, 100),
      weatherCode: code.toInt(),
      description: description,
      fetchedAt: fetchedAt,
    );
  }
}

class WeatherFetchResult {
  const WeatherFetchResult({
    required this.snapshot,
    required this.fromCache,
    this.errorMessage,
  });

  final WeatherSnapshot? snapshot;
  final bool fromCache;
  final String? errorMessage;

  bool get isUnavailable => snapshot == null;
}

class WeatherService {
  static const String _cacheKey = 'dashboard_weather_cache_v1';
  static const Duration _maxCacheAge = Duration(hours: 6);

  Future<WeatherFetchResult> fetchWithFallback({
    required double latitude,
    required double longitude,
  }) async {
    if (latitude.abs() > 90 || longitude.abs() > 180) {
      return cachedOrUnavailable(
        reason: 'Live weather unavailable. Showing last known conditions.',
      );
    }

    try {
      final snapshot = await _fetchLiveWithRetry(latitude, longitude);
      await _cacheSnapshot(snapshot);
      return WeatherFetchResult(snapshot: snapshot, fromCache: false);
    } catch (_) {
      final cached = await _loadCachedSnapshot(maxAge: _maxCacheAge);
      if (cached != null) {
        return WeatherFetchResult(
          snapshot: cached,
          fromCache: true,
          errorMessage:
              'Live weather unavailable. Showing last known conditions.',
        );
      }

      final stale = await _loadCachedSnapshot();
      if (stale != null) {
        return WeatherFetchResult(
          snapshot: stale,
          fromCache: true,
          errorMessage:
              'Live weather unavailable. Showing older cached weather.',
        );
      }

      return const WeatherFetchResult(
        snapshot: null,
        fromCache: false,
        errorMessage: 'Weather unavailable right now. Please retry.',
      );
    }
  }

  Future<WeatherFetchResult> cachedOrUnavailable({String? reason}) async {
    final cached = await _loadCachedSnapshot(maxAge: _maxCacheAge);
    if (cached != null) {
      return WeatherFetchResult(
        snapshot: cached,
        fromCache: true,
        errorMessage: reason ?? 'Showing last known weather.',
      );
    }

    final stale = await _loadCachedSnapshot();
    if (stale != null) {
      return WeatherFetchResult(
        snapshot: stale,
        fromCache: true,
        errorMessage: reason ?? 'Showing older cached weather.',
      );
    }

    return WeatherFetchResult(
      snapshot: null,
      fromCache: false,
      errorMessage: reason ?? 'Weather unavailable right now. Please retry.',
    );
  }

  Future<WeatherSnapshot> _fetchLiveWithRetry(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${latitude.toStringAsFixed(4)}'
      '&longitude=${longitude.toStringAsFixed(4)}'
      '&current_weather=true'
      '&hourly=precipitation_probability'
      '&temperature_unit=fahrenheit'
      '&wind_speed_unit=mph'
      '&forecast_days=1'
      '&timezone=auto',
    );

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return _parseSnapshot(data);
        }

        lastError = Exception('Weather API status ${response.statusCode}');
      } catch (e) {
        lastError = e;
      }

      if (attempt < 2) {
        final delayMs = 600 * (1 << attempt);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw lastError ?? Exception('Unknown weather fetch failure');
  }

  WeatherSnapshot _parseSnapshot(Map<String, dynamic> data) {
    final current = data['current_weather'];
    if (current is! Map) {
      throw Exception('Missing current_weather data');
    }

    final temp = current['temperature'];
    final wind = current['windspeed'];
    final code = current['weathercode'];
    final time = current['time']?.toString();

    if (temp is! num || wind is! num || code is! num) {
      throw Exception('Incomplete current weather payload');
    }

    final rainChance = _rainChanceForCurrentHour(data, time);

    return WeatherSnapshot(
      temperatureF: temp.toDouble(),
      windMph: wind.toDouble(),
      rainChancePercent: rainChance,
      weatherCode: code.toInt(),
      description: _weatherCodeToDesc(code.toInt()),
      fetchedAt: DateTime.now(),
    );
  }

  int _rainChanceForCurrentHour(
      Map<String, dynamic> data, String? currentTime) {
    final hourly = data['hourly'];
    if (hourly is! Map) return 0;

    final times = hourly['time'];
    final probs = hourly['precipitation_probability'];
    if (times is! List || probs is! List || times.isEmpty || probs.isEmpty) {
      return 0;
    }

    var index = 0;
    if (currentTime != null) {
      final found =
          times.indexWhere((entry) => entry?.toString() == currentTime);
      if (found >= 0) {
        index = found;
      }
    }

    if (index >= probs.length) {
      index = probs.length - 1;
    }

    final value = probs[index];
    if (value is num) return value.toInt().clamp(0, 100);
    return 0;
  }

  Future<void> _cacheSnapshot(WeatherSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(snapshot.toJson()));
  }

  Future<WeatherSnapshot?> _loadCachedSnapshot({Duration? maxAge}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot =
          WeatherSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      if (snapshot == null) return null;

      if (maxAge != null &&
          DateTime.now().difference(snapshot.fetchedAt) > maxAge) {
        return null;
      }

      return snapshot;
    } catch (_) {
      return null;
    }
  }

  String _weatherCodeToDesc(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 55) return 'Drizzle';
    if (code <= 65) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Rain showers';
    return 'Stormy';
  }
}
