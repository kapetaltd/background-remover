import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cutout_colors.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CutoutColors.mat,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF8FD6B0) : CutoutColors.mat,
          onPrimary: isDark ? CutoutColors.matDark : Colors.white,
          secondary: CutoutColors.blade,
          onSecondary: CutoutColors.onBlade,
          tertiary: CutoutColors.blade,
          onTertiary: CutoutColors.onBlade,
          surface: isDark ? CutoutColors.surfaceDark : CutoutColors.surface,
          onSurface: isDark ? const Color(0xFFE8EDEA) : CutoutColors.ink,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final body = GoogleFonts.atkinsonHyperlegibleTextTheme(base.textTheme);
    TextStyle? heading(TextStyle? s) => s == null
        ? null
        : GoogleFonts.bricolageGrotesque(
            textStyle: s,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          );
    final textTheme = body
        .copyWith(
          displayLarge: heading(body.displayLarge),
          displayMedium: heading(body.displayMedium),
          displaySmall: heading(body.displaySmall),
          headlineLarge: heading(body.headlineLarge),
          headlineMedium: heading(body.headlineMedium),
          headlineSmall: heading(body.headlineSmall),
          titleLarge: heading(body.titleLarge),
          titleMedium: heading(body.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    const buttonSize = Size(64, 52);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final buttonText = textTheme.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? CutoutColors.matDark : CutoutColors.mat,
      extensions: [isDark ? CutoutTheme.dark : CutoutTheme.light],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CutoutColors.blade,
          foregroundColor: CutoutColors.onBlade,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline, width: 1.5),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: CutoutColors.bladeDeep,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 8,
        borderRadius: BorderRadius.circular(4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CutoutColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: CutoutColors.blade,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      focusColor: CutoutColors.blade.withValues(alpha: 0.35),
    );
  }
}
