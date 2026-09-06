import 'package:flutter/material.dart';

const _seedColor = Color(0xFF176B45);

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final scaffoldColor = isDark
      ? const Color(0xFF0F1511)
      : const Color(0xFFF5F7F5);
  final fieldColor = isDark ? const Color(0xFF18201B) : Colors.white;
  final outlineColor = isDark
      ? const Color(0xFF354039)
      : const Color(0xFFE1E7E2);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldColor,
    fontFamily: 'Microsoft YaHei',
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldColor,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: fieldColor,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF18201B) : Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    ),
    dividerColor: outlineColor,
  );
}
