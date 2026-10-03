import 'package:flutter/material.dart';

/// Brand palette: a green self-healing cutting mat, a white work surface and
/// a yellow blade.
abstract final class CutoutColors {
  static const mat = Color(0xFF123B2A);
  static const matDark = Color(0xFF0A2219);
  static const matLine = Color(0x1FFFFFFF);
  static const matLineMajor = Color(0x38FFFFFF);

  static const blade = Color(0xFFFFD23F);
  static const bladeDeep = Color(0xFFE0AE00);
  static const onBlade = Color(0xFF1B1600);

  static const ink = Color(0xFF13201A);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF17201C);

  static const checkerLight = Color(0xFFFFFFFF);
  static const checkerDark = Color(0xFFE3E6E4);
  static const checkerLightDm = Color(0xFF2B312E);
  static const checkerDarkDm = Color(0xFF353C38);
}

/// Extra theme values that Material's [ColorScheme] has no slot for.
@immutable
class CutoutTheme extends ThemeExtension<CutoutTheme> {
  const CutoutTheme({
    required this.mat,
    required this.matLine,
    required this.matLineMajor,
    required this.blade,
    required this.onBlade,
    required this.checkerA,
    required this.checkerB,
  });

  final Color mat;
  final Color matLine;
  final Color matLineMajor;
  final Color blade;
  final Color onBlade;
  final Color checkerA;
  final Color checkerB;

  static const light = CutoutTheme(
    mat: CutoutColors.mat,
    matLine: CutoutColors.matLine,
    matLineMajor: CutoutColors.matLineMajor,
    blade: CutoutColors.blade,
    onBlade: CutoutColors.onBlade,
    checkerA: CutoutColors.checkerLight,
    checkerB: CutoutColors.checkerDark,
  );

  static const dark = CutoutTheme(
    mat: CutoutColors.matDark,
    matLine: Color(0x14FFFFFF),
    matLineMajor: Color(0x29FFFFFF),
    blade: CutoutColors.blade,
    onBlade: CutoutColors.onBlade,
    checkerA: CutoutColors.checkerLightDm,
    checkerB: CutoutColors.checkerDarkDm,
  );

  static CutoutTheme of(BuildContext context) =>
      Theme.of(context).extension<CutoutTheme>() ?? light;

  @override
  CutoutTheme copyWith({
    Color? mat,
    Color? matLine,
    Color? matLineMajor,
    Color? blade,
    Color? onBlade,
    Color? checkerA,
    Color? checkerB,
  }) {
    return CutoutTheme(
      mat: mat ?? this.mat,
      matLine: matLine ?? this.matLine,
      matLineMajor: matLineMajor ?? this.matLineMajor,
      blade: blade ?? this.blade,
      onBlade: onBlade ?? this.onBlade,
      checkerA: checkerA ?? this.checkerA,
      checkerB: checkerB ?? this.checkerB,
    );
  }

  @override
  CutoutTheme lerp(CutoutTheme? other, double t) {
    if (other == null) return this;
    return CutoutTheme(
      mat: Color.lerp(mat, other.mat, t)!,
      matLine: Color.lerp(matLine, other.matLine, t)!,
      matLineMajor: Color.lerp(matLineMajor, other.matLineMajor, t)!,
      blade: Color.lerp(blade, other.blade, t)!,
      onBlade: Color.lerp(onBlade, other.onBlade, t)!,
      checkerA: Color.lerp(checkerA, other.checkerA, t)!,
      checkerB: Color.lerp(checkerB, other.checkerB, t)!,
    );
  }
}
