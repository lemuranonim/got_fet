import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_manager.dart';
import '../services/supabase_auth_service.dart';
import '../theme/app_theme.dart';

class GotFetSplashScreen extends StatefulWidget {
  const GotFetSplashScreen({super.key});

  @override
  State<GotFetSplashScreen> createState() => _GotFetSplashScreenState();
}

class _GotFetSplashScreenState extends State<GotFetSplashScreen> {
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    unawaited(_continue());
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = packageInfo.version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'Dev');
    }
  }

  Future<void> _continue() async {
    await Future.delayed(const Duration(milliseconds: 900));

    final auth = SupabaseAuthService();
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final session = await SessionManager.instance.getActiveSession();

    if (!mounted) return;

    if (supabaseUser == null || session == null) {
      context.go('/login');
      return;
    }

    if (session.userId != supabaseUser.id) {
      await SessionManager.instance.nukeStaleSession(
        incomingUserId: supabaseUser.id,
      );
      if (!mounted) return;
      context.go('/login');
      return;
    }

    final restored = await auth.restoreSession();
    if (!mounted) return;
    context.go(restored == null ? '/login' : '/got-fet');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColors = isDark
        ? [
            AdvantaColors.deepForest,
            const Color(0xFF112E20),
            const Color(0xFF0A2318),
          ]
        : [
            const Color(0xFF061A44),
            const Color(0xFF0A3D5E),
            AdvantaColors.primaryGreen,
          ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bgColors,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 132,
                    height: 132,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: Colors.white.withAlpha(20),
                      border: Border.all(color: Colors.white.withAlpha(60)),
                    ),
                    child: Image.asset(
                      'assets/logo_got_fet.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'GOT & FET',
                    style: AdvantaText.display.copyWith(
                      color: Colors.white,
                      fontSize: 32,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seed quality workflow',
                    style: AdvantaText.body2.copyWith(
                      color: Colors.white.withAlpha(180),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'v$_version',
                    style: AdvantaText.caption.copyWith(
                      color: Colors.white.withAlpha(150),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
