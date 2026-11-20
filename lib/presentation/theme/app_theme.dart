import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warm, paper-like palette: ivory and charcoal surfaces, one clay accent.
abstract final class Palette {
  static const clay = Color(0xFFD97757);
  static const ivory = Color(0xFFFAF9F5);
  static const parchment = Color(0xFFF0EEE6);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF141413);
  static const stone = Color(0xFF6B6A63);
  static const sand = Color(0xFFE3E0D6);
  static const night = Color(0xFF1F1E1D);
  static const charcoal = Color(0xFF262624);
  static const slate = Color(0xFF30302E);
  static const ash = Color(0xFFA3A098);
  static const seam = Color(0xFF3E3D39);
  static const sage = Color(0xFF6E9E6A);
  static const amber = Color(0xFFD9A441);
  static const brick = Color(0xFFC4554D);
}

/// Semantic colours Material's scheme has no slot for.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.line,
    required this.raised,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color muted, line, raised, success, warning, danger;

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          muted: Color.lerp(muted, other.muted, t)!,
          line: Color.lerp(line, other.line, t)!,
          raised: Color.lerp(raised, other.raised, t)!,
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          danger: Color.lerp(danger, other.danger, t)!,
        );
}

typedef TextThemeBuilder = TextTheme Function(TextTheme base);

/// Source Serif 4 for display and headlines, Inter for interface text.
TextTheme googleTypography(TextTheme base) {
  TextStyle serif(TextStyle? s, FontWeight w) =>
      GoogleFonts.sourceSerif4(textStyle: s, fontWeight: w, letterSpacing: -0.4);
  TextStyle sans(TextStyle? s) => GoogleFonts.inter(textStyle: s);
  return base.copyWith(
    displayLarge: serif(base.displayLarge, FontWeight.w400),
    displayMedium: serif(base.displayMedium, FontWeight.w400),
    displaySmall: serif(base.displaySmall, FontWeight.w400),
    headlineLarge: serif(base.headlineLarge, FontWeight.w500),
    headlineMedium: serif(base.headlineMedium, FontWeight.w500),
    headlineSmall: serif(base.headlineSmall, FontWeight.w500),
    titleLarge: sans(base.titleLarge),
    titleMedium: sans(base.titleMedium),
    titleSmall: sans(base.titleSmall),
    bodyLarge: sans(base.bodyLarge),
    bodyMedium: sans(base.bodyMedium),
    bodySmall: sans(base.bodySmall),
    labelLarge: sans(base.labelLarge),
    labelMedium: sans(base.labelMedium),
    labelSmall: sans(base.labelSmall),
  );
}

abstract final class AppTheme {
  static const _cjkFallback = ['PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC', 'Noto Sans SC', 'Source Han Sans SC'];

  static ThemeData build(Brightness brightness, TextThemeBuilder typography) {
    final dark = brightness == Brightness.dark;
    final background = dark ? Palette.night : Palette.ivory;
    final surface = dark ? Palette.charcoal : Palette.paper;
    final raised = dark ? Palette.slate : Palette.parchment;
    final text = dark ? Palette.ivory : Palette.ink;
    final muted = dark ? Palette.ash : Palette.stone;
    final line = dark ? Palette.seam : Palette.sand;
    final radius = BorderRadius.circular(12);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: Palette.clay,
      onPrimary: Colors.white,
      secondary: text,
      onSecondary: background,
      error: Palette.brick,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
      inverseSurface: text,
      onInverseSurface: background,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(brightness: brightness, colorScheme: scheme);
    final textTheme =
        typography(base.textTheme).apply(bodyColor: text, displayColor: text, fontFamilyFallback: _cjkFallback);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      extensions: [
        AppColors(
          muted: muted,
          line: line,
          raised: raised,
          success: Palette.sage,
          warning: Palette.amber,
          danger: Palette.brick,
        ),
      ],
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: line)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.clay,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: text, shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Palette.clay, width: 1.5)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.headlineSmall,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: text, borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(color: background, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: Palette.clay.withValues(alpha: 0.16),
          selectedForegroundColor: text,
          foregroundColor: muted,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: radius),
          visualDensity: VisualDensity.compact,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: Palette.clay.withValues(alpha: 0.16),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCheckmark: false,
        labelStyle: textTheme.labelLarge,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.clay : raised),
        trackOutlineColor: WidgetStatePropertyAll(line),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: text,
        contentTextStyle: TextStyle(color: background),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        iconColor: muted,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: line)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Palette.clay),
    );
  }
}
