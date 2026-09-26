import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/models/theme_family.dart';
import 'package:cerebrum/ui/themes/extensions.dart';
import 'package:cerebrum/ui/themes/tokens/tokyo_night.dart';
import 'package:flutter/material.dart';

/// The Tokyo Night theme family.
///
/// A cool, deep-blue palette. Mirrors [buildDefaultTheme] exactly; only the
/// token set changes. See `default_theme.dart` for the rationale behind each
/// component default.
ThemeData buildTokyoNightTheme({
  required Brightness brightness,
  required CerebrumColors tokens,
}) {
  final scheme = _schemeFor(brightness, tokens);
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,

    // --- Surfaces -------------------------------------------------------
    scaffoldBackgroundColor: tokens.surface.canvas,
    canvasColor: tokens.surface.canvas,
    cardColor: tokens.surface.raised,
    dividerColor: tokens.surface.outline,
    dividerTheme: DividerThemeData(
      color: tokens.surface.outline,
      space: 1,
      thickness: 1,
    ),
    splashColor: tokens.brand.primary.withValues(alpha: isDark ? 0.12 : 0.08),
    highlightColor: tokens.brand.primary.withValues(
      alpha: isDark ? 0.06 : 0.04,
    ),

    // --- Typography -----------------------------------------------------
    textTheme: _textThemeFor(tokens),
    primaryTextTheme: _textThemeFor(tokens),

    // --- Component defaults --------------------------------------------
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface.canvas,
      foregroundColor: tokens.text.strong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: tokens.surface.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.surface.outline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface.raised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface.raised,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: tokens.text.strong),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? tokens.surface.raised : tokens.brand.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: isDark ? tokens.text.strong : tokens.text.onAccent,
        fontSize: 12,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.brand.primary,
      foregroundColor: tokens.brand.onPrimary,
      elevation: 2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected)
                ? tokens.brand.onPrimary
                : tokens.surface.outlineStrong,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected)
                ? tokens.brand.primary
                : tokens.surface.sunken,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected)
                ? Colors.transparent
                : tokens.surface.outlineStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected)
                ? tokens.brand.primary
                : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(tokens.brand.onPrimary),
      side: BorderSide(color: tokens.surface.outlineStrong),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface.sunken,
      hintStyle: TextStyle(color: tokens.text.faint),
      labelStyle: TextStyle(color: tokens.text.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.surface.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.surface.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.brand.primary, width: 2),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tokens.brand.primary,
      inactiveTrackColor: tokens.surface.sunken,
      thumbColor: tokens.brand.primary,
      overlayColor: tokens.brand.primary.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.brand.primary,
      linearTrackColor: tokens.surface.sunken,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surface.sunken,
      side: BorderSide(color: tokens.surface.outline),
      labelStyle: TextStyle(color: tokens.text.body),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.text.muted,
      textColor: tokens.text.strong,
    ),
    iconTheme: IconThemeData(color: tokens.text.body),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? tokens.surface.raised : tokens.brand.ink,
      contentTextStyle: TextStyle(
        color: isDark ? tokens.text.strong : tokens.text.onAccent,
      ),
      actionTextColor: tokens.brand.accent,
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.brand.primary,
      unselectedLabelColor: tokens.text.muted,
      indicatorColor: tokens.brand.primary,
      dividerColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface.raised,
      indicatorColor: tokens.brand.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: tokens.text.muted),
      ),
    ),
    // Register the tokens last so `context.cerebrum` resolves everywhere below.
    extensions: [tokens],
  );
}

/// The Material [ColorScheme], derived from tokens rather than hand-picked.
ColorScheme _schemeFor(Brightness brightness, CerebrumColors t) {
  return ColorScheme(
    brightness: brightness,
    primary: t.brand.primary,
    onPrimary: t.brand.onPrimary,
    primaryContainer: t.brand.primaryWash.withValues(alpha: 0.16),
    onPrimaryContainer: t.brand.ink,
    secondary: t.brand.accent,
    onSecondary: t.text.onAccent,
    secondaryContainer: t.brand.accent.withValues(alpha: 0.16),
    onSecondaryContainer: t.brand.accentDeep,
    tertiary: t.gantt.current,
    onTertiary: t.gantt.onTask,
    error: t.status.danger,
    onError: t.brand.onPrimary,
    errorContainer: t.status.dangerSurface,
    onErrorContainer: t.status.dangerDeep,
    surface: t.surface.canvas,
    onSurface: t.text.strong,
    surfaceContainerLowest: t.surface.canvas,
    surfaceContainerLow: t.surface.sunken,
    surfaceContainer: t.surface.sunken,
    surfaceContainerHigh: t.surface.raised,
    surfaceContainerHighest: t.surface.raised,
    onSurfaceVariant: t.text.muted,
    outline: t.surface.outlineStrong,
    outlineVariant: t.surface.outline,
    shadow: t.shadow.strong,
    scrim: t.shadow.scrim,
    inverseSurface: t.brand.ink,
    onInverseSurface: t.text.onAccent,
    inversePrimary: t.brand.accent,
  );
}

TextTheme _textThemeFor(CerebrumColors t) {
  TextStyle s(double size, FontWeight w, Color c, {double? h}) =>
      TextStyle(fontSize: size, fontWeight: w, color: c, height: h);

  return TextTheme(
    displayLarge: s(40, FontWeight.w700, t.text.strong),
    displayMedium: s(32, FontWeight.w700, t.text.strong),
    displaySmall: s(28, FontWeight.w600, t.text.strong),
    headlineLarge: s(26, FontWeight.w700, t.text.strong),
    headlineMedium: s(22, FontWeight.w600, t.text.strong),
    headlineSmall: s(20, FontWeight.w600, t.text.strong),
    titleLarge: s(18, FontWeight.w600, t.text.strong),
    titleMedium: s(15, FontWeight.w600, t.text.strong),
    titleSmall: s(13, FontWeight.w600, t.text.strong),
    bodyLarge: s(15, FontWeight.w400, t.text.strong, h: 1.4),
    bodyMedium: s(13, FontWeight.w400, t.text.body, h: 1.4),
    bodySmall: s(12, FontWeight.w400, t.text.muted, h: 1.35),
    labelLarge: s(14, FontWeight.w600, t.text.strong),
    labelMedium: s(12, FontWeight.w500, t.text.muted),
    labelSmall: s(10, FontWeight.w500, t.text.faint),
  );
}

/// Tokyo Night is a single dark palette; both slots point at the same tokens
/// so the family is selectable regardless of the active [Brightness].
final tokyoNightTheme = buildTokyoNightTheme(
  brightness: Brightness.dark,
  tokens: tokyoNightTokens,
);

final tokyoNightThemeFamily = ThemeFamily(
  id: 'tokyo_night',
  label: 'Tokyo Night',
  light: tokyoNightTheme,
  dark: tokyoNightTheme,
);
