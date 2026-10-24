import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle _style({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      decoration: decoration,
    );
  }

  // Branding
  static TextStyle get appName => _style(
    size: 30,
    weight: FontWeight.w700,
    letterSpacing: -1.2,
  );

  // Display
  static TextStyle get displayLarge =>
      _style(size: 48, weight: FontWeight.w700);

  static TextStyle get displayMedium =>
      _style(size: 40, weight: FontWeight.w700);

  static TextStyle get displaySmall =>
      _style(size: 36, weight: FontWeight.w700);

  // Headings
  static TextStyle get h1 =>
      _style(size: 32, weight: FontWeight.w700, letterSpacing: -.8);

  static TextStyle get h2 =>
      _style(size: 28, weight: FontWeight.w700, letterSpacing: -.5);

  static TextStyle get h3 =>
      _style(size: 24, weight: FontWeight.w600);

  static TextStyle get h4 =>
      _style(size: 20, weight: FontWeight.w600);

  static TextStyle get h5 =>
      _style(size: 18, weight: FontWeight.w600);

  static TextStyle get h6 =>
      _style(size: 16, weight: FontWeight.w600);

  // Body
  static TextStyle get bodyXL =>
      _style(size: 18, weight: FontWeight.w400, height: 1.5);

  static TextStyle get bodyLarge =>
      _style(size: 16, weight: FontWeight.w400, height: 1.5);

  static TextStyle get body =>
      _style(size: 14, weight: FontWeight.w400, height: 1.5);

  static TextStyle get bodySmall =>
      _style(size: 12, weight: FontWeight.w400, height: 1.4);

  // Labels
  static TextStyle get labelLarge =>
      _style(size: 14, weight: FontWeight.w600);

  static TextStyle get labelMedium =>
      _style(size: 12, weight: FontWeight.w500);

  static TextStyle get labelSmall =>
      _style(size: 10, weight: FontWeight.w500);

  // Buttons
  static TextStyle get button =>
      _style(size: 16, weight: FontWeight.w600);

  static TextStyle get buttonSmall =>
      _style(size: 14, weight: FontWeight.w600);

  // Inputs
  static TextStyle get input =>
      _style(size: 16, weight: FontWeight.w400);

  static TextStyle get inputHint =>
      _style(size: 16, weight: FontWeight.w400);

  static TextStyle get inputLabel =>
      _style(size: 13, weight: FontWeight.w500);

  // Links
  static TextStyle get link => _style(
    size: 14,
    weight: FontWeight.w600,
    // decoration: TextDecoration.underline,
  );

  static TextStyle get linkDecoration => _style(
    size: 14,
    weight: FontWeight.w600,
    decoration: TextDecoration.underline,
  );

  static TextStyle get privacyLink => _style(
    size: 13,
    weight: FontWeight.w500,
    decoration: TextDecoration.underline,
  );

  // Cards
  static TextStyle get cardTitle =>
      _style(size: 18, weight: FontWeight.w600);

  static TextStyle get cardSubtitle =>
      _style(size: 14, weight: FontWeight.w400);

  // Navigation
  static TextStyle get tab =>
      _style(size: 14, weight: FontWeight.w600);

  static TextStyle get bottomNavigation =>
      _style(size: 12, weight: FontWeight.w500);

  // Misc
  static TextStyle get caption =>
      _style(size: 11, weight: FontWeight.w400);

  static TextStyle get overline => _style(
    size: 10,
    weight: FontWeight.w600,
    letterSpacing: 1,
  );

  static TextStyle get badge =>
      _style(size: 12, weight: FontWeight.w700);

  static TextStyle get dialogTitle =>
      _style(size: 20, weight: FontWeight.w700);

  static TextStyle get dialogBody =>
      _style(size: 15, weight: FontWeight.w400, height: 1.5);
}