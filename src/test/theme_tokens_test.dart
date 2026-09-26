import 'package:cerebrum/ui/themes/default.dart';
import 'package:cerebrum/ui/themes/extensions.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/themes/theme_provider.dart';
import 'package:cerebrum/ui/themes/tokens/default_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the theming layer.
///
/// The first hand-written version of [CerebrumColors] shipped with
/// `copyWith(analysisBlock: analysisBlock ?? this.analysisMode)` -- a field
/// that silently fell back to a sibling token. The tests below fail if that
/// class of mistake is reintroduced, and if the provider stops resolving
/// themes end to end.
void main() {
  // Cannot collide with any value in the generated palettes.
  const sentinel = Color(0xFF010203);

  /// Rebuilds a group with a single token overridden, then asserts that
  /// exactly that one token moved.
  ///
  /// [rebuild] already collapses to `.asMap` so this works uniformly across
  /// groups with different types.
  void expectCopyWithIsIsolated(
    String name,
    Map<String, Color> before,
    Map<String, Color> Function(Color value) rebuild,
  ) {
    expect(before, isNotEmpty, reason: '$name declared no tokens');

    final after = rebuild(sentinel);
    expect(after.keys, before.keys, reason: '$name.asMap key set drifted');

    final moved = after.keys.where((k) => after[k] != before[k]).toList();
    expect(
      moved.length,
      1,
      reason: '$name.copyWith must move exactly one token, moved $moved',
    );
    expect(
      after[moved.single],
      sentinel,
      reason: '$name.copyWith wrote the sentinel to the wrong token',
    );
  }

  group('token wiring', () {
    test('both brightnesses resolve, and they differ', () {
      expect(cerebrumLightTokens, isNotNull);
      expect(cerebrumDarkTokens, isNotNull);
      expect(
        cerebrumLightTokens,
        isNot(equals(cerebrumDarkTokens)),
        reason: 'dark tokens must actually differ from light',
      );
    });

    test('copyWith isolates the field it was given, per group', () {
      final l = cerebrumLightTokens;
      expectCopyWithIsIsolated(
        'brand',
        l.brand.asMap,
        (v) => l.brand.copyWith(primary: v).asMap,
      );
      expectCopyWithIsIsolated(
        'surface',
        l.surface.asMap,
        (v) => l.surface.copyWith(canvas: v).asMap,
      );
      expectCopyWithIsIsolated(
        'shadow',
        l.shadow.asMap,
        (v) => l.shadow.copyWith(soft: v).asMap,
      );
      expectCopyWithIsIsolated(
        'text',
        l.text.asMap,
        (v) => l.text.copyWith(strong: v).asMap,
      );
      expectCopyWithIsIsolated(
        'status',
        l.status.asMap,
        (v) => l.status.copyWith(success: v).asMap,
      );
      expectCopyWithIsIsolated(
        'code',
        l.code.asMap,
        (v) => l.code.copyWith(background: v).asMap,
      );
      expectCopyWithIsIsolated(
        'editor',
        l.editor.asMap,
        (v) => l.editor.copyWith(insertMode: v).asMap,
      );
      expectCopyWithIsIsolated(
        'dial',
        l.dial.asMap,
        (v) => l.dial.copyWith(accent: v).asMap,
      );
      expectCopyWithIsIsolated(
        'gantt',
        l.gantt.asMap,
        (v) => l.gantt.copyWith(current: v).asMap,
      );
      expectCopyWithIsIsolated(
        'quiz',
        l.quiz.asMap,
        (v) => l.quiz.copyWith(rateEasy: v).asMap,
      );
    });

    test('every declared token appears in asMap', () {
      // Guards against a token existing on the class but missing from asMap,
      // which would make it invisible to the isolation test above.
      final l = cerebrumLightTokens;
      expect(
        l.editor.asMap.keys,
        containsAll([
          'insertMode',
          'normalMode',
          'analysisMode',
          'analysisBlock',
        ]),
      );
      final maps = <String, Map<String, Color>>{
        'brand': l.brand.asMap,
        'surface': l.surface.asMap,
        'shadow': l.shadow.asMap,
        'text': l.text.asMap,
        'status': l.status.asMap,
        'code': l.code.asMap,
        'editor': l.editor.asMap,
        'dial': l.dial.asMap,
        'gantt': l.gantt.asMap,
        'quiz': l.quiz.asMap,
      };
      expect(maps, hasLength(10));
      maps.forEach((name, map) {
        expect(map, isNotEmpty, reason: '$name.asMap is empty');
        expect(
          map.keys.toSet().length,
          map.length,
          reason: '$name.asMap has duplicate keys',
        );
      });

      // Backgrounds and foregrounds must be fully opaque. The alpha-bearing
      // groups (shadow, and the editor's page tints) are the deliberate
      // exceptions -- they exist to composite.
      for (final opaque in [
        l.surface.asMap,
        l.text.asMap,
        l.brand.asMap,
        l.status.asMap,
      ]) {
        expect(
          opaque.values.every((c) => c.a == 1.0),
          isTrue,
          reason: 'a surface/text/brand/status token is translucent',
        );
      }

      // Shadows and washes must actually be translucent, otherwise the
      // "bake the alpha in" contract is silently broken.
      expect(
        l.shadow.asMap.values.every((c) => c.a < 1.0),
        isTrue,
        reason: 'shadow tokens must carry their own alpha',
      );
    });

    test('copyWith with no arguments is identity', () {
      expect(cerebrumLightTokens.copyWith(), equals(cerebrumLightTokens));
      expect(
        cerebrumLightTokens.editor.copyWith(),
        equals(cerebrumLightTokens.editor),
      );
    });

    test('editor mode tokens are independently overridable', () {
      // insert and analysis ship equal in the default theme; a custom theme
      // must be able to split them without disturbing anything else.
      const red = Color(0xFFFF0000);
      final e = cerebrumLightTokens.editor.copyWith(analysisMode: red);
      expect(e.analysisMode, red);
      expect(e.insertMode, cerebrumLightTokens.editor.insertMode);
      expect(e.normalMode, cerebrumLightTokens.editor.normalMode);
    });

    test('lerp endpoints are exact and the midpoint lies between', () {
      final at0 = cerebrumLightTokens.lerp(cerebrumDarkTokens, 0);
      final at1 = cerebrumLightTokens.lerp(cerebrumDarkTokens, 1);
      expect(at0, equals(cerebrumLightTokens));
      expect(at1, equals(cerebrumDarkTokens));

      final mid = cerebrumLightTokens.lerp(cerebrumDarkTokens, 0.5);
      expect(
        mid.brand.primary,
        isNot(equals(cerebrumLightTokens.brand.primary)),
      );
      expect(
        mid.brand.primary.computeLuminance(),
        inInclusiveRange(
          cerebrumLightTokens.brand.primary.computeLuminance(),
          cerebrumDarkTokens.brand.primary.computeLuminance(),
        ),
      );
    });

    test('lerp with a foreign extension returns this', () {
      expect(cerebrumLightTokens.lerp(null, 0.5), equals(cerebrumLightTokens));
    });
  });

  group('theme family', () {
    test('default family registers the tokens on both themes', () {
      expect(
        defaultLightTheme.extension<CerebrumColors>(),
        equals(cerebrumLightTokens),
      );
      expect(
        defaultDarkTheme.extension<CerebrumColors>(),
        equals(cerebrumDarkTokens),
      );
    });

    test('theme brightness matches its token set', () {
      expect(defaultLightTheme.brightness, Brightness.light);
      expect(defaultDarkTheme.brightness, Brightness.dark);
    });

    test('color scheme is derived from tokens, not the stock M3 baseline', () {
      // The old scheme used 0xFF6750A4 while the widgets used 0xFF6C4FCE, so
      // the learning_center subtree rendered in a different palette from
      // everything else.
      final scheme = defaultLightTheme.colorScheme;
      expect(scheme.primary, cerebrumLightTokens.brand.primary);
      expect(scheme.surface, cerebrumLightTokens.surface.canvas);
      expect(scheme.onSurface, cerebrumLightTokens.text.strong);
      expect(scheme.error, cerebrumLightTokens.status.danger);
      expect(
        scheme.primary,
        isNot(const Color(0xFF6750A4)),
        reason: 'stock Material baseline purple must be gone',
      );
    });

    test('body text contrasts with its background in both brightnesses', () {
      for (final theme in [defaultLightTheme, defaultDarkTheme]) {
        final s = theme.colorScheme;
        expect(
          s.onSurface.computeLuminance(),
          isNot(equals(s.surface.computeLuminance())),
          reason: 'onSurface and surface must not be the same luminance',
        );
        expect(
          s.onPrimary.computeLuminance(),
          isNot(equals(s.primary.computeLuminance())),
        );
      }
    });
  });

  group('context access', () {
    testWidgets('context.cerebrum resolves the active theme', (tester) async {
      late CerebrumColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: defaultDarkTheme,
          home: Builder(
            builder: (context) {
              seen = context.cerebrum;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, equals(cerebrumDarkTokens));
    });

    testWidgets('context.cerebrum falls back when no extension is present', (
      tester,
    ) async {
      late CerebrumColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              seen = context.cerebrum;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, equals(defaultCerebrumColors));
    });

    test('ThemeData.cerebrum mirrors the context accessor', () {
      expect(defaultDarkTheme.cerebrum, equals(cerebrumDarkTokens));
      expect(ThemeData().cerebrum, equals(defaultCerebrumColors));
    });
  });

  group('provider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to the default family in light mode', () {
      final provider = ThemeProvider();
      expect(provider.selectedThemeId, 'default');
      expect(provider.darkMode, isFalse);
      expect(provider.theme, same(defaultLightTheme));
    });

    test('toggling brightness swaps within the same family', () {
      final provider = ThemeProvider()..setDarkMode(true);
      expect(provider.theme, same(defaultDarkTheme));
      expect(
        provider.theme.extension<CerebrumColors>(),
        equals(cerebrumDarkTokens),
      );
    });

    test('selecting a family keeps the brightness choice', () {
      final provider =
          ThemeProvider()
            ..setDarkMode(true)
            ..setSelectedTheme('default');
      expect(provider.theme.brightness, Brightness.dark);
    });

    test('an unknown persisted id degrades to the first family', () {
      // A theme removed from `families` must not crash the app on next launch.
      final provider = ThemeProvider();
      expect(provider.families, isNotEmpty);
      expect(
        provider.themeFor('no-such-theme'),
        isNotNull,
        reason: 'resolution must fall back rather than throw',
      );
    });
  });
}
