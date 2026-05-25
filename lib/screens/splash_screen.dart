import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_manager.dart';
import '../services/supabase_auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/got_fet_loading.dart';

class GotFetSplashScreen extends StatefulWidget {
  const GotFetSplashScreen({super.key});

  @override
  State<GotFetSplashScreen> createState() => _GotFetSplashScreenState();
}

class _GotFetSplashScreenState extends State<GotFetSplashScreen> {
  String _version = 'Loading...';
  double _progress = .18;
  int _stageIndex = 0;
  String _loadingTitle = 'Splash / Loading';
  String _loadingMessage = 'Menyiapkan pengalaman inspeksi digital.';

  static const _stages = [
    'Splash',
    'Sinkronisasi',
    'Modul',
  ];

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
    await Future.delayed(const Duration(milliseconds: 420));
    _setLoadingStage(
      index: 1,
      progress: .54,
      title: 'Sinkronisasi Data Inspeksi',
      message: 'Memuat profil, role, dan preferensi akun.',
    );

    final auth = SupabaseAuthService();
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final session = await SessionManager.instance.getActiveSession();

    if (!mounted) return;

    if (supabaseUser == null || session == null) {
      await Future.delayed(const Duration(milliseconds: 360));
      if (!mounted) return;
      context.go('/login');
      return;
    }

    if (session.userId != supabaseUser.id) {
      await SessionManager.instance.nukeStaleSession(
        incomingUserId: supabaseUser.id,
      );
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 240));
      if (!mounted) return;
      context.go('/login');
      return;
    }

    _setLoadingStage(
      index: 2,
      progress: .86,
      title: 'Menyiapkan Dashboard',
      message: 'Menyusun modul, preferensi, dan data penting.',
    );

    final restored = await auth.restoreSession();
    if (!mounted) return;
    _setLoadingStage(
      index: 2,
      progress: 1,
      title: restored == null ? 'Mengarahkan Login' : 'Dashboard Siap',
      message: restored == null
          ? 'Sesi perlu diperbarui sebelum masuk.'
          : 'Data berhasil disiapkan untuk inspeksi.',
    );
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    context.go(restored == null ? '/login' : '/got-fet');
  }

  void _setLoadingStage({
    required int index,
    required double progress,
    required String title,
    required String message,
  }) {
    if (!mounted) return;
    setState(() {
      _stageIndex = index;
      _progress = progress;
      _loadingTitle = title;
      _loadingMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AdvantaColors.navy;
    final mutedColor =
        isDark ? Colors.white.withAlpha(190) : AdvantaColors.greenDark;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AdvantaColors.navyDark.withAlpha(246),
                        AdvantaColors.navy.withAlpha(225),
                        Colors.black.withAlpha(170),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withAlpha(235),
                        Colors.white.withAlpha(188),
                        Colors.white.withAlpha(18),
                      ],
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Container(
                    width: 154,
                    height: 154,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AdvantaColors.navyDeep.withAlpha(150)
                          : Colors.white.withAlpha(180),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(42)
                            : Colors.white.withAlpha(220),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? Colors.cyan : AdvantaColors.blue)
                              .withAlpha(isDark ? 70 : 28),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo_got_fet_unbox.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'GOT & FET',
                    textAlign: TextAlign.center,
                    style: AdvantaText.display.copyWith(
                      color: textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grow Out Test &\nField Emergence Test',
                    textAlign: TextAlign.center,
                    style: AdvantaText.heading3.copyWith(
                      color: mutedColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(flex: 3),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AdvantaColors.navyDeep.withAlpha(184)
                          : Colors.white.withAlpha(216),
                      borderRadius: AdvantaRadius.cardRadius,
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(30)
                            : Colors.white.withAlpha(210),
                      ),
                      boxShadow: AdvantaShadows.card(isDark),
                    ),
                    child: Column(
                      children: [
                        GotFetCircularProgress(
                          progress: _progress,
                          size: 82,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _loadingTitle,
                          textAlign: TextAlign.center,
                          style: AdvantaText.heading3.copyWith(
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _loadingMessage,
                          textAlign: TextAlign.center,
                          style: AdvantaText.caption.copyWith(
                            color: isDark
                                ? Colors.white.withAlpha(180)
                                : AdvantaColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        GotFetStepProgress(
                          steps: _stages,
                          activeIndex: _stageIndex,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'v$_version',
                    style: AdvantaText.caption.copyWith(
                      color: isDark
                          ? Colors.white.withAlpha(150)
                          : Colors.white.withAlpha(210),
                      shadows: [
                        Shadow(
                          color: Colors.black.withAlpha(100),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
