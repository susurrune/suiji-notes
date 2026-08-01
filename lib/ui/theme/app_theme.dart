import 'package:flutter/material.dart';

/// 应用主题（Material 3，浅/深两套）。
///
/// 设计基调：简洁克制、卡片式布局为主（需求 §三）。选一个低饱和青绿色
/// 作为 seed，避免信息过载。
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF2E7D6B); // 青绿
  static const _warmPaper = Color(0xFFFAF8F4); // 暖纸底色

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      surface: _warmPaper,
    );
    return _base(Brightness.light, scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return _base(Brightness.dark, scheme);
  }

  static ThemeData _base(Brightness brightness, ColorScheme scheme) {
    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight ? _warmPaper : scheme.surface,
      // 细字重 + 更柔和的行高，让正文更耐读
      textTheme: const TextTheme(
        bodyLarge: TextStyle(height: 1.5),
        bodyMedium: TextStyle(height: 1.5),
        titleLarge: TextStyle(letterSpacing: 0.2),
      ),
      // 全局页面转场：淡入前移（M3 新规范），比默认 Zoom 更柔和艺术
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: isLight ? 0.5 : 0,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isLight ? _warmPaper : scheme.surface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: isLight ? scheme.onSurface : scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: isLight ? _warmPaper : scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: isLight ? 0.12 : 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF1EDE6) : scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: scheme.outline),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
    );
  }
}
