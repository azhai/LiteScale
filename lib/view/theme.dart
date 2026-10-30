import 'package:flutter/material.dart';

/// Lake-green brand palette (湖绿) used across the app.
class Brand {
  const Brand._();

  /// Primary lake green.
  static const Color lake = Color(0xFF0E7C6B);

  /// Darker lake green used for text/icon on light surfaces.
  static const Color deep = Color(0xFF0B6E5F);

  /// Pale lake green used for containers.
  static const Color mist = Color(0xFFBCF0E2);

  /// Warm accent — goal line, secondary chart line.
  static const Color amber = Color(0xFF9A6B12);
}

/// Layout rhythm. Everything is a multiple of 2 so the UI stays on a grid.
class Insets {
  const Insets._();
  static const double page = 20;
  static const double card = 18;
  static const double gap = 14;
  static const double section = 22;
}

class Radii {
  const Radii._();
  static const double card = 22;
  static const double field = 14;
  static const double small = 12;
}

ColorScheme _scheme(Brightness brightness) {
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: Brand.lake,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  if (brightness == Brightness.light) {
    return base.copyWith(
      primary: Brand.deep,
      onPrimary: Colors.white,
      primaryContainer: Brand.mist,
      onPrimaryContainer: const Color(0xFF00251F),
      secondary: const Color(0xFF3A695E),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFD3EEE6),
      onSecondaryContainer: const Color(0xFF07201B),
      tertiary: Brand.amber,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF8E3B4),
      onTertiaryContainer: const Color(0xFF241A00),
      surface: const Color(0xFFF6FAF8),
      onSurface: const Color(0xFF0F1D1A),
      onSurfaceVariant: const Color(0xFF4B605A),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF1F8F5),
      surfaceContainer: const Color(0xFFEAF3F0),
      surfaceContainerHigh: const Color(0xFFE3EFEB),
      surfaceContainerHighest: const Color(0xFFDCEAE5),
      outline: const Color(0xFF768A85),
      outlineVariant: const Color(0xFFC9DBD5),
      inverseSurface: const Color(0xFF23332F),
      onInverseSurface: const Color(0xFFE9F6F2),
      inversePrimary: const Color(0xFF7BD9C3),
    );
  }

  return base.copyWith(
    primary: const Color(0xFF7BD9C3),
    onPrimary: const Color(0xFF00382F),
    primaryContainer: const Color(0xFF005144),
    onPrimaryContainer: const Color(0xFF9BF6E0),
    secondary: const Color(0xFFA9CCC2),
    onSecondary: const Color(0xFF0C322B),
    secondaryContainer: const Color(0xFF2C4A43),
    onSecondaryContainer: const Color(0xFFC5E9DF),
    tertiary: const Color(0xFFE6C173),
    onTertiary: const Color(0xFF3A2B00),
    tertiaryContainer: const Color(0xFF5C4400),
    onTertiaryContainer: const Color(0xFFFFE9AE),
    surface: const Color(0xFF0B1512),
    onSurface: const Color(0xFFE3EFEA),
    onSurfaceVariant: const Color(0xFFB7CBC5),
    surfaceContainerLowest: const Color(0xFF080F0D),
    surfaceContainerLow: const Color(0xFF0F1B18),
    surfaceContainer: const Color(0xFF13211D),
    surfaceContainerHigh: const Color(0xFF1A2A25),
    surfaceContainerHighest: const Color(0xFF22332E),
    outline: const Color(0xFF819690),
    outlineVariant: const Color(0xFF33443F),
    inverseSurface: const Color(0xFFE3EFEA),
    onInverseSurface: const Color(0xFF10201C),
    inversePrimary: Brand.deep,
  );
}

/// [fontFamily] / [fontFamilyFallback] let tests and previews swap in a real
/// font; production passes nothing and uses the platform default.
ThemeData buildAppTheme(
  Brightness brightness, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final ColorScheme cs = _scheme(brightness);
  final ThemeData base = ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    brightness: brightness,
  );
  final TextTheme baseText = base.textTheme.apply(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );
  final TextTheme tt = baseText;
  final bool light = brightness == Brightness.light;

  final Color cardColor = light ? Colors.white : cs.surfaceContainerLow;
  final Color borderColor =
      cs.outlineVariant.withValues(alpha: light ? 0.55 : 0.35);
  final BorderSide cardSide = BorderSide(color: borderColor);

  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    textTheme: tt.copyWith(
      displayMedium: tt.displayMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -2,
      ),
      displaySmall: tt.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
      ),
      headlineSmall: tt.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleLarge: tt.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: Insets.page,
      titleTextStyle: tt.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        color: cs.onSurface,
      ),
      toolbarTextStyle: tt.bodyMedium,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: cardSide,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: borderColor,
      thickness: 0.8,
      space: 0.8,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: borderColor),
        textStyle: tt.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: tt.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(tt.labelMedium),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: borderColor),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.selected)) return cs.primaryContainer;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.selected)) return cs.onPrimaryContainer;
          return cs.onSurfaceVariant;
        }),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? cs.surfaceContainerLow : cs.surfaceContainerHigh,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(color: cs.primary, width: 1.4),
      ),
      labelStyle: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      hintStyle: tt.bodySmall?.copyWith(
        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      suffixStyle: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide.none,
      labelStyle: tt.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) {
          final bool sel = states.contains(WidgetState.selected);
          return tt.labelSmall?.copyWith(
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? cs.onSurface : cs.onSurfaceVariant,
          );
        },
      ),
      iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        final bool sel = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: tt.bodyMedium?.copyWith(color: cs.onInverseSurface),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small + 4),
      ),
      textStyle: tt.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: cs.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
