import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();

  factory LocalStorageService() {
    return _instance;
  }

  LocalStorageService._internal();

  late SharedPreferences _prefs;
  final Logger _logger = Logger();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _logger.i('LocalStorage initialized');
  }

  Future<void> saveUserId(String userId) => _prefs.setString('user_id', userId);

  String? getUserId() => _prefs.getString('user_id');

  Future<void> clearUserId() => _prefs.remove('user_id');

  Future<void> setDefaultSwathWidth(double width) =>
      _prefs.setDouble('default_swath_width', width);

  double getDefaultSwathWidth() =>
      _prefs.getDouble('default_swath_width') ?? 15.0;

  Future<void> setThemeMode(String mode) => _prefs.setString('theme_mode', mode);

  String getThemeMode() => _prefs.getString('theme_mode') ?? 'system';

    Future<void> setOnboardingDismissed(String userId, bool dismissed) =>
      _prefs.setBool('onboarding_dismissed_$userId', dismissed);

    bool isOnboardingDismissed(String userId) =>
      _prefs.getBool('onboarding_dismissed_$userId') ?? false;

    Future<void> clearOnboardingDismissed(String userId) =>
      _prefs.remove('onboarding_dismissed_$userId');

  Future<void> clearAll() => _prefs.clear();
}
