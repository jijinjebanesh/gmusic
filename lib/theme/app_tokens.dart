import 'package:flutter/material.dart';

/// GMusic visual scale: radii, gaps, artwork metrics and motion, in one place.
/// Mirrors the Mornye design language (Material 3 Expressive).
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.radiusBadge,
    required this.radiusThumb,
    required this.radiusCover,
    required this.radiusControl,
    required this.radiusCard,
    required this.radiusSheet,
    required this.gapXs,
    required this.gapSm,
    required this.gapMd,
    required this.gapLg,
    required this.gapXl,
    required this.coverMini,
    required this.coverList,
    required this.playerControlGap,
    required this.motionFast,
    required this.motionMedium,
    required this.motionSlow,
    this.rowPaddingH = 20,
    this.rowPaddingV = 12,
  });

  static const AppTokens standard = AppTokens(
    radiusBadge: 6,
    radiusThumb: 5,
    radiusCover: 8,
    radiusControl: 8,
    radiusCard: 10,
    radiusSheet: 20,
    gapXs: 4,
    gapSm: 8,
    gapMd: 12,
    gapLg: 16,
    gapXl: 24,
    coverMini: 48,
    coverList: 56,
    playerControlGap: 20,
    motionFast: Duration(milliseconds: 150),
    motionMedium: Duration(milliseconds: 250),
    motionSlow: Duration(milliseconds: 400),
  );

  final double radiusBadge;
  final double radiusThumb;
  final double radiusCover;
  final double radiusControl;
  final double radiusCard;
  final double radiusSheet;
  final double gapXs;
  final double gapSm;
  final double gapMd;
  final double gapLg;
  final double gapXl;

  /// Mini player artwork.
  final double coverMini;

  /// Standard list row artwork.
  final double coverList;

  /// Gap between prev / play / next transport controls.
  final double playerControlGap;

  final Duration motionFast;
  final Duration motionMedium;
  final Duration motionSlow;

  final double rowPaddingH;
  final double rowPaddingV;

  BorderRadius get borderRadiusBadge => BorderRadius.circular(radiusBadge);
  BorderRadius get borderRadiusThumb => BorderRadius.circular(radiusThumb);
  BorderRadius get borderRadiusCover => BorderRadius.circular(radiusCover);
  BorderRadius get borderRadiusControl => BorderRadius.circular(radiusControl);
  BorderRadius get borderRadiusCard => BorderRadius.circular(radiusCard);

  @override
  AppTokens copyWith({
    double? radiusBadge,
    double? radiusThumb,
    double? radiusCover,
    double? radiusControl,
    double? radiusCard,
    double? radiusSheet,
    double? gapXs,
    double? gapSm,
    double? gapMd,
    double? gapLg,
    double? gapXl,
    double? coverMini,
    double? coverList,
    double? playerControlGap,
    Duration? motionFast,
    Duration? motionMedium,
    Duration? motionSlow,
    double? rowPaddingH,
    double? rowPaddingV,
  }) => AppTokens(
    radiusBadge: radiusBadge ?? this.radiusBadge,
    radiusThumb: radiusThumb ?? this.radiusThumb,
    radiusCover: radiusCover ?? this.radiusCover,
    radiusControl: radiusControl ?? this.radiusControl,
    radiusCard: radiusCard ?? this.radiusCard,
    radiusSheet: radiusSheet ?? this.radiusSheet,
    gapXs: gapXs ?? this.gapXs,
    gapSm: gapSm ?? this.gapSm,
    gapMd: gapMd ?? this.gapMd,
    gapLg: gapLg ?? this.gapLg,
    gapXl: gapXl ?? this.gapXl,
    coverMini: coverMini ?? this.coverMini,
    coverList: coverList ?? this.coverList,
    playerControlGap: playerControlGap ?? this.playerControlGap,
    motionFast: motionFast ?? this.motionFast,
    motionMedium: motionMedium ?? this.motionMedium,
    motionSlow: motionSlow ?? this.motionSlow,
    rowPaddingH: rowPaddingH ?? this.rowPaddingH,
    rowPaddingV: rowPaddingV ?? this.rowPaddingV,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    final d = lerpDouble;
    return AppTokens(
      radiusBadge: d(radiusBadge, other.radiusBadge, t),
      radiusThumb: d(radiusThumb, other.radiusThumb, t),
      radiusCover: d(radiusCover, other.radiusCover, t),
      radiusControl: d(radiusControl, other.radiusControl, t),
      radiusCard: d(radiusCard, other.radiusCard, t),
      radiusSheet: d(radiusSheet, other.radiusSheet, t),
      gapXs: d(gapXs, other.gapXs, t),
      gapSm: d(gapSm, other.gapSm, t),
      gapMd: d(gapMd, other.gapMd, t),
      gapLg: d(gapLg, other.gapLg, t),
      gapXl: d(gapXl, other.gapXl, t),
      coverMini: d(coverMini, other.coverMini, t),
      coverList: d(coverList, other.coverList, t),
      playerControlGap: d(playerControlGap, other.playerControlGap, t),
      motionFast: t < 0.5 ? motionFast : other.motionFast,
      motionMedium: t < 0.5 ? motionMedium : other.motionMedium,
      motionSlow: t < 0.5 ? motionSlow : other.motionSlow,
      rowPaddingH: d(rowPaddingH, other.rowPaddingH, t),
      rowPaddingV: d(rowPaddingV, other.rowPaddingV, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

extension AppTokensContext on BuildContext {
  /// Active [AppTokens]; falls back to [AppTokens.standard] outside a themed
  /// subtree (tests, isolated previews).
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.standard;
}
