import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'constants/app_constants.dart';
import 'utils/app_theme.dart';
import 'utils/local_storage_service.dart';
import 'utils/theme_controller.dart';
import 'services/supabase_service.dart';
import 'services/map_service.dart';
import 'services/payment_service.dart';
import 'services/offline_session_service.dart';
import 'screens/about_page.dart';
import 'screens/analytics_screen.dart';
import 'screens/landing_page.dart';
import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  final supabaseService = SupabaseService();
  await supabaseService.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  MapService();
  PaymentService().initialize(AppConstants.stripePublishableKey);

  await LocalStorageService().initialize();
  await OfflineSessionService().initialize();
  final themeController = ThemeController(LocalStorageService());
  await themeController.initialize();

  runApp(CoverTrackApp(themeController: themeController));
}

class CoverTrackApp extends StatelessWidget {
  const CoverTrackApp({
    Key? key,
    required this.themeController,
  }) : super(key: key);

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SupabaseService>(create: (_) => SupabaseService()),
        Provider<MapService>(create: (_) => MapService()),
        Provider<PaymentService>(create: (_) => PaymentService()),
        Provider<LocalStorageService>(create: (_) => LocalStorageService()),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, child) => MaterialApp(
          title: 'SprayMap Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: controller.themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const LandingPage(),
            '/about': (context) => const AboutPage(),
            '/analytics': (context) => const AnalyticsScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const LoginScreen(startInSignUpMode: true),
            '/home': (context) => const HomeDashboard(),
            '/home_dashboard': (context) => const HomeDashboard(),
          },
        ),
      ),
    );
  }
}

