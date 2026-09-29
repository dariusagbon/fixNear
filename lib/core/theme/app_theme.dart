import 'package:flutter/material.dart';

/// FixNear's visual language.
///
/// - Dark ink for text and main buttons, on a grey-green background.
/// - White panels with thin borders. No shadows anywhere.
/// - Yellow ([attention]) is reserved for "this needs you now". Don't use it
///   for decoration, selection or branding.
/// - Tap targets are at least 48px, including on desktop web.
class AppTheme {
  static const Color ink = Color(0xFF1D2B2E);
  static const Color background = Color(0xFFEDF0EA);
  static const Color panel = Colors.white;

  /// Secondary text. 5.4:1 on [background], 6.2:1 on [panel].
  static const Color inkMuted = Color(0xFF56645F);

  /// Thin panel and divider borders (decorative).
  static const Color border = Color(0xFFD5DBD2);

  /// Form-field outlines; 3:1 against white, as WCAG asks for controls.
  static const Color fieldBorder = Color(0xFF8D9892);

  /// Quiet fill for chips, chat bubbles and selected states.
  static const Color tint = Color(0xFFE1E6DE);

  /// "This needs you now." Ink text on it is 8.1:1.
  static const Color attention = Color(0xFFF5B700);

  static const Color success = Color(0xFF2F6B47);
  static const Color successTint = Color(0xFFE4EFE6);
  static const Color error = Color(0xFFBA1A1A);

  static const double minTapTarget = 48;

  static ThemeData get lightTheme {
    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: border),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonSize = Size(minTapTarget, minTapTarget);
    OutlineInputBorder fieldOutline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: ink,
          brightness: Brightness.light,
        ).copyWith(
          primary: ink,
          onPrimary: Colors.white,
          primaryContainer: tint,
          onPrimaryContainer: ink,
          secondary: ink,
          onSecondary: Colors.white,
          secondaryContainer: tint,
          onSecondaryContainer: ink,
          surface: panel,
          onSurface: ink,
          onSurfaceVariant: inkMuted,
          surfaceContainerLowest: panel,
          surfaceContainerLow: panel,
          surfaceContainer: panel,
          surfaceContainerHigh: panel,
          surfaceContainerHighest: tint,
          surfaceTint: Colors.transparent,
          outline: fieldBorder,
          outlineVariant: border,
          error: error,
          shadow: Colors.transparent,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      // Desktop browsers otherwise get compact density and shrink-wrapped
      // tap targets below 48px.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      shadowColor: Colors.transparent,
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      textTheme: ThemeData.light().textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: ink,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: ink,
            ),
            bodyMedium: const TextStyle(fontSize: 14, color: inkMuted),
            bodySmall: const TextStyle(fontSize: 12, color: inkMuted),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: panelShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        elevation: 0,
        shape: panelShape,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        elevation: 0,
        shape: panelShape,
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          elevation: WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(panel),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: panel,
        elevation: 0,
        shape: panelShape,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: panel,
        elevation: 0,
        shape: panelShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: fieldOutline(fieldBorder),
        enabledBorder: fieldOutline(fieldBorder),
        disabledBorder: fieldOutline(border),
        focusedBorder: fieldOutline(ink, 2),
        errorBorder: fieldOutline(error),
        focusedErrorBorder: fieldOutline(error, 2),
        labelStyle: const TextStyle(color: inkMuted),
        floatingLabelStyle: const TextStyle(color: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: buttonShape,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: buttonSize,
          side: const BorderSide(color: fieldBorder),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: buttonSize,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: ink,
        labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        elevation: 0,
        indicatorColor: tint,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: ink)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkMuted,
        indicatorColor: ink,
        dividerColor: border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? success : tint,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(fieldBorder),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: ink,
        thumbColor: ink,
        inactiveTrackColor: tint,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        elevation: 0,
      ),
    );
  }
}
