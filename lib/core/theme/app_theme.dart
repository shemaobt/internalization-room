import 'package:flutter/material.dart';

import 'sala_colors.dart';

abstract class AppTheme {
  static ThemeData light = _build(SalaColors.light, Brightness.light);
  static ThemeData dark = _build(SalaColors.dark, Brightness.dark);

  static ThemeData _build(SalaColors colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ShemaBrand.telha,
        brightness: brightness,
        surface: colors.paper,
      ),
      splashFactory: NoSplash.splashFactory,
      extensions: [colors],
    );
  }
}
