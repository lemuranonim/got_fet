import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/got_fet/got_fet_screen.dart';
import 'screens/got_fet/got_fet_settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const GotFetSplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/got-fet',
      builder: (context, state) => const GotFetScreen(),
    ),
    GoRoute(
      path: '/got-fet/settings',
      builder: (context, state) => const GotFetSettingsScreen(),
    ),
  ],
  redirect: (context, state) async {
    final path = state.uri.path;
    if (path == '/splash') return null;

    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final session = await SessionManager.instance.getActiveSession();
    final isLoggedIn = supabaseUser != null && session != null;

    if (!isLoggedIn && path != '/login') return '/login';
    if (isLoggedIn && path == '/login') return '/got-fet';

    return null;
  },
);

class GotFetApp extends StatelessWidget {
  const GotFetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) {
        return MaterialApp.router(
          title: 'GOT & FET',
          theme: AdvantaTheme.light(),
          darkTheme: AdvantaTheme.dark(),
          themeMode: mode,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Gagal memulai GOT & FET:\n$errorMessage',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

    await themeController.load();

    runApp(const GotFetApp());
  } catch (e) {
    runApp(ErrorApp(errorMessage: e.toString()));
  }
}
