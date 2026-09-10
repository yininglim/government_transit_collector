import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const shellBlue = Color(0xFF123052);
  static const contentBlue = Color(0xFF245A8D);

  static final shellColorScheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
  ).copyWith(
    primary: shellBlue,
    onPrimary: Colors.white,
    secondary: contentBlue,
    onSecondary: Colors.white,
  );

  static ThemeData get light {
    return ThemeData(
      colorScheme: shellColorScheme.copyWith(
        primary: shellColorScheme.secondary,
        onPrimary: shellColorScheme.onSecondary,
        primaryContainer: shellColorScheme.secondaryContainer,
        onPrimaryContainer: shellColorScheme.onSecondaryContainer,
      ),
      inputDecorationTheme: const InputDecorationTheme(errorMaxLines: 6),
      useMaterial3: true,
    );
  }
}
