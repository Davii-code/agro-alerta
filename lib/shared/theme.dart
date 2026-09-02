import 'package:flutter/material.dart';

/// Visual language for Agro Alerta.
///
/// Two constraints drove the sizing here, both from the user rather than from
/// taste: the app is read outdoors in direct sun, and it is operated with dirty
/// or gloved hands. So body text never drops below 14sp, primary content sits at
/// 16sp or more, and every tappable target is at least 48dp.
class AgroTheme {
  // --- Brand ---------------------------------------------------------------
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF81C784);
  static const Color accent = Color(0xFF4CAF50);
  static const Color lightBg = Color(0xFFF1F5F2);
  static const Color cardBg = Colors.white;
  static const Color darkBg = Color(0xFF0F1E15);

  // --- Traffic light -------------------------------------------------------
  // These three carry meaning, not decoration: they are the whole answer the
  // producer came for. Each has a tint for backgrounds and a strong tone for
  // text, so a coloured chip still passes contrast on white.
  static const Color statusGreen = Color(0xFF2E7D32);
  static const Color statusGreenTint = Color(0xFFE8F5E9);
  static const Color statusYellow = Color(0xFFB25000);
  static const Color statusYellowTint = Color(0xFFFFF3E0);
  static const Color statusRed = Color(0xFFB3261E);
  static const Color statusRedTint = Color(0xFFFDECEA);
  static const Color legendPurple = Color(0xFF6A1B9A);

  static const Color info = Color(0xFF0D5FA6);
  static const Color infoTint = Color(0xFFE3F2FD);

  // --- Text ----------------------------------------------------------------
  // textGray replaces the old 0xFF757575, which fell below 4.5:1 on white and
  // was effectively invisible on a phone screen in sunlight.
  static const Color textGray = Color(0xFF5A5F5C);
  static const Color textDark = Color(0xFF1A1C1A);
  static const Color divider = Color(0xFFDFE4E0);

  /// Minimum comfortable touch target, used by every custom control.
  static const double minTouchTarget = 48.0;

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        secondary: accent,
        surface: Colors.white,
        error: statusRed,
      ),
      scaffoldBackgroundColor: lightBg,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: textDark, height: 1.4),
        bodyMedium: TextStyle(fontSize: 15, color: textDark, height: 1.4),
        bodySmall: TextStyle(fontSize: 14, color: textGray, height: 1.35),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textDark, size: 26),
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: divider, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          minimumSize: const Size(0, minTouchTarget),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: statusRed, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textGray, fontSize: 16),
        hintStyle: const TextStyle(color: textGray, fontSize: 16),
        errorStyle: const TextStyle(color: statusRed, fontSize: 14),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontSize: 16, color: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        contentTextStyle: const TextStyle(fontSize: 16, color: textDark),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: textGray,
        selectedLabelStyle:
            TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        unselectedLabelStyle: TextStyle(fontSize: 13),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
