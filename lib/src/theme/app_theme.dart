import 'package:flutter/material.dart';

/// 品牌色：蓝 → 紫 → 青 的三色渐变体系，与设计稿保持一致。
abstract final class AppColors {
  static const Color primary = Color(0xFF2B5CFF);
  static const Color primaryLight = Color(0xFF6A8DFF);
  static const Color violet = Color(0xFF8F6BFF);
  static const Color teal = Color(0xFF2FD3C8);
  static const Color success = Color(0xFF1F9D63);

  static const Color pageStart = Color(0xFFF7F9FD);
  static const Color pageEnd = Color(0xFFEBEFF8);

  static const Color surfaceGlass = Color(0xF2FFFFFF);
  static const Color borderGlass = Color(0xB3FFFFFF);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B5CFF), Color(0xFF4F7DFF), Color(0xFF8F6BFF)],
  );

  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF2B5CFF),
      Color(0xFF6A8DFF),
      Color(0xFF9A6BFF),
      Color(0xFF2FD3C8),
    ],
  );

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [pageStart, pageEnd],
  );
}

/// 全局唯一的浅色 Material 3 主题。
ThemeData buildAppTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        secondary: AppColors.violet,
        tertiary: AppColors.teal,
        surface: Colors.white,
      );

  final TextTheme textTheme = Typography.material2021(colorScheme: scheme).black
      .apply(
        bodyColor: const Color(0xFF1F2D3D),
        displayColor: const Color(0xFF1F2D3D),
        fontFamilyFallback: const [
          'Microsoft YaHei',
          'PingFang SC',
          'Noto Sans SC',
        ],
      );

  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE4E9F2),
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.86),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      elevation: 18,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: textTheme.titleLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.78),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: scheme.outline, fontSize: 13),
      border: border(const Color(0xFFDCE4F2), 1),
      enabledBorder: border(const Color(0xFFDCE4F2), 1),
      focusedBorder: border(AppColors.primary, 1.4),
      errorBorder: border(scheme.error, 1),
      focusedErrorBorder: border(scheme.error, 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFD5DEEE)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xE61F2D3D),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 320),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF26364D),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(8),
      radius: const Radius.circular(8),
      thumbColor: WidgetStatePropertyAll<Color>(
        const Color(0xFFA9B8D4).withValues(alpha: 0.7),
      ),
    ),
  );
}
