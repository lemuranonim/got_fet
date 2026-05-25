import 'dart:async';
import 'dart:math' as math;

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
  static const _minimumSplashDuration = Duration(seconds: 3);

  final DateTime _startedAt = DateTime.now();
  String _version = 'Loading...';
  double _progress = .18;

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
    _setLoadingProgress(
      progress: .54,
    );

    final auth = SupabaseAuthService();
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final session = await SessionManager.instance.getActiveSession();

    if (!mounted) return;

    if (supabaseUser == null || session == null) {
      await Future.delayed(const Duration(milliseconds: 360));
      if (!mounted) return;
      await _waitForMinimumSplash();
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
      await _waitForMinimumSplash();
      if (!mounted) return;
      context.go('/login');
      return;
    }

    _setLoadingProgress(
      progress: .86,
    );

    final restored = await auth.restoreSession();
    if (!mounted) return;
    _setLoadingProgress(
      progress: 1,
    );
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    await _waitForMinimumSplash();
    if (!mounted) return;
    context.go(restored == null ? '/login' : '/got-fet');
  }

  Future<void> _waitForMinimumSplash() async {
    final elapsed = DateTime.now().difference(_startedAt);
    final remaining = _minimumSplashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  void _setLoadingProgress({
    required double progress,
  }) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
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
                  _SplashLoadingMark(
                    progress: _progress,
                    isDark: isDark,
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

class _SplashLoadingMark extends StatelessWidget {
  final double progress;
  final bool isDark;

  const _SplashLoadingMark({
    required this.progress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor =
        isDark ? Colors.white.withAlpha(54) : Colors.white.withAlpha(210);
    final progressValue = progress.clamp(0.0, 1.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PremiumOrbitRing(
          progress: progressValue,
          trackColor: trackColor,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        Text(
          'Memuat...',
          textAlign: TextAlign.center,
          style: AdvantaText.heading3.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumOrbitRing extends StatefulWidget {
  final double progress;
  final Color trackColor;
  final bool isDark;

  const _PremiumOrbitRing({
    required this.progress,
    required this.trackColor,
    required this.isDark,
  });

  @override
  State<_PremiumOrbitRing> createState() => _PremiumOrbitRingState();
}

class _PremiumOrbitRingState extends State<_PremiumOrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.progress),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: const Size.square(64),
              painter: _PremiumOrbitRingPainter(
                orbit: _controller.value,
                progress: progress,
                trackColor: widget.trackColor,
                isDark: widget.isDark,
              ),
            );
          },
        );
      },
    );
  }
}

class _PremiumOrbitRingPainter extends CustomPainter {
  final double orbit;
  final double progress;
  final Color trackColor;
  final bool isDark;

  const _PremiumOrbitRingPainter({
    required this.orbit,
    required this.progress,
    required this.trackColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 11) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final start = (orbit * math.pi * 2) - math.pi / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(isDark ? 128 : 210);
    canvas.drawArc(
      rect.deflate(7),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..color = AdvantaColors.green.withAlpha(105);
    canvas.drawArc(rect, start, math.pi * .86, false, glowPaint);

    final greenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round
      ..color = AdvantaColors.green;
    canvas.drawArc(rect, start, math.pi * .86, false, greenPaint);

    final blueGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = AdvantaColors.blue.withAlpha(isDark ? 90 : 68);
    final blueStart = start + math.pi * 1.25;
    canvas.drawArc(
        rect.deflate(2), blueStart, math.pi * .36, false, blueGlowPaint);

    final bluePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..color = AdvantaColors.navy;
    canvas.drawArc(rect.deflate(2), blueStart, math.pi * .36, false, bluePaint);

    final pulse = .58 + (math.sin(orbit * math.pi * 2) + 1) * .11;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withAlpha((pulse * 255).round());
    canvas.drawCircle(center, 2.7, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _PremiumOrbitRingPainter oldDelegate) {
    return oldDelegate.orbit != orbit ||
        oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.isDark != isDark;
  }
}
