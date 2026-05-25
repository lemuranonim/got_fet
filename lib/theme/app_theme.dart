import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdvantaColors {
  AdvantaColors._();

  static const Color navy = Color(0xFF06346F);
  static const Color navyDeep = Color(0xFF031A3D);
  static const Color navyDark = Color(0xFF06152F);
  static const Color blue = Color(0xFF1687D9);
  static const Color green = Color(0xFF25B34B);
  static const Color greenDark = Color(0xFF0B8E45);
  static const Color greenSoft = Color(0xFFEAF8EE);
  static const Color skySoft = Color(0xFFEFF8FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBackground = Color(0xFFF5FAFF);
  static const Color darkSurface = Color(0xFF0B2347);
  static const Color darkSurfaceAlt = Color(0xFF0E2D5B);
  static const Color lineLight = Color(0xFFE2EAF3);
  static const Color lineDark = Color(0xFF264A76);
  static const Color textDark = Color(0xFF06214A);
  static const Color textMuted = Color(0xFF6B7A90);
  static const Color textMutedDark = Color(0xFF9FB2CF);
  static const Color warning = Color(0xFFF6A11A);

  static const Color deepForest = Color(0xFF0D3D2B);
  static const Color primaryGreen = green;
  static const Color midGreen = greenDark;
  static const Color lightGreen = Color(0xFF61D37F);
  static const Color paleGreen = greenSoft;
  static const Color gold = warning;
  static const Color goldLight = Color(0xFFFFCB55);
  static const Color goldPale = Color(0xFFFFF8E1);
  static const Color cream = Color(0xFFFAFCFF);
  static const Color charcoal = Color(0xFF1C2526);
  static const Color softGrey = Color(0xFFF3F7FB);
  static const Color dividerGrey = lineLight;
  static const Color mutedGrey = textMuted;
  static const Color success = green;
  static const Color successLight = greenSoft;
  static const Color error = Color(0xFFE04F5F);
  static const Color errorLight = Color(0xFFFFEEF0);
}

class AdvantaText {
  AdvantaText._();
  static const String _fontFamily = 'Nunito';

  static const TextStyle display = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
    height: 1.12,
  );
  static const TextStyle heading1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.24,
  );
  static const TextStyle heading2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.28,
  );
  static const TextStyle heading3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.35,
  );
  static const TextStyle body1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.48,
  );
  static const TextStyle body2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.45,
  );
  static const TextStyle bodyBold = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.42,
  );
  static const TextStyle label = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.35,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.35,
  );
  static const TextStyle button = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
    height: 1,
  );
  static const TextStyle brandTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
  static const TextStyle brandSubtitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
}

class AdvantaRadius {
  AdvantaRadius._();
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(8));
  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(12));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(100));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(24));
  static const BorderRadius dialogRadius =
      BorderRadius.all(Radius.circular(22));
  static const BorderRadius buttonRadius =
      BorderRadius.all(Radius.circular(12));
}

class AdvantaShadows {
  AdvantaShadows._();

  static List<BoxShadow> card(bool isDark) => [
        BoxShadow(
          color: isDark
              ? Colors.black.withAlpha(90)
              : AdvantaColors.navy.withAlpha(16),
          blurRadius: isDark ? 20 : 18,
          offset: const Offset(0, 8),
        ),
      ];
}

class AdvantaTheme {
  AdvantaTheme._();

  static ThemeData light() {
    final colorScheme = const ColorScheme.light(
      primary: AdvantaColors.green,
      onPrimary: Colors.white,
      secondary: AdvantaColors.blue,
      onSecondary: Colors.white,
      surface: AdvantaColors.lightSurface,
      onSurface: AdvantaColors.textDark,
      error: AdvantaColors.error,
      onError: Colors.white,
    );

    return _buildTheme(colorScheme, AdvantaColors.lightBackground);
  }

  static ThemeData dark() {
    final colorScheme = const ColorScheme.dark(
      primary: AdvantaColors.green,
      onPrimary: Colors.white,
      secondary: AdvantaColors.blue,
      onSecondary: Colors.white,
      surface: AdvantaColors.darkSurface,
      onSurface: Colors.white,
      error: AdvantaColors.error,
      onError: Colors.white,
    );

    return _buildTheme(colorScheme, AdvantaColors.navyDark);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Color scaffoldBgColor) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final outline = isDark ? AdvantaColors.lineDark : AdvantaColors.lineLight;
    final muted =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;
    final surface = isDark ? AdvantaColors.darkSurface : Colors.white;

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBgColor,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AdvantaColors.navyDark : Colors.white,
        foregroundColor: isDark ? Colors.white : AdvantaColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: AdvantaText.brandTitle.copyWith(
          color: isDark ? Colors.white : AdvantaColors.textDark,
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AdvantaColors.textDark,
          size: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AdvantaRadius.cardRadius,
          side: BorderSide(color: outline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.primary.withAlpha(105),
          disabledForegroundColor: Colors.white.withAlpha(170),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
          textStyle: AdvantaText.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AdvantaRadius.buttonRadius,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : AdvantaColors.navy,
          side: BorderSide(color: outline),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          shape: const RoundedRectangleBorder(
            borderRadius: AdvantaRadius.buttonRadius,
          ),
          textStyle: AdvantaText.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? AdvantaColors.navyDeep.withAlpha(160) : Colors.white,
        labelStyle: AdvantaText.body2.copyWith(color: muted),
        hintStyle: AdvantaText.body2.copyWith(color: muted.withAlpha(180)),
        prefixIconColor:
            isDark ? AdvantaColors.textMutedDark : AdvantaColors.navy,
        suffixIconColor:
            isDark ? AdvantaColors.textMutedDark : AdvantaColors.navy,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: const OutlineInputBorder(
          borderRadius: AdvantaRadius.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AdvantaRadius.inputRadius,
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AdvantaRadius.inputRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: isDark ? AdvantaColors.navyDeep : Colors.white,
        indicatorColor: isDark
            ? AdvantaColors.green.withAlpha(38)
            : AdvantaColors.greenSoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AdvantaText.caption.copyWith(
            color: states.contains(WidgetState.selected)
                ? AdvantaColors.green
                : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
          ),
        ),
      ),
      textTheme: TextTheme(
        displayLarge:
            AdvantaText.display.copyWith(color: colorScheme.onSurface),
        headlineLarge:
            AdvantaText.heading1.copyWith(color: colorScheme.onSurface),
        headlineMedium:
            AdvantaText.heading2.copyWith(color: colorScheme.onSurface),
        headlineSmall:
            AdvantaText.heading3.copyWith(color: colorScheme.onSurface),
        bodyLarge: AdvantaText.body1.copyWith(color: colorScheme.onSurface),
        bodyMedium: AdvantaText.body2.copyWith(color: colorScheme.onSurface),
        labelMedium: AdvantaText.label.copyWith(color: colorScheme.onSurface),
      ),
    );
  }
}

class AdvantaBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const AdvantaBanner.error({super.key, required this.message})
      : isError = true;
  const AdvantaBanner.info({super.key, required this.message})
      : isError = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isError
        ? (isDark
            ? AdvantaColors.error.withAlpha(34)
            : AdvantaColors.errorLight)
        : (isDark
            ? AdvantaColors.green.withAlpha(30)
            : AdvantaColors.greenSoft);
    final fg = isError ? AdvantaColors.error : AdvantaColors.greenDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(color: fg.withAlpha(isDark ? 90 : 60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline,
              color: fg, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AdvantaText.body2.copyWith(color: fg, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
