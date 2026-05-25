import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/got_fet_loading.dart';

class GotFetSettingsScreen extends StatefulWidget {
  const GotFetSettingsScreen({super.key});

  @override
  State<GotFetSettingsScreen> createState() => _GotFetSettingsScreenState();
}

class _GotFetSettingsScreenState extends State<GotFetSettingsScreen> {
  ActiveSession? _session;
  bool _isLoading = true;
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadSession();
    _fetchVersion();
  }

  Future<void> _loadSession() async {
    final session = await SessionManager.instance.getActiveSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _isLoading = false;
    });
  }

  Future<void> _fetchVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = packageInfo.version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'Dev');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: AdvantaRadius.dialogRadius),
          title: Text(
            'Keluar dari GOT & FET?',
            style: AdvantaText.heading2
                .copyWith(color: theme.colorScheme.onSurface),
          ),
          content: Text(
            'Sesi pengguna di perangkat ini akan dihapus. Setelah login ulang, user akan masuk kembali ke GOT & FET.',
            style: AdvantaText.body1
                .copyWith(color: theme.colorScheme.onSurface.withAlpha(180)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Batal',
                style: AdvantaText.bodyBold
                    .copyWith(color: AdvantaColors.mutedGrey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdvantaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('KELUAR'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await SessionManager.instance
        .clearSessionOnLogout(userId: _session?.userId);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AdvantaColors.textDark;
    final mutedColor =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;

    return Scaffold(
      backgroundColor:
          isDark ? AdvantaColors.navyDark : AdvantaColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AdvantaColors.navyDark : Colors.white,
        foregroundColor: isDark ? Colors.white : AdvantaColors.navy,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('GOT & FET Settings'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const _SettingsLoadingState()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  const _SettingsSectionLabel('AKUN'),
                  _ProfileCard(
                    name: _session?.name.trim().isNotEmpty == true
                        ? _session!.name
                        : 'GOT & FET User',
                    email: _session?.email ?? '-',
                    role: _session?.role ?? '-',
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                  const SizedBox(height: 22),
                  const _SettingsSectionLabel('INFORMASI APLIKASI'),
                  _SettingsTile(
                    icon: Icons.verified_user_rounded,
                    title: 'Role',
                    value: _session?.role ?? '-',
                  ),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Action',
                    value: _session?.action ?? '-',
                  ),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.energy_savings_leaf_rounded,
                    title: 'Modul Aktif',
                    value: 'GOT & FET',
                  ),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Versi Aplikasi',
                    value: _version,
                  ),
                  const SizedBox(height: 22),
                  const _SettingsSectionLabel('PREFERENSI'),
                  _ThemeModeCard(),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdvantaColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('KELUAR'),
                      onPressed: _logout,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettingsLoadingState extends StatelessWidget {
  const _SettingsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GotFetSkeletonList(itemCount: 1),
          SizedBox(height: 18),
          GotFetSkeletonList(itemCount: 4),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String label;

  const _SettingsSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Text(
        label,
        style: AdvantaText.label.copyWith(
          color: isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final Color textColor;
  final Color mutedColor;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.role,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AdvantaColors.darkSurface : Colors.white,
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(
          color: isDark ? AdvantaColors.lineDark : AdvantaColors.lineLight,
        ),
        boxShadow: AdvantaShadows.card(isDark),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withAlpha(10) : AdvantaColors.skySoft,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/logo_got_fet_unbox.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.heading2.copyWith(color: textColor),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.body2.copyWith(color: mutedColor),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AdvantaColors.green.withAlpha(isDark ? 44 : 24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdvantaText.caption.copyWith(
                      color: isDark ? Colors.white : AdvantaColors.greenDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AdvantaColors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: isDark ? AdvantaColors.darkSurface : Colors.white,
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(
          color: isDark ? AdvantaColors.lineDark : AdvantaColors.lineLight,
        ),
        boxShadow: AdvantaShadows.card(isDark),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AdvantaColors.green.withAlpha(isDark ? 36 : 20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isDark ? Colors.white : AdvantaColors.primaryGreen,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AdvantaText.bodyBold.copyWith(
                    color: isDark ? Colors.white : AdvantaColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AdvantaText.body2.copyWith(
                    color: isDark
                        ? AdvantaColors.textMutedDark
                        : AdvantaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color:
                isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AdvantaColors.textDark;
    final mutedColor =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AdvantaColors.darkSurface : Colors.white,
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(
          color: isDark ? AdvantaColors.lineDark : AdvantaColors.lineLight,
        ),
        boxShadow: AdvantaShadows.card(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tampilan',
            style: AdvantaText.bodyBold.copyWith(color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Pilih tema aplikasi GOT & FET.',
            style: AdvantaText.body2.copyWith(color: mutedColor),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeController,
            builder: (context, mode, _) {
              return SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.phone_android_rounded),
                      label: Text('Sistem'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Light'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    themeController.setMode(selection.first);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
