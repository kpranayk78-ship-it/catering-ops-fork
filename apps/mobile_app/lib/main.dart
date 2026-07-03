import 'services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/signup_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'role_views/owner/join_requests_screen.dart';
import 'core/env.dart';
import 'core/app_theme.dart';
import 'services/notification_service.dart';
import 'services/cache_service.dart';
import 'features/settings/screens/meet_developers_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: "assets/.env");

    // Initialize Push Notifications early
    await NotificationService.setupOneSignal();
    
    // Initialize Local Cache for Offline-First behavior
    await CacheService.init();

    await ThemeService.init();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    runApp(MyApp());
  } catch (e, stack) {
    debugPrint('FATAL STARTUP ERROR: $e');
    debugPrint(stack.toString());
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText('Fatal Startup Error: $e\n\n$stack'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeNotifier.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Catering Ops',
          theme: AppTheme.lightTheme,
          initialRoute: '/',
          routes: {
            '/': (context) => AuthGate(),
            '/login': (context) => LoginScreen(),
            '/signup': (context) => SignUpScreen(),
            '/dashboard': (context) => DashboardScreen(),
            '/join_requests': (context) => JoinRequestsScreen(),
            '/meet-developers': (context) => MeetOurDevelopersScreen(),
          },
        );
      }
    );
  }
}

class AuthGate extends StatelessWidget {
  AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return LoginScreen();
        return DashboardScreen();
      },
    );
  }
}
