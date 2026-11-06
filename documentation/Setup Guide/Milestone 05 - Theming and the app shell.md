---
title: "Milestone 5: Theming and the app shell"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 5
aliases:
  - Milestone 5
updated: 2026-11-06
---
# Milestone 5: Theming and the app shell

This milestone gives the app its look and its five tabs: Library, Updates, Browse, History and More, each still an empty page. Theme and shell are shared code, so everything here lives outside `features/`: `lib/src/theme/`, `lib/src/routing/`, `lib/src/constants/` and `lib/src/common_widgets/`. The theme settings are preferences from [[Milestone 04 - Preferences and the local database|milestone 4]], so a chosen theme is saved from the start.

**Themes** (`lib/src/theme/`):

1. `palettes.dart`: hand-write Catppuccin Mocha (dark), Latte (light) and a grayscale E-ink scheme as `const ColorScheme`s. Add a `NoctuaColors` theme extension for colors M3 has no role for (success, warning), and a `BuildContext` extension so screens can write `context.colors`, `context.text` and `context.isEink`.
2. `mihon_schemes.dart`: Mihon's 13 built-in themes (Default, Green Apple, Lavender, Midnight Dusk, Nord, Strawberry Daiquiri, Tako, Teal & Turquoise, Tidal Wave, Yin & Yang, Yotsuba, Tokyo Night, Monochrome) as `MihonTheme(id, label, dark, light)`. Port the color values from Mihon’s Kotlin sources and keep its Apache-2.0 licence next to the file.
3. `app_theme.dart`: `buildTheme(scheme)` wraps `FlexThemeData` with Inter text and the extensions; E-ink also turns off ripples and page transitions. The generated `appThemesProvider` watches only the theme preferences (added to [[Milestone 04 - Preferences and the local database|milestone 4]]’s registry) and returns the light/dark pair plus the `ThemeMode`.
4. Dynamic colour: in `main()`, call `DynamicColorPlugin.getCorePalette()` (dynamic\_color). On Android 12+ it returns the five tonal palettes the system derived from the wallpaper; turn them into a light and dark scheme with `schemesFromPalettes`. Override `dynamicSchemesProvider` with them; on Android 11 and older it returns null, the provider stays null and the Dynamic card is hidden. `ThemeMode.system` already follows the system’s light or dark setting.

```dart
// main.dart
(ColorScheme, ColorScheme)? dynamicSchemes;
try {
  final p = await DynamicColorPlugin.getCorePalette(); // null before Android 12
  if (p != null) {
    dynamicSchemes = schemesFromPalettes(
      primary: p.primary,
      secondary: p.secondary,
      tertiary: p.tertiary,
      neutral: p.neutral,
      neutralVariant: p.neutralVariant,
    );
  }
} on Object {
  dynamicSchemes = null;
}

// lib/src/theme/app_theme.dart
@Riverpod(keepAlive: true)
(ColorScheme, ColorScheme)? dynamicSchemes(Ref ref) => null; // overridden in main()

@Riverpod(keepAlive: true)
AppThemes appThemes(Ref ref) {
  final theme = ref.pref(Prefs.appTheme);
  final mode = switch (ref.pref(Prefs.darkMode)) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  if (theme == 'eink') {
    final t = buildTheme(einkScheme, eink: true);
    return AppThemes(t, t, ThemeMode.light);
  }
  final (light, dark) = builtInSchemes(theme, ref.watch(dynamicSchemesProvider));
  final black = ref.pref(Prefs.pureBlack);
  return AppThemes(buildTheme(light), buildTheme(black ? pureBlackOf(dark) : dark), mode);
}
```

**Router and shell** (`lib/src/routing/` and `lib/src/app.dart`):

1. `routing/app_router.dart`: an `@AutoRouterConfig(replaceInRouteName: 'Page,Route')` class. `HomeShellRoute` is the initial route, with the five tab pages as its children; every other page is a top-level route pushed over the shell.
2. Each page class is annotated `@RoutePage()` and lives in its feature’s `presentation/` folder. The router is the one place that knows about every feature.
3. `routing/home_shell_page.dart`: an `AutoTabsRouter` with a `NavigationBar`. When `context.useNavigationRail` is true (the expanded breakpoint, 840 dp and up) it switches to a `NavigationRail` ([[Milestone 13 - Errors, tablets and e-ink|milestone 13]] builds on this).
4. `app.dart`: `NoctuaApp` builds `MaterialApp.router` from `appThemesProvider` and the router config, and wraps every route in responsive\_framework’s `ResponsiveBreakpoints.builder` with Material 3’s window sizes from `constants/breakpoints.dart`: COMPACT 0–599, MEDIUM 600–839, EXPANDED 840–1199, LARGE 1200+. Screens never compare raw widths; they ask `context.useNavigationRail` or `context.useTwoPanes`. Keep `main.dart` to bootstrapping only.

**Move the updater into place:** annotate `AppUpdatePage` and `ChangelogPage` with `@RoutePage()`, register them, and wrap the `AutoTabsRouter` in `AppUpdateListener` so the launch check runs from the shell. Replace `Theme.of(context)` with the new shortcuts in those widgets, and delete [[Milestone 03 - In-app updates|milestone 3]]’s temporary home page.

## Code walkthrough: milestone 5

**Step 1: hand-written schemes.** `lib/src/theme/palettes.dart` maps Catppuccin onto Material 3's color roles. Every role is spelled out (no `fromSeed`), because Catppuccin's exact hex values are the point. The Mocha scheme:

```dart
/// Catppuccin Mocha mapped onto Material 3 color roles (Mauve accent).
/// Catppuccin's mantle/crust are darker than base, so the M3 surface
/// containers step lighter from base instead, to keep elevation readable.
const mochaScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFCBA6F7),
  onPrimary: Color(0xFF11111B),
  primaryContainer: Color(0xFF45345F),
  onPrimaryContainer: Color(0xFFE9DCFC),
  secondary: Color(0xFFB4BEFE),
  onSecondary: Color(0xFF11111B),
  secondaryContainer: Color(0xFF3A3F66),
  onSecondaryContainer: Color(0xFFDDE1FF),
  tertiary: Color(0xFFFAB387),
  onTertiary: Color(0xFF11111B),
  tertiaryContainer: Color(0xFF5A3D2A),
  onTertiaryContainer: Color(0xFFFFDCC6),
  error: Color(0xFFF38BA8),
  onError: Color(0xFF11111B),
  errorContainer: Color(0xFF5C2A3A),
  onErrorContainer: Color(0xFFFFD9E1),
  surface: Color(0xFF1E1E2E),
  onSurface: Color(0xFFCDD6F4),
  onSurfaceVariant: Color(0xFFA6ADC8),
  surfaceDim: Color(0xFF181825),
  surfaceBright: Color(0xFF3C3E52),
  surfaceContainerLowest: Color(0xFF181825),
  surfaceContainerLow: Color(0xFF232336),
  surfaceContainer: Color(0xFF28283D),
  surfaceContainerHigh: Color(0xFF313244),
  surfaceContainerHighest: Color(0xFF3C3E52),
  outline: Color(0xFF6C7086),
  outlineVariant: Color(0xFF45475A),
  inverseSurface: Color(0xFFCDD6F4),
  onInverseSurface: Color(0xFF1E1E2E),
  inversePrimary: Color(0xFF8839EF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFFCBA6F7),
);
```

The comment explains the one deliberate departure: Catppuccin's "mantle" and "crust" are darker than its base, but M3 expects containers to get lighter as they rise, so `surfaceContainerLow` to `Highest` step up from base instead. Write `latteScheme` the same way, and `einkScheme` with only black, white and grays (`surfaceTint: Colors.transparent` removes M3's colored elevation overlay).

Then the pieces the color scheme has no room for:

```dart
/// Semantic extras not in ColorScheme.
class NoctuaColors extends ThemeExtension<NoctuaColors> {
  const NoctuaColors({required this.success, required this.warning, required this.coverText});

  final Color success;
  final Color warning;
  final Color coverText;

  static const mocha = NoctuaColors(success: Color(0xFFA6E3A1), warning: Color(0xFFFAB387), coverText: Color(0xFFCDD6F4));
  static const latte = NoctuaColors(success: Color(0xFF40A02B), warning: Color(0xFFFE640B), coverText: Color(0xFFEFF1F5));
  static const eink = NoctuaColors(success: Color(0xFF000000), warning: Color(0xFF000000), coverText: Color(0xFF000000));

  @override
  NoctuaColors copyWith({Color? success, Color? warning, Color? coverText}) =>
      NoctuaColors(success: success ?? this.success, warning: warning ?? this.warning, coverText: coverText ?? this.coverText);

  @override
  NoctuaColors lerp(NoctuaColors? other, double t) {
    if (other == null) return this;
    return NoctuaColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      coverText: Color.lerp(coverText, other.coverText, t)!,
    );
  }
}

extension NoctuaThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  NoctuaColors get noctua => Theme.of(this).extension<NoctuaColors>() ?? NoctuaColors.mocha;
  bool get isEink => Theme.of(this).extension<EinkMarker>() != null;
}

/// Present only in the E-ink theme, so widgets can drop covers, shadows and motion.
class EinkMarker extends ThemeExtension<EinkMarker> {
  const EinkMarker();
  @override
  EinkMarker copyWith() => this;
  @override
  EinkMarker lerp(EinkMarker? other, double t) => this;
}
```

- `NoctuaColors` is a `ThemeExtension`: extra colors that travel with the theme and animate between themes through `lerp`.
- `EinkMarker` carries no data. Its presence in a theme is the signal, so any widget can ask `context.isEink` and drop shadows, covers or motion.
- `NoctuaThemeX` is the shortcut every screen uses: `context.colors.primary` instead of `Theme.of(context).colorScheme.primary`.

**Step 2: Mihon's themes.** `lib/src/theme/mihon_schemes.dart` holds 13 pairs of `ColorScheme`s ported from Mihon's Kotlin sources. Each Kotlin `darkColorScheme(primary = Color(0xFF…), …)` becomes a `const ColorScheme(brightness: Brightness.dark, primary: Color(0xFF…), …)`, role for role. One theme and the list:

```dart
// GENERATED from Mihon’s theme sources (Apache-2.0, https://github.com/mihonapp/mihon; see MIHON_LICENSE).
// Original schemes and credits: app/src/main/java/eu/kanade/presentation/theme/colorscheme/*.kt
// background/onBackground/surfaceVariant are folded into surface or dropped: Flutter’s ColorScheme no longer uses them.
// Roles a Mihon scheme leaves out fall back to the Material 3 baseline, as Compose does.
import 'package:flutter/material.dart';

class MihonTheme {
  const MihonTheme(this.id, this.label, this.dark, this.light);
  final String id;
  final String label;
  final ColorScheme dark;
  final ColorScheme light;
}

const _tachiyomiDark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFB0C6FF),
  onPrimary: Color(0xFF002D6E),
  primaryContainer: Color(0xFF00429B),
  onPrimaryContainer: Color(0xFFD9E2FF),
  inversePrimary: Color(0xFF0058CA),
  secondary: Color(0xFFB0C6FF),
  onSecondary: Color(0xFF002D6E),
  secondaryContainer: Color(0xFF00429B),
  onSecondaryContainer: Color(0xFFD9E2FF),
  tertiary: Color(0xFF7ADC77),
  onTertiary: Color(0xFF003909),
  tertiaryContainer: Color(0xFF005312),
  onTertiaryContainer: Color(0xFF95F990),
  surface: Color(0xFF1B1B1F),
  onSurface: Color(0xFFE3E2E6),
  onSurfaceVariant: Color(0xFFC5C6D0),
  surfaceTint: Color(0xFFB0C6FF),
  inverseSurface: Color(0xFFE3E2E6),
  onInverseSurface: Color(0xFF1B1B1F),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  outline: Color(0xFF8F9099),
  outlineVariant: Color(0xFF44464F),
  surfaceContainerLowest: Color(0xFF1A181D),
  surfaceContainerLow: Color(0xFF1E1C22),
  surfaceContainer: Color(0xFF211F26),
  surfaceContainerHigh: Color(0xFF292730),
  surfaceContainerHighest: Color(0xFF302E38),
);
```

```dart
/// Every Mihon theme except Dynamic (read from the system with dynamic_color) and Catppuccin (Noctua’s own default).
const mihonThemes = <MihonTheme>[
  MihonTheme('tachiyomi', 'Default', _tachiyomiDark, _tachiyomiLight),
  MihonTheme('greenApple', 'Green Apple', _greenAppleDark, _greenAppleLight),
  MihonTheme('lavender', 'Lavender', _lavenderDark, _lavenderLight),
  MihonTheme('midnightDusk', 'Midnight Dusk', _midnightDuskDark, _midnightDuskLight),
  MihonTheme('nord', 'Nord', _nordDark, _nordLight),
  MihonTheme('strawberry', 'Strawberry Daiquiri', _strawberryDark, _strawberryLight),
  MihonTheme('tako', 'Tako', _takoDark, _takoLight),
  MihonTheme('tealTurquoise', 'Teal & Turquoise', _tealTurquoiseDark, _tealTurquoiseLight),
  MihonTheme('tidalWave', 'Tidal Wave', _tidalWaveDark, _tidalWaveLight),
  MihonTheme('yinYang', 'Yin & Yang', _yinYangDark, _yinYangLight),
  MihonTheme('yotsuba', 'Yotsuba', _yotsubaDark, _yotsubaLight),
  MihonTheme('tokyoNight', 'Tokyo Night', _tokyoNightDark, _tokyoNightLight),
  MihonTheme('monochrome', 'Monochrome', _monochromeDark, _monochromeLight),
];
```

Mihon's sources also set `background`, `onBackground` and `surfaceVariant`; Flutter deprecated those roles, so they are folded into `surface` or dropped. Keep Mihon's Apache-2.0 licence in `lib/src/theme/MIHON_LICENSE`.

**Step 3: building `ThemeData`.** flex_color_scheme turns a `ColorScheme` into a fully styled `ThemeData` (inputs, chips, cards, navigation bar) so no screen styles components by hand:

```dart
/// Shared component tuning: M3 defaults, with a few shapes matched to the mockup.
FlexSubThemesData _subThemes({required bool eink}) => FlexSubThemesData(
  interactionEffects: !eink,
  blendOnColors: false,
  inputDecoratorBorderType: FlexInputBorderType.outline,
  inputDecoratorRadius: 4,
  chipRadius: 8,
  cardRadius: 12,
  bottomSheetRadius: 28,
  navigationBarIndicatorSchemeColor: SchemeColor.secondaryContainer,
  navigationBarBackgroundSchemeColor: SchemeColor.surfaceContainer,
  thinBorderWidth: eink ? 1.5 : 1,
);
```

```dart
ThemeData buildTheme(ColorScheme scheme, {bool eink = false, NoctuaColors? extras}) {
  final dark = scheme.brightness == Brightness.dark;
  final base = dark
      ? FlexThemeData.dark(
          colorScheme: scheme,
          useMaterial3: true,
          blendLevel: 0,
          subThemesData: _subThemes(eink: eink),
        )
      : FlexThemeData.light(
          colorScheme: scheme,
          useMaterial3: true,
          blendLevel: 0,
          subThemesData: _subThemes(eink: eink),
        );

  var theme = base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
    extensions: [extras ?? (dark ? NoctuaColors.mocha : NoctuaColors.latte), if (eink) const EinkMarker()],
  );

  if (eink) {
    // Every animation costs a ghosting refresh on e-paper: no ripples, no page transitions.
    theme = theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: _NoTransitionBuilder(), TargetPlatform.linux: _NoTransitionBuilder()},
      ),
    );
  }
  return theme;
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
```

- `blendLevel: 0` stops flex_color_scheme from tinting surfaces with the primary color, which would change Catppuccin's exact surfaces.
- `interactionEffects: !eink` and `NoSplash.splashFactory` remove ripples on e-ink, where each animation frame costs a visible refresh.
- `_NoTransitionBuilder` returns the new page as-is, so e-ink navigation is an instant swap.
- `GoogleFonts.interTextTheme` swaps every text style to Inter while keeping M3's sizes and weights.

**Step 4: the theme providers.** `appThemesProvider` is the only thing `MaterialApp` watches. It recomputes when one of the theme preferences it reads changes, and only then:

```dart
class AppThemes {
  const AppThemes(this.light, this.dark, this.mode);
  final ThemeData light;
  final ThemeData dark;
  final ThemeMode mode;
}

/// Material You schemes from the system's dynamic colours (dynamic_color),
/// read once in main(). Null on Android 11 and older and on platforms without
/// dynamic colour, and then the Dynamic theme isn't offered.
@Riverpod(keepAlive: true)
(ColorScheme, ColorScheme)? dynamicSchemes(Ref ref) => null;

/// Light and dark schemes from the system's Material You palettes (the five
/// tonal palettes Android 12+ derives from the wallpaper).
///
/// Every role, the newer surface containers and fixed colours included, is
/// resolved with Material's own tone rules (`DynamicScheme`), so nothing is
/// guessed from a single seed colour. dynamic_color's `toColorScheme()` isn't
/// used: in dynamic_color 2.x it returns material_ui's `ColorScheme`, a
/// different type from Flutter's.
(ColorScheme, ColorScheme) schemesFromPalettes({
  required mcu.TonalPalette primary,
  required mcu.TonalPalette secondary,
  required mcu.TonalPalette tertiary,
  required mcu.TonalPalette neutral,
  required mcu.TonalPalette neutralVariant,
}) {
  ColorScheme make(bool dark) {
    final s = mcu.DynamicScheme(
      sourceColorHct: primary.keyColor,
      variant: mcu.Variant.tonalSpot,
      isDark: dark,
      primaryPalette: primary,
      secondaryPalette: secondary,
      tertiaryPalette: tertiary,
      neutralPalette: neutral,
      neutralVariantPalette: neutralVariant,
    );
    return ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: Color(s.primary),
      onPrimary: Color(s.onPrimary),
      primaryContainer: Color(s.primaryContainer),
      onPrimaryContainer: Color(s.onPrimaryContainer),
      primaryFixed: Color(s.primaryFixed),
      primaryFixedDim: Color(s.primaryFixedDim),
      onPrimaryFixed: Color(s.onPrimaryFixed),
      onPrimaryFixedVariant: Color(s.onPrimaryFixedVariant),
      secondary: Color(s.secondary),
      onSecondary: Color(s.onSecondary),
      secondaryContainer: Color(s.secondaryContainer),
      onSecondaryContainer: Color(s.onSecondaryContainer),
      secondaryFixed: Color(s.secondaryFixed),
      secondaryFixedDim: Color(s.secondaryFixedDim),
      onSecondaryFixed: Color(s.onSecondaryFixed),
      onSecondaryFixedVariant: Color(s.onSecondaryFixedVariant),
      tertiary: Color(s.tertiary),
      onTertiary: Color(s.onTertiary),
      tertiaryContainer: Color(s.tertiaryContainer),
      onTertiaryContainer: Color(s.onTertiaryContainer),
      tertiaryFixed: Color(s.tertiaryFixed),
      tertiaryFixedDim: Color(s.tertiaryFixedDim),
      onTertiaryFixed: Color(s.onTertiaryFixed),
      onTertiaryFixedVariant: Color(s.onTertiaryFixedVariant),
      error: Color(s.error),
      onError: Color(s.onError),
      errorContainer: Color(s.errorContainer),
      onErrorContainer: Color(s.onErrorContainer),
      surface: Color(s.surface),
      onSurface: Color(s.onSurface),
      surfaceDim: Color(s.surfaceDim),
      surfaceBright: Color(s.surfaceBright),
      surfaceContainerLowest: Color(s.surfaceContainerLowest),
      surfaceContainerLow: Color(s.surfaceContainerLow),
      surfaceContainer: Color(s.surfaceContainer),
      surfaceContainerHigh: Color(s.surfaceContainerHigh),
      surfaceContainerHighest: Color(s.surfaceContainerHighest),
      onSurfaceVariant: Color(s.onSurfaceVariant),
      outline: Color(s.outline),
      outlineVariant: Color(s.outlineVariant),
      shadow: Color(s.shadow),
      scrim: Color(s.scrim),
      inverseSurface: Color(s.inverseSurface),
      onInverseSurface: Color(s.inverseOnSurface),
      inversePrimary: Color(s.inversePrimary),
      surfaceTint: Color(s.surfaceTint),
    );
  }

  return (make(false), make(true));
}

/// Mihon's "pure black dark mode": black background, near-black containers so
/// content scrolling under the navigation bar stays visible.
ColorScheme pureBlackOf(ColorScheme dark) => dark.copyWith(
  surface: Colors.black,
  onSurface: Colors.white,
  surfaceDim: Colors.black,
  surfaceContainerLowest: const Color(0xFF0C0C0C),
  surfaceContainerLow: const Color(0xFF0C0C0C),
  surfaceContainer: const Color(0xFF0C0C0C),
  surfaceContainerHigh: const Color(0xFF131313),
  surfaceContainerHighest: const Color(0xFF1B1B1B),
);

/// Light and dark schemes for every built-in theme id except custom and E-ink.
(ColorScheme light, ColorScheme dark) builtInSchemes(String id, (ColorScheme, ColorScheme)? dynamic) {
  if (id == 'dynamic' && dynamic != null) return dynamic;
  for (final t in mihonThemes) {
    if (t.id == id) return (t.light, t.dark);
  }
  return (latteScheme, mochaScheme);
}

/// Builds the light/dark ThemeData pair from preferences. Rebuilt only when a
/// theme-related preference changes.
@Riverpod(keepAlive: true)
AppThemes appThemes(Ref ref) {
  final theme = ref.pref(Prefs.appTheme);
  final dark = ref.pref(Prefs.darkMode);
  final mode = switch (dark) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  final pureBlack = ref.pref(Prefs.pureBlack);

  switch (theme) {
    case 'eink':
      final t = buildTheme(einkScheme, eink: true, extras: NoctuaColors.eink);
      return AppThemes(t, t, ThemeMode.light);
    case 'custom':
      final primary = Color(ref.pref(Prefs.customPrimary));
      final s2 = ref.pref(Prefs.customSecondary), s3 = ref.pref(Prefs.customTertiary);
      final variant = ref.pref(Prefs.customVariant);
      final contrast = ref.pref(Prefs.customContrast);
      ColorScheme make(Brightness b, String rolesJson) => applyRoles(
        schemeFromSeeds(
          brightness: b,
          primary: primary,
          secondary: s2 == 0 ? null : Color(s2),
          tertiary: s3 == 0 ? null : Color(s3),
          variant: variant,
          contrast: contrast,
        ),
        decodeRoles(rolesJson),
      );
      return AppThemes(
        buildTheme(make(Brightness.light, ref.pref(Prefs.customRolesLight)), extras: NoctuaColors.latte),
        buildTheme(
          pureBlack
              ? pureBlackOf(make(Brightness.dark, ref.pref(Prefs.customRolesDark)))
              : make(Brightness.dark, ref.pref(Prefs.customRolesDark)),
          extras: NoctuaColors.mocha,
        ),
        mode,
      );
    default:
      final (light, dark) = builtInSchemes(theme, ref.watch(dynamicSchemesProvider));
      return AppThemes(
        buildTheme(light, extras: NoctuaColors.latte),
        buildTheme(pureBlack ? pureBlackOf(dark) : dark, extras: NoctuaColors.mocha),
        mode,
      );
  }
}
```

- `ref.pref(Prefs.appTheme)` is [[Milestone 04 - Preferences and the local database|milestone 4]]'s `PrefRef` extension. It uses `select`, so changing an unrelated setting (grid columns, say) doesn't rebuild the theme.
- `dynamicSchemes` returns a Dart record `(light, dark)`, or null. Records give two return values without a wrapper class.
- `schemesFromPalettes` builds a Material `DynamicScheme` from the system's palettes and copies every role into Flutter's `ColorScheme`, surface containers and fixed colours included. It uses `material_color_utilities` under an `mcu.` prefix, because flex_color_scheme exports classes with the same names. dynamic_color's own `toColorScheme()` isn't used: in dynamic_color 2.x it returns the separate `material_ui` package's `ColorScheme`, which isn't the type Flutter's `ThemeData` takes.
- `builtInSchemes` falls back to Catppuccin when the id is unknown, so a preference saved by a newer version can't leave the app unthemed.
- `pureBlackOf` keeps containers a few shades above black, so a card or the navigation bar stays visible against the background.
- The `custom` case belongs to [[Milestone 10 - Settings|milestone 10]]'s theme editor; leave it out for now.

Add the theme keys to the `Prefs` registry from [[Milestone 04 - Preferences and the local database|milestone 4]] (`appTheme`, `darkMode`, `pureBlack`); the providers read them through `ref.pref`, so a theme change is saved and survives a restart with no extra code.

**Step 5: Material You colours in `main()`.** dynamic_color reads the palettes Android 12+ derives from the wallpaper. It returns null on older Android and other platforms, which is how the app knows to hide the Dynamic card:

```dart
(ColorScheme, ColorScheme)? dynamicSchemes;
try {
  final p = await DynamicColorPlugin.getCorePalette();
  if (p != null) {
    dynamicSchemes = schemesFromPalettes(
      primary: p.primary,
      secondary: p.secondary,
      tertiary: p.tertiary,
      neutral: p.neutral,
      neutralVariant: p.neutralVariant,
    );
  }
} on Object {
  dynamicSchemes = null; // no plugin (tests, desktop): no Dynamic theme
}
// …then in ProviderScope(overrides: [...]):
dynamicSchemesProvider.overrideWithValue(dynamicSchemes),
```

Import the plugin with `show DynamicColorPlugin`, so its other exports don't clash with Flutter's Material types. `getCorePalette` is read once at startup, so after the user changes wallpaper the new colours apply the next time the app starts.

**Step 6: breakpoints.** Window size classes from the Material 3 guidelines, named once:

```dart
import 'package:flutter/widgets.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// Material 3 window size classes, as responsive_framework breakpoints.
/// NoctuaApp installs them with [ResponsiveBreakpoints.builder].
abstract final class WindowSize {
  static const compact = 'COMPACT'; // phones in portrait
  static const medium = 'MEDIUM'; // small tablets, foldables, phones in landscape
  static const expanded = 'EXPANDED'; // tablets in portrait, big foldables
  static const large = 'LARGE'; // tablets in landscape, desktops

  static const breakpoints = [
    Breakpoint(start: 0, end: 599, name: compact),
    Breakpoint(start: 600, end: 839, name: medium),
    Breakpoint(start: 840, end: 1199, name: expanded),
    Breakpoint(start: 1200, end: double.infinity, name: large),
  ];
}

extension WindowSizeX on BuildContext {
  ResponsiveBreakpointsData get _bp => ResponsiveBreakpoints.of(this);

  /// Navigation rail instead of the bottom bar.
  bool get useNavigationRail => _bp.largerOrEqualTo(WindowSize.expanded);

  /// Library and work details side by side.
  bool get useTwoPanes => _bp.largerOrEqualTo(WindowSize.large);
}
```

`ResponsiveBreakpoints.of(context)` reads the active breakpoint from an `InheritedWidget`, so a widget using `context.useNavigationRail` rebuilds when the window crosses 840 dp (rotating a tablet, unfolding a foldable) and not on every pixel of a resize.

**Step 7: the router.** auto_route generates a `*Route` class for every page annotated `@RoutePage()`. `replaceInRouteName: 'Page,Route'` turns `LibraryPage` into `LibraryRoute`. The finished router, which grows milestone by milestone:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:noctua/src/routing/app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    // Auth (the start route is chosen in main.dart from the saved session)
    AutoRoute(page: WelcomeRoute.page),
    AutoRoute(page: SignInRoute.page),
    AutoRoute(page: RegisterRoute.page),
    AutoRoute(page: ForgotPasswordRoute.page),
    AutoRoute(page: AccountRoute.page),

    // First run
    AutoRoute(page: SetupRoute.page),
    AutoRoute(page: TourRoute.page),

    AutoRoute(
      page: HomeShellRoute.page,
      initial: true,
      children: [
        AutoRoute(page: LibraryRoute.page, initial: true),
        AutoRoute(page: UpdatesRoute.page),
        AutoRoute(page: BrowseRoute.page),
        AutoRoute(page: HistoryRoute.page),
        AutoRoute(page: MoreRoute.page),
      ],
    ),
    AutoRoute(page: WorkDetailsRoute.page),
    AutoRoute(page: ReaderRoute.page),
    AutoRoute(page: OpenWorksRoute.page),
    AutoRoute(page: SeriesRoute.page),
    AutoRoute(page: AuthorRoute.page),
    AutoRoute(page: ContentWarningRoute.page),
    AutoRoute(page: HighlightsRoute.page),
    AutoRoute(page: DeepSearchRoute.page),

    // Sources
    AutoRoute(page: ImportRoute.page),
    AutoRoute(page: ExtensionReposRoute.page),
    AutoRoute(page: SourceSettingsRoute.page),
    AutoRoute(page: SourceLoginRoute.page),

    // More
    AutoRoute(page: DownloadQueueRoute.page),
    AutoRoute(page: SyncRoute.page),
    AutoRoute(page: StatsRoute.page),

    // Settings
    AutoRoute(page: SettingsRoute.page),
    AutoRoute(page: SettingsSearchRoute.page),
    AutoRoute(page: AppearanceSettingsRoute.page),
    AutoRoute(page: EinkSettingsRoute.page),
    AutoRoute(page: CustomThemeRoute.page),
    AutoRoute(page: LibrarySettingsRoute.page),
    AutoRoute(page: ReaderPrefsRoute.page),
    AutoRoute(page: DownloadSettingsRoute.page),
    AutoRoute(page: AccountsSettingsRoute.page),
    AutoRoute(page: DataSettingsRoute.page),
    AutoRoute(page: PrivacySettingsRoute.page),
    AutoRoute(page: AdvancedSettingsRoute.page),
    AutoRoute(page: AboutRoute.page),
    AutoRoute(page: AppUpdateRoute.page),
    AutoRoute(page: ChangelogRoute.page),
    AutoRoute(page: CoverSettingsRoute.page),
    AutoRoute(page: AiSettingsRoute.page),
    AutoRoute(page: CommunityArchiveRoute.page),
    AutoRoute(page: ServerDataRoute.page),
    AutoRoute(page: DevicesRoute.page),
    AutoRoute(page: RestoreBackupRoute.page),
    AutoRoute(page: MutedTagsRoute.page),
    AutoRoute(page: EditCategoriesRoute.page),

    // Errors and feedback
    AutoRoute(page: CrashRoute.page),
    AutoRoute(page: ErrorReportRoute.page),
    AutoRoute(page: FeedbackRoute.page),
  ];
}
```

- `HomeShellRoute` has `children`: the five tabs live inside the shell, so switching tabs keeps the bottom bar and each tab's own back stack.
- Every other page is a sibling at the top level, so it covers the shell when pushed (full-screen details, reader, settings).
- After adding a page, add its route here and run build_runner; `app_router.gr.dart` then contains its `Route` class.

For this milestone, the tab pages can be placeholders:

```dart
@RoutePage()
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Updates')));
}
```

**Step 8: the home shell.** `AutoTabsRouter` keeps all five tab pages alive and swaps which one is visible. The builder decides the navigation chrome from the window size:

```dart
/// Bottom navigation (Library, Updates, Browse, History, More) plus the
/// Mihon-style "Downloaded only" / "Incognito mode" banners above everything.
@RoutePage()
class HomeShellPage extends ConsumerWidget {
  const HomeShellPage({super.key});

  static const _destinations = [
    (Symbols.collections_bookmark_rounded, 'Library'),
    (Symbols.new_releases_rounded, 'Updates'),
    (Symbols.explore_rounded, 'Browse'),
    (Symbols.history_rounded, 'History'),
    (Symbols.more_horiz_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadedOnly = ref.pref(Prefs.downloadedOnly);
    final incognito = ref.pref(Prefs.incognito);
    final hasBanner = downloadedOnly || incognito;

    // Checks for app updates on launch and offers one when found.
    return AppUpdateListener(
      child: AutoTabsRouter(
        routes: const [LibraryRoute(), UpdatesRoute(), BrowseRoute(), HistoryRoute(), MoreRoute()],
        builder: (context, child) {
          final tabs = AutoTabsRouter.of(context);
          // Tablets and unfolded foldables: navigation rail instead of the bottom bar.
          if (context.useNavigationRail) {
            return Scaffold(
              body: Row(
                children: [
                  SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: tabs.activeIndex,
                      onDestinationSelected: tabs.setActiveIndex,
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: NoctuaLogo(size: 32)),
                      destinations: [
                        for (final (i, (icon, label)) in _destinations.indexed)
                          NavigationRailDestination(
                            icon: i == 1 ? Badge(label: const Text('7'), child: Icon(icon)) : Icon(icon),
                            selectedIcon: i == 1 ? Badge(label: const Text('7'), child: Icon(icon, fill: 1)) : Icon(icon, fill: 1),
                            label: Text(label),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        if (hasBanner) ModeBanners(downloadedOnly: downloadedOnly, incognito: incognito),
                        Expanded(
                          child: hasBanner ? MediaQuery.removePadding(context: context, removeTop: true, child: child) : child,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return Scaffold(
            body: Column(
              children: [
                if (hasBanner) ModeBanners(downloadedOnly: downloadedOnly, incognito: incognito),
                Expanded(
                  // The banners already cover the status bar inset.
                  child: hasBanner ? MediaQuery.removePadding(context: context, removeTop: true, child: child) : child,
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tabs.activeIndex,
              onDestinationSelected: tabs.setActiveIndex,
              destinations: [
                for (final (i, (icon, label)) in _destinations.indexed)
                  NavigationDestination(
                    icon: i == 1 ? Badge(label: const Text('7'), child: Icon(icon)) : Icon(icon),
                    selectedIcon: i == 1 ? Badge(label: const Text('7'), child: Icon(icon, fill: 1)) : Icon(icon, fill: 1),
                    label: label,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- `_destinations` is a list of records `(icon, label)`; the loop destructures them with `for (final (i, (icon, label)) in _destinations.indexed)`.
- `Icon(icon, fill: 1)` uses Material Symbols' variable fill axis for the selected state, instead of shipping two icon sets.
- `AppUpdateListener` from [[Milestone 03 - In-app updates|milestone 3]] wraps the whole shell, so the launch check starts on the first screen users see. Delete [[Milestone 03 - In-app updates|milestone 3]]'s temporary home page now.
- The shell lives in `lib/src/routing/`, not in a feature: like the router, it is wiring that knows about every tab.
- The `Badge` with "7" is placeholder data until [[Milestone 09 - Updates, History, Browse and sources|milestone 9]]'s Updates page exists.

The banners at the top come from Mihon: "Downloaded only" and "Incognito mode" are global modes, so they sit above every tab:

```dart
class ModeBanners extends StatelessWidget {
  const ModeBanners({super.key, required this.downloadedOnly, required this.incognito});
  final bool downloadedOnly;
  final bool incognito;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    Widget bar(String text, Color bg, Color fg, double extraTop) => Container(
      width: double.infinity,
      color: bg,
      padding: EdgeInsets.only(top: extraTop + 4, bottom: 4),
      alignment: Alignment.center,
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
    return Column(
      children: [
        if (downloadedOnly) bar('Downloaded only', c.tertiary, c.onTertiary, top),
        if (incognito) bar('Incognito mode', c.primary, c.onPrimary, downloadedOnly ? 0 : top),
      ],
    );
  }
}
```

The first banner takes the status bar inset (`MediaQuery.paddingOf(context).top`) as extra padding, and the shell then removes that inset from the tab below with `MediaQuery.removePadding`, so the tab's app bar doesn't leave a gap.

**Step 9: the logo widget.** `assets/branding/logo_mask.png` is the owl in white on transparent; `BlendMode.srcIn` paints it in any colour, so one asset follows every theme. Add the asset to `pubspec.yaml` under `flutter: assets:`.

```dart
import 'package:flutter/material.dart';

/// The owl-and-moon logo, tinted with [color] (the theme's primary by default),
/// so it follows every theme including E-ink.
class NoctuaLogo extends StatelessWidget {
  const NoctuaLogo({super.key, this.size = 56, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/logo_mask.png',
    width: size,
    height: size,
    color: color ?? Theme.of(context).colorScheme.primary,
    colorBlendMode: BlendMode.srcIn,
    semanticLabel: 'Noctua',
  );
}
```

**Step 10: the app widget.** `NoctuaApp` turns the router into a `routerConfig` once (in `late final`, so hot reload doesn't rebuild the navigation stack) and watches the themes:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/src/constants/breakpoints.dart';
import 'package:noctua/src/features/auth/data/session_repository.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/routing/app_router.dart';
import 'package:noctua/src/routing/app_router.gr.dart';
import 'package:noctua/src/theme/app_theme.dart';
import 'package:responsive_framework/responsive_framework.dart';

class NoctuaApp extends ConsumerStatefulWidget {
  const NoctuaApp({super.key, required this.router});
  final AppRouter router;

  @override
  ConsumerState<NoctuaApp> createState() => _NoctuaAppState();
}

class _NoctuaAppState extends ConsumerState<NoctuaApp> {
  // Signed out → welcome screen; otherwise straight to the library.
  late final _routerConfig = widget.router.config(
    deepLinkBuilder: (_) =>
        DeepLink.single(switch ((ref.read(sessionRepositoryProvider), ref.readPref(Prefs.setupDone), ref.readPref(Prefs.tourDone))) {
          (null, _, _) => const WelcomeRoute(),
          (_, false, _) => const SetupRoute(),
          (_, true, false) => const TourRoute(),
          _ => const HomeShellRoute(),
        }),
  );

  @override
  Widget build(BuildContext context) {
    final themes = ref.watch(appThemesProvider);
    return MaterialApp.router(
      title: 'Noctua',
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: themes.mode,
      routerConfig: _routerConfig,
      // Names the window size classes the layouts switch on (constants/breakpoints.dart).
      builder: (context, child) => ResponsiveBreakpoints.builder(child: child!, breakpoints: WindowSize.breakpoints),
    );
  }
}
```

- `deepLinkBuilder` picks the first screen. The `switch` over a record `(session, setupDone, tourDone)` reads top to bottom like a decision table; milestones 11 and 12 add those screens and the `sessionRepositoryProvider` it reads. For now, return `const HomeShellRoute()`.
- `builder` wraps everything below `MaterialApp` in `ResponsiveBreakpoints.builder`, which is what makes `context.useNavigationRail` work in every route, dialogs and sheets included.

**Step 11: `main()` at this point.** [[Milestone 04 - Preferences and the local database|Milestone 4]]'s `main()` gains the dynamic colours and starts `NoctuaApp` instead of the temporary home:

```dart
Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  F.appFlavor = Flavor.values.asNameMap()[appFlavor] ?? Flavor.stable;

  final db = AppDatabase();
  final prefs = await db.loadPreferences();
  final dynamicSchemes = /* step 5 */;
  final installed = await readInstalledApp();

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      initialPrefsProvider.overrideWithValue(prefs),
      dynamicSchemesProvider.overrideWithValue(dynamicSchemes),
      installedAppProvider.overrideWithValue(installed),
    ],
    child: NoctuaApp(router: AppRouter()),
  ));
  FlutterNativeSplash.remove();
}
```

Because preferences are loaded before `runApp` and the native splash stays up until then, the first frame is already in the saved theme: no flash of Catppuccin before switching to the user's choice.

**Step 12: the updater on the router.** The three update widgets from [[Milestone 03 - In-app updates|milestone 3]] switch to the shortcuts from step 1 and to auto_route: `AppUpdatePage` and `ChangelogPage` get `@RoutePage()`, and `Navigator.of(context).push(MaterialPageRoute(...))` becomes `context.router.push(const AppUpdateRoute())`. Nothing in the controller, service or repositories changes, which is the point of keeping them out of the widgets.

**Step 13: small shared widgets.** Two widgets used on almost every screen from [[Milestone 06 - The library|milestone 6]] on; create them now in `lib/src/common_widgets/common_widgets.dart`:

```dart
/// Small rounded count, used for unread chapters and the Updates badge.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(9)),
    child: Text(
      '$count',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.colors.onPrimary),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8), this.trailing});
  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Stand-in for actions that would hit the network in the real app.
void showPlaceholder(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what (placeholder)'), behavior: SnackBarBehavior.floating));
}
```

`?trailing` in the `Row` is Dart 3.8's null-aware element: the child is added only when it isn't null.

> [!success] Checkpoint
> run build\_runner, then the app. You get five empty tabs in Catppuccin Mocha. The Appearance screen (built properly in [[Milestone 10 - Settings|milestone 10]], but worth wiring now to test themes) switches theme, dark mode and pure black instantly. Kill the app and reopen it: it comes back in the theme you picked, with no flash of the default.

![[noctua-m05-theming.png]]
*Milestone 5: Appearance settings and the library in Catppuccin Latte*

---
← [[Milestone 04 - Preferences and the local database]] · [[00 Index|Index]] · [[Milestone 06 - The library]] →
