import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/session_manager.dart';
import '../services/supabase_auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/got_fet_loading.dart';

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
  bool _rememberMe = true;
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

  void _toggleTheme() {
    final next = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeController.setMode(next);
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature belum aktif di versi ini.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor = isDark ? Colors.white : AdvantaColors.navy;

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
                        AdvantaColors.navyDark.withAlpha(250),
                        AdvantaColors.navy.withAlpha(232),
                        AdvantaColors.navyDark.withAlpha(198),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withAlpha(246),
                        Colors.white.withAlpha(232),
                        Colors.white.withAlpha(80),
                      ],
                    ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 860;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 48 : 22,
                    20,
                    isWide ? 48 : 22,
                    28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: isWide
                            ? Row(
                                children: [
                                  Expanded(
                                    child:
                                        _LoginBrand(contentColor: contentColor),
                                  ),
                                  const SizedBox(width: 44),
                                  Expanded(
                                    child: _LoginCard(
                                      rememberMe: _rememberMe,
                                      emailController: _emailController,
                                      passwordController: _passwordController,
                                      isPasswordHidden: _isPasswordHidden,
                                      isLoading: _isLoading,
                                      errorMessage: _errorMessage,
                                      onRememberChanged: (value) => setState(
                                        () => _rememberMe = value ?? false,
                                      ),
                                      onTogglePassword: () => setState(
                                        () => _isPasswordHidden =
                                            !_isPasswordHidden,
                                      ),
                                      onLogin: _login,
                                      onGoogleLogin: () =>
                                          _showComingSoon('Login Google'),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton.filledTonal(
                                      tooltip: 'Ganti tema',
                                      onPressed: _toggleTheme,
                                      icon: Icon(
                                        isDark
                                            ? Icons.light_mode_rounded
                                            : Icons.dark_mode_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _LoginBrand(
                                    contentColor: contentColor,
                                    compact: true,
                                  ),
                                  const SizedBox(height: 24),
                                  _LoginCard(
                                    rememberMe: _rememberMe,
                                    emailController: _emailController,
                                    passwordController: _passwordController,
                                    isPasswordHidden: _isPasswordHidden,
                                    isLoading: _isLoading,
                                    errorMessage: _errorMessage,
                                    onRememberChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                    onTogglePassword: () => setState(
                                      () => _isPasswordHidden =
                                          !_isPasswordHidden,
                                    ),
                                    onLogin: _login,
                                    onGoogleLogin: () =>
                                        _showComingSoon('Login Google'),
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
    );
  }
}

class _LoginBrand extends StatelessWidget {
  final Color contentColor;
  final bool compact;

  const _LoginBrand({
    required this.contentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final logoWidth = compact ? 176.0 : 260.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/logo_got_fet_unbox.png',
          width: logoWidth,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 20),
        Text(
          'Selamat Datang',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: AdvantaText.display.copyWith(
            color: contentColor,
            fontSize: compact ? 28 : 38,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Digital Inspection for Quality Seeds',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: AdvantaText.heading3.copyWith(
            color: contentColor.withAlpha(190),
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final bool rememberMe;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isPasswordHidden;
  final bool isLoading;
  final String errorMessage;
  final ValueChanged<bool?> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onGoogleLogin;

  const _LoginCard({
    required this.rememberMe,
    required this.emailController,
    required this.passwordController,
    required this.isPasswordHidden,
    required this.isLoading,
    required this.errorMessage,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onGoogleLogin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark
        ? AdvantaColors.navyDeep.withAlpha(212)
        : Colors.white.withAlpha(236);
    final borderColor =
        isDark ? Colors.white.withAlpha(32) : AdvantaColors.lineLight;
    final textColor = isDark ? Colors.white : AdvantaColors.textDark;
    final mutedColor =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: AdvantaShadows.card(isDark),
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Masuk untuk memulai inspeksi lapangan',
              style: AdvantaText.heading3.copyWith(color: textColor),
            ),
            const SizedBox(height: 10),
            const _AccountRoleNotice(),
            const SizedBox(height: 18),
            _LoginField(
              controller: emailController,
              label: 'Email atau Username',
              hint: 'Masukkan email atau username',
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 13),
            _LoginField(
              controller: passwordController,
              label: 'Password',
              hint: 'Masukkan password',
              icon: Icons.lock_outline_rounded,
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
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: rememberMe,
                    onChanged: onRememberChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ingat saya',
                    style: AdvantaText.body2.copyWith(color: mutedColor),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Lupa Password?'),
                ),
              ],
            ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              AdvantaBanner.error(message: errorMessage),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : onLogin,
                child: isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const GotFetPulsingDots(size: 6),
                          const SizedBox(width: 12),
                          Text(
                            'Memverifikasi akun...',
                            style: AdvantaText.button
                                .copyWith(color: Colors.white),
                          ),
                        ],
                      )
                    : const Text('Masuk Sekarang'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: borderColor)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'atau',
                    style: AdvantaText.caption.copyWith(color: mutedColor),
                  ),
                ),
                Expanded(child: Divider(color: borderColor)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onGoogleLogin,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: const Text('Masuk dengan Google'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: mutedColor,
                ),
                const SizedBox(width: 7),
                Text(
                  'Keamanan data terjamin',
                  style: AdvantaText.caption.copyWith(color: mutedColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRoleNotice extends StatelessWidget {
  const _AccountRoleNotice();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdvantaColors.green.withAlpha(isDark ? 36 : 20),
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(
          color: AdvantaColors.green.withAlpha(isDark ? 86 : 58),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AdvantaColors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Role otomatis dari database',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.bodyBold.copyWith(
                    color: isDark ? Colors.white : AdvantaColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Masuk dengan email terdaftar untuk memuat hak akses akun.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
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

  const _LoginField({
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
      style: AdvantaText.bodyBold,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}
