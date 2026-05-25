import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/session_manager.dart';
import '../services/supabase_auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SupabaseAuthService _auth = SupabaseAuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final supabaseUser = _auth.currentUser;
    if (supabaseUser == null) return;

    final session = await SessionManager.instance.getActiveSession();
    if (session == null) return;

    if (session.userId != supabaseUser.id) {
      await SessionManager.instance.nukeStaleSession(
        incomingUserId: supabaseUser.id,
      );
      return;
    }

    final appUser = await _auth.restoreSession();
    if (appUser != null && mounted) {
      context.go('/got-fet');
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Email dan password wajib diisi.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final appUser = await _auth.signInWithEmail(email, password);
    if (!mounted) return;

    if (appUser == null) {
      setState(() {
        _errorMessage = 'Login gagal. Periksa kembali email dan password.';
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = false);
    context.go('/got-fet');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _LoginPalette.navy,
              _LoginPalette.deepNavy,
              _LoginPalette.greenShade,
            ],
            stops: [0, 0.58, 1],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _LoginBackdrop()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final horizontalPadding = isWide ? 48.0 : 20.0;
                  final verticalPadding = isWide ? 40.0 : 22.0;
                  final minHeight = constraints.maxHeight > verticalPadding * 2
                      ? constraints.maxHeight - verticalPadding * 2
                      : 0.0;

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Expanded(
                                      flex: 6,
                                      child: _BrandPanel(),
                                    ),
                                    const SizedBox(width: 42),
                                    Expanded(
                                      flex: 5,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: _LoginPanel(
                                          emailController: _emailController,
                                          passwordController:
                                              _passwordController,
                                          isPasswordHidden: _isPasswordHidden,
                                          isLoading: _isLoading,
                                          errorMessage: _errorMessage,
                                          onTogglePassword: () => setState(
                                            () => _isPasswordHidden =
                                                !_isPasswordHidden,
                                          ),
                                          onLogin: _login,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _BrandPanel(compact: true),
                                    const SizedBox(height: 24),
                                    _LoginPanel(
                                      emailController: _emailController,
                                      passwordController: _passwordController,
                                      isPasswordHidden: _isPasswordHidden,
                                      isLoading: _isLoading,
                                      errorMessage: _errorMessage,
                                      onTogglePassword: () => setState(
                                        () => _isPasswordHidden =
                                            !_isPasswordHidden,
                                      ),
                                      onLogin: _login,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPalette {
  const _LoginPalette._();

  static const Color navy = Color(0xFF003878);
  static const Color deepNavy = Color(0xFF001C4E);
  static const Color ink = Color(0xFF071833);
  static const Color green = Color(0xFF08A84F);
  static const Color greenShade = Color(0xFF00624E);
  static const Color ivory = Color(0xFFFBFCF8);
  static const Color border = Color(0xFFE2E8EF);
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LoginBackdropPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(13)
      ..strokeWidth = 1;

    for (var x = -size.height; x < size.width; x += 92) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.45, size.height),
        linePaint,
      );
    }

    final ridgePaint = Paint()
      ..color = _LoginPalette.green.withAlpha(34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.58 + i * 0.085);
      final path = Path()
        ..moveTo(-40, y)
        ..cubicTo(
          size.width * 0.22,
          y - 54,
          size.width * 0.48,
          y + 42,
          size.width + 40,
          y - 18,
        );
      canvas.drawPath(path, ridgePaint);
    }

    final shade = Paint()..color = Colors.black.withAlpha(36);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.58, 0, size.width * 0.42, size.height),
      shade,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrandPanel extends StatelessWidget {
  final bool compact;

  const _BrandPanel({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 108.0 : 152.0;
    final titleSize = compact ? 36.0 : 54.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        _LogoMark(size: logoSize),
        SizedBox(height: compact ? 18 : 26),
        Text(
          'GOT & FET',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: AdvantaText.display.copyWith(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Grow Out & Field Emergence Test',
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: AdvantaText.heading2.copyWith(
              color: Colors.white.withAlpha(224),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 34),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SignalChip(
                icon: Icons.verified_rounded,
                label: 'QA Ready',
              ),
              _SignalChip(
                icon: Icons.eco_rounded,
                label: 'Field Data',
              ),
              _SignalChip(
                icon: Icons.lock_rounded,
                label: 'Secure Session',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double size;

  const _LogoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.02),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: Colors.white.withAlpha(58)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(54),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Image.asset(
        'assets/logo_got_fet.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.eco_rounded,
          color: Colors.white,
          size: size * 0.46,
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SignalChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF8CF3B4), size: 17),
          const SizedBox(width: 8),
          Text(
            label,
            style: AdvantaText.label.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isPasswordHidden;
  final bool isLoading;
  final String errorMessage;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;

  const _LoginPanel({
    required this.emailController,
    required this.passwordController,
    required this.isPasswordHidden,
    required this.isLoading,
    required this.errorMessage,
    required this.onTogglePassword,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 450),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
        decoration: BoxDecoration(
          color: _LoginPalette.ivory,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withAlpha(210), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(58),
              blurRadius: 34,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'assets/logo_got_fet.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Masuk',
                          style: AdvantaText.heading1.copyWith(
                            color: _LoginPalette.ink,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Akses workspace GOT & FET',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.body2.copyWith(
                            color: _LoginPalette.ink.withAlpha(150),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _PremiumTextField(
                controller: emailController,
                label: 'Email',
                hint: 'nama@perusahaan.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 14),
              _PremiumTextField(
                controller: passwordController,
                label: 'Password',
                hint: 'Masukkan password',
                icon: Icons.lock_rounded,
                obscureText: isPasswordHidden,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => onLogin(),
                suffix: IconButton(
                  tooltip: isPasswordHidden
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  onPressed: onTogglePassword,
                  icon: Icon(
                    isPasswordHidden
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
              if (errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                _LoginErrorBanner(message: errorMessage),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : onLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _LoginPalette.green,
                    disabledBackgroundColor: _LoginPalette.green.withAlpha(110),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 20),
                  label: Text(isLoading ? 'MEMPROSES' : 'MASUK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      cursorColor: _LoginPalette.green,
      style: AdvantaText.bodyBold.copyWith(
        color: _LoginPalette.ink,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        labelStyle: AdvantaText.body2.copyWith(
          color: _LoginPalette.ink.withAlpha(150),
          fontWeight: FontWeight.w700,
        ),
        hintStyle: AdvantaText.body2.copyWith(
          color: _LoginPalette.ink.withAlpha(92),
        ),
        prefixIconColor: _LoginPalette.green,
        suffixIconColor: _LoginPalette.ink.withAlpha(150),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _LoginPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: _LoginPalette.green,
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  final String message;

  const _LoginErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC6C6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AdvantaColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AdvantaText.body2.copyWith(
                color: AdvantaColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
