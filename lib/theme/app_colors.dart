import 'package:flutter/material.dart';

class AppColors {
  static const Color glassBackground = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x4DFFFFFF);
  
  static const Color appleYellow = Color(0xFFFFD60A);
  static const Color appleWhite = Color(0xFFFFFFFF);
  static const Color appleGray = Color(0xFF8E8E93);
  
  static const Color neonBlue = appleYellow; // Aliasing for compatibility during refactor
  static const Color neonPink = Color(0xFFFF3B30); // iOS Red
  static const Color neonPurple = Color(0xFF5856D6); // iOS Indigo
  
  static const Color darkBackground = Color(0xFF000000);
  static const Color textPrimary = appleWhite;
  static const Color textSecondary = appleGray;

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
