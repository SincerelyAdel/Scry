import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Scry's colours, shared with its sibling app RepoViewer: near-black
/// with gold in dark mode, warm cream with deeper gold in light mode.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentLight,
    required this.onAccent,
    required this.button,
    required this.onButton,
    required this.success,
    required this.danger,
    required this.violet,
    required this.violetLight,
  });

  final bool isDark;

  /// Page background, cards, selected rows and outlines.
  final Color bg, surface, surfaceAlt, border;

  /// Main text, secondary text, hints.
  final Color text, muted, faint;

  /// Gold, a lighter gold for glows, and text on gold.
  final Color accent, accentLight, onAccent;

  /// Solid buttons and selected chips: a lighter gold.
  final Color button, onButton;

  final Color success, danger;

  /// The purple from the app icon, mixed into the gold glows and edges.
  final Color violet, violetLight;

  /// Gold running into the icon's purple, for edges and glows.
  LinearGradient goldViolet({
    double alpha = 1,
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) => LinearGradient(
    begin: begin,
    end: end,
    colors: [
      accentLight.withValues(alpha: alpha),
      accent.withValues(alpha: alpha),
      violet.withValues(alpha: alpha),
      violetLight.withValues(alpha: alpha),
    ],
    stops: const [0, 0.35, 0.75, 1],
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

const darkPalette = AppPalette(
  isDark: true,
  bg: Color(0xFF0D0D0D),
  surface: Color(0xFF2A2A2A),
  surfaceAlt: Color(0xFF353535),
  border: Color(0xFF3D3D3D),
  text: Color(0xFFF5F5F5),
  muted: Color(0xFF9E9E9E),
  faint: Color(0xFF6B6B6B),
  accent: Color(0xFFC9A227),
  accentLight: Color(0xFFE8CB6A),
  onAccent: Color(0xFF0D0D0D),
  button: Color(0xFFE6CA72),
  onButton: Color(0xFF1A1508),
  success: Color(0xFF5FAE72),
  danger: Color(0xFFE5675A),
  violet: Color(0xFF8A5CD6),
  violetLight: Color(0xFF9B6BDF),
);

const lightPalette = AppPalette(
  isDark: false,
  bg: Color(0xFFFAF9F5),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFF0EEE6),
  border: Color(0xFFE3E0D5),
  text: Color(0xFF1F1E1D),
  muted: Color(0xFF6E6C66),
  faint: Color(0xFFA6A39A),
  accent: Color(0xFF9C7A12),
  accentLight: Color(0xFFC9A227),
  onAccent: Color(0xFFFFFFFF),
  button: Color(0xFFDDBE5C),
  onButton: Color(0xFF1F1E1D),
  success: Color(0xFF3F7D4E),
  danger: Color(0xFFB8432F),
  violet: Color(0xFF6A3FB5),
  violetLight: Color(0xFF7B4FC9),
);

/// Serif headings (Android maps 'serif' to Noto Serif).
const kSerif = 'serif';

extension PaletteOf on BuildContext {
  /// The current [AppPalette].
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

ThemeData buildAppTheme(AppPalette c) {
  final brightness = c.isDark ? Brightness.dark : Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        primaryContainer: c.surfaceAlt,
        onPrimaryContainer: c.accent,
        secondary: c.accentLight,
        onSecondary: c.onAccent,
        tertiary: c.violet,
        onTertiary: Colors.white,
        secondaryContainer: c.surfaceAlt,
        onSecondaryContainer: c.text,
        surface: c.bg,
        onSurface: c.text,
        onSurfaceVariant: c.muted,
        surfaceContainerLowest: c.bg,
        surfaceContainerLow: c.surface,
        surfaceContainer: c.surface,
        surfaceContainerHigh: c.surface,
        surfaceContainerHighest: c.surfaceAlt,
        surfaceTint: Colors.transparent,
        error: c.danger,
        errorContainer: c.danger.withValues(alpha: 0.18),
        onErrorContainer: c.danger,
        outline: c.faint,
        outlineVariant: c.border,
      );

  RoundedRectangleBorder rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: c.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: kSerif,
        color: c.text,
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.muted),
    textTheme: TextTheme(bodyMedium: TextStyle(color: c.text)),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.border,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.button,
      height: 66,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? c.onButton : c.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? c.text : c.muted,
        ),
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: c.accent,
      textColor: c.onAccent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(20),
      titleTextStyle: TextStyle(
        fontFamily: kSerif,
        color: c.text,
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.isDark ? c.surface : c.text,
      contentTextStyle: TextStyle(color: c.isDark ? c.text : c.bg),
      actionTextColor: c.accentLight,
      behavior: SnackBarBehavior.floating,
      shape: rounded(12),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.35),
      selectionHandleColor: c.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      hintStyle: TextStyle(color: c.faint),
      labelStyle: TextStyle(color: c.muted),
      floatingLabelStyle: TextStyle(color: c.accent),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.accent),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide(color: c.accent.withValues(alpha: 0.45)),
      labelStyle: TextStyle(color: c.text, fontWeight: FontWeight.w600),
      shape: rounded(10),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.faint,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.border,
      thumbColor: c.accentLight,
      valueIndicatorColor: c.button,
      valueIndicatorTextStyle: TextStyle(color: c.onButton),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.button : c.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onButton : c.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onButton : c.muted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.button,
        foregroundColor: c.onButton,
        elevation: 0,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.button,
        foregroundColor: c.onButton,
        disabledBackgroundColor: c.surfaceAlt,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.button,
      foregroundColor: c.onButton,
      elevation: 0,
      highlightElevation: 0,
      shape: rounded(18),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.accent),
    ),
  );
}
