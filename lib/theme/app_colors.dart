import 'package:flutter/material.dart';

class AppColors {
  static const Color glassBackground = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x4DFFFFFF);
  
  static const Color neonBlue = Color(0xFF00E5FF);
  static const Color neonPink = Color(0xFFFF00E5);
  static const Color neonPurple = Color(0xFFB000FF);
  
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x66FFFFFF),
      Color(0x1AFFFFFF),
    ],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      neonBlue,
      neonPurple,
    ],
  );
}
