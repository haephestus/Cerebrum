import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Color, HSVColor;

import 'package:cerebrum/services/storage_paths.dart';

/// Persistence for editor-local preferences that aren't part of a note's
/// content — currently the tool wheel's custom colour palette, per-tool stroke
/// widths, and the minimum wheel size. Mirrors [NoteStore]'s file-IO shape
/// (static async methods, JSON under `<appSupport>/cerebrum/…`) so the two read the
/// same way.
///
/// ```
/// <appSupport>/cerebrum/editor/
///     palette.json     # {"custom": [ {"hex": "#1E88E5", "name": "My Blue"} ] }
///     settings.json    # {"minWheelScale": .., "penWidth": .., "highlighterWidth": ..}
/// ```
///
/// These live in their own `editor/` folder (deliberately NOT loose
/// SharedPreferences keys) so all editor settings sit together and are easy to
/// inspect/back up alongside notes.
class EditorSettingsStore {
  // -- paths -------------------------------------------------------------

  static Future<Directory> _editorDir() async {
    final root = await StoragePaths.cerebrumRoot();
    return Directory('${root.path}/editor');
  }

  static Future<File> _paletteFile() async =>
      File('${(await _editorDir()).path}/palette.json');

  static Future<File> _settingsFile() async =>
      File('${(await _editorDir()).path}/settings.json');

  static Future<File> _themesFile() async =>
      File('${(await _editorDir()).path}/themes.json');

  // -- custom colours ----------------------------------------------------

  /// The user's saved custom swatches, oldest first. Empty (never throws) when
  /// nothing has been saved or the file is missing/corrupt.
  static Future<List<CustomSwatch>> loadCustomColors() async {
    final raw = await _readJson(await _paletteFile());
    final list = (raw is Map ? raw['custom'] : null);
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => CustomSwatch.fromJson(Map<String, dynamic>.from(e)))
        .whereType<CustomSwatch>()
        .toList();
  }

  /// Append [swatch] (de-duped by hex, case-insensitive) and persist. Returns
  /// the resulting list so callers can update their in-memory copy without a
  /// re-read.
  static Future<List<CustomSwatch>> addCustomColor(CustomSwatch swatch) async {
    final current = await loadCustomColors();
    current.removeWhere((s) => s.hex.toUpperCase() == swatch.hex.toUpperCase());
    current.add(swatch);
    await _writeJson(await _paletteFile(), {
      'custom': current.map((s) => s.toJson()).toList(),
    });
    return current;
  }

  // -- colour-wheel themes ----------------------------------------------
  //
  // Only USER themes are persisted (built-ins live in code — see
  // [WheelTheme.builtIns]). Stored as their flat source colours so they can be
  // re-arranged / re-edited later; the active theme is stored by name and may
  // refer to a built-in.

  /// Loaded custom themes (oldest first) + the persisted active-theme name (may
  /// name a built-in). Tolerant: returns `(const [], null)` on missing/corrupt.
  static Future<({List<WheelTheme> custom, String? active})>
      loadThemes() async {
    final raw = await _readJson(await _themesFile());
    if (raw is! Map) return (custom: const <WheelTheme>[], active: null);
    final list = raw['themes'];
    final custom = <WheelTheme>[];
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final name = (e['name'] as String?)?.trim();
        final colors = (e['colors'] as List?)
            ?.map((c) => CustomSwatch.parseHex(c?.toString()))
            .whereType<Color>()
            .map((c) => c.toARGB32() & 0x00FFFFFF)
            .toList();
        if (name == null || name.isEmpty || colors == null || colors.isEmpty) {
          continue;
        }
        custom.add(WheelTheme.fromColors(name, colors));
      }
    }
    return (custom: custom, active: raw['active'] as String?);
  }

  static Future<void> saveThemes(
      List<WheelTheme> custom, String activeName) async {
    await _writeJson(await _themesFile(), {
      'active': activeName,
      'themes': custom
          .map((t) => {
                'name': t.name,
                'colors': (t.sourceColors ?? const <int>[])
                    .map((h) =>
                        '#${(h & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}')
                    .toList(),
              })
          .toList(),
    });
  }

  // -- settings ----------------------------------------------------------

  static Future<EditorSettings> loadSettings() async {
    final raw = await _readJson(await _settingsFile());
    return EditorSettings.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : const {});
  }

  static Future<void> saveSettings(EditorSettings settings) async {
    await _writeJson(await _settingsFile(), settings.toJson());
  }

  // -- json io (same tolerant helpers as NoteStore) ----------------------

  static Future<void> _writeJson(File file, Object? data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  static Future<dynamic> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

/// A user-saved colour: an ARGB [Color] plus a display [name]. Serialised as
/// `{"hex": "#RRGGBB", "name": ".."}` (alpha dropped — swatches are opaque).
class CustomSwatch {
  const CustomSwatch(this.color, this.name);

  final Color color;
  final String name;

  /// `#RRGGBB`, upper-case, no alpha.
  String get hex => color.hex;

  Map<String, dynamic> toJson() => {'hex': hex, 'name': name};

  /// Parses `{"hex": "#RRGGBB", "name": ".."}`; returns null on a bad hex so a
  /// single corrupt entry can't break the whole load.
  static CustomSwatch? fromJson(Map<String, dynamic> json) {
    final parsed = parseHex(json['hex'] as String?);
    if (parsed == null) return null;
    final name = (json['name'] as String?)?.trim();
    return CustomSwatch(parsed, (name == null || name.isEmpty) ? parsed.hex : name);
  }

  /// `#RRGGBB` / `RRGGBB` → opaque [Color], or null if unparseable.
  static Color? parseHex(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}

extension _SwatchHex on Color {
  String get hex {
    final rgb = toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// Editor-wide preferences. Defaults are chosen so a fresh install behaves
/// exactly like the pre-persistence wheel (pen 4 / highlighter 16) with a
/// readable minimum size.
class EditorSettings {
  const EditorSettings({
    this.minWheelScale = 0.8,
    this.maxWheelScale = 1.8,
    this.penWidth = 4.0,
    this.highlighterWidth = 16.0,
    this.eraserWidth = 24.0,
    this.showHex = false,
  });

  /// Lower / upper bounds on the tool HUB's `_hubScale` (the colour wheel itself
  /// is a constant size). User-adjustable in the editor.
  final double minWheelScale;
  final double maxWheelScale;
  final double penWidth;
  final double highlighterWidth;

  /// Diameter (logical px) of the eraser — drives both the whole-stroke eraser
  /// hit radius and the partial-erase cut radius. Sized from the same wheel
  /// size selector as the pen/highlighter.
  final double eraserWidth;

  /// Whether the colour wheel draws each swatch's hex code (toggle on the wheel).
  final bool showHex;

  EditorSettings copyWith({
    double? minWheelScale,
    double? maxWheelScale,
    double? penWidth,
    double? highlighterWidth,
    double? eraserWidth,
    bool? showHex,
  }) =>
      EditorSettings(
        minWheelScale: minWheelScale ?? this.minWheelScale,
        maxWheelScale: maxWheelScale ?? this.maxWheelScale,
        penWidth: penWidth ?? this.penWidth,
        highlighterWidth: highlighterWidth ?? this.highlighterWidth,
        eraserWidth: eraserWidth ?? this.eraserWidth,
        showHex: showHex ?? this.showHex,
      );

  Map<String, dynamic> toJson() => {
        'minWheelScale': minWheelScale,
        'maxWheelScale': maxWheelScale,
        'penWidth': penWidth,
        'highlighterWidth': highlighterWidth,
        'eraserWidth': eraserWidth,
        'showHex': showHex,
      };

  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    double read(String k, double fallback) {
      final v = json[k];
      return v is num ? v.toDouble() : fallback;
    }

    return EditorSettings(
      minWheelScale: read('minWheelScale', 0.8),
      maxWheelScale: read('maxWheelScale', 1.8),
      penWidth: read('penWidth', 4.0),
      highlighterWidth: read('highlighterWidth', 16.0),
      eraserWidth: read('eraserWidth', 24.0),
      showHex: json['showHex'] == true,
    );
  }
}

/// A colour-wheel palette: hue families (angular sectors) × value bands, drawn
/// as concentric rings. Built-in themes carry a fixed [sectors] table; a custom
/// theme is a curated flat set of [sourceColors] auto-arranged into [sectors]
/// (see [fromColors]) — so users make themes by picking / typing colours, not
/// by editing a grid.
class WheelTheme {
  const WheelTheme({
    required this.name,
    required this.sectors,
    this.builtIn = false,
    this.sourceColors,
  });

  final String name;

  /// Arranged table: `sectors[sector][band] = 0xRRGGBB` (inner band = index 0).
  final List<List<int>> sectors;
  final bool builtIn;

  /// The flat curated set a custom theme was built from — persisted, and the
  /// basis for future edits. Null for built-ins.
  final List<int>? sourceColors;

  /// Largest family (radial cap) — keeps the arranged table inside the disc.
  static const int maxBands = 6;

  /// Build a theme by auto-arranging a curated colour set into the wheel: sort
  /// by hue, split into contiguous hue families, and order each family
  /// light→dark outward. Family count targets ~4 per family (big cells) without
  /// exceeding [maxBands]; unequal remainders create the ragged outer edge.
  factory WheelTheme.fromColors(String name, List<int> colors,
          {bool builtIn = false}) =>
      WheelTheme(
        name: name,
        sectors: arrangeIntoWheel(colors),
        builtIn: builtIn,
        sourceColors: List<int>.unmodifiable(colors),
      );

  static List<List<int>> arrangeIntoWheel(List<int> colors) {
    if (colors.isEmpty) return const [];
    final items = colors.map((c) {
      final hsv = HSVColor.fromColor(Color(0xFF000000 | c));
      return (hex: c & 0xFFFFFF, hue: hsv.hue, val: hsv.value);
    }).toList()
      ..sort((a, b) => a.hue.compareTo(b.hue));
    final n = items.length;
    var families = (n / 4).round().clamp(1, 18);
    if ((n / families).ceil() > maxBands) families = (n / maxBands).ceil();
    families = families.clamp(1, 24);
    final basePer = n ~/ families;
    var rem = n % families;
    final out = <List<int>>[];
    var i = 0;
    for (var f = 0; f < families; f++) {
      final take = basePer + (rem > 0 ? 1 : 0);
      if (rem > 0) rem--;
      if (take == 0) continue;
      final chunk = items.sublist(i, i + take)
        ..sort((a, b) => b.val.compareTo(a.val)); // light (high value) inner
      out.add(chunk.map((e) => e.hex).toList());
      i += take;
    }
    return out;
  }

  /// Built-in themes (not persisted). The first is the default.
  static List<WheelTheme> builtIns() => [
        const WheelTheme(
            name: 'Spectrum', sectors: _kSpectrumSectors, builtIn: true),
        WheelTheme.fromColors('Grayscale', _kGrayscale, builtIn: true),
      ];

  static const WheelTheme fallback =
      WheelTheme(name: 'Spectrum', sectors: _kSpectrumSectors, builtIn: true);
}

// Default "Spectrum" palette. GENERATED by scratchpad/gen_palette2.py (seed
// 1729): 18 hue families × 3–5 value bands (76 swatches), big cells + ragged
// edge. Edit freely — it's a plain fixed table.
const List<List<int>> _kSpectrumSectors = [
  [0xFFB2B6, 0xE27A7C, 0xC64A4A, 0xA92724, 0x8C0E07], // 0° x5
  [0xFFC8B2, 0xC6734A, 0x8C3A07], // 20° x3
  [0xFFE2B2, 0xD9B269, 0xB28930, 0x8C6607], // 40° x4
  [0xFFFBB2, 0xE2E07A, 0xC6C64A, 0xA6A924, 0x868C07], // 60° x5
  [0xE9FFB2, 0xB5D969, 0x85B230, 0x598C07], // 80° x4
  [0xD0FFB2, 0x90D969, 0x59B230, 0x2D8C07], // 100° x4
  [0xB6FFB2, 0x7CE27A, 0x4AC64A, 0x24A927, 0x078C0E], // 120° x5
  [0xB2FFC8, 0x4AC673, 0x078C3A], // 140° x3
  [0xB2FFE2, 0x69D9B2, 0x30B289, 0x078C66], // 160° x4
  [0xB2FFFB, 0x69D9D7, 0x30B0B2, 0x07868C], // 180° x4
  [0xB2E9FF, 0x7AC2E2, 0x4A9CC6, 0x2479A9, 0x07598C], // 200° x5
  [0xB2D0FF, 0x6990D9, 0x3059B2, 0x072D8C], // 220° x4
  [0xB2B6FF, 0x696BD9, 0x3230B2, 0x0E078C], // 240° x4
  [0xC8B2FF, 0x8C69D9, 0x5D30B2, 0x3A078C], // 260° x4
  [0xE2B2FF, 0xB269D9, 0x8930B2, 0x66078C], // 280° x4
  [0xFBB2FF, 0xE07AE2, 0xC64AC6, 0xA924A6, 0x8C0786], // 300° x5
  [0xFFB2E9, 0xE27AC2, 0xC64A9C, 0xA92479, 0x8C0759], // 320° x5
  [0xFFB2D0, 0xD96990, 0xB23059, 0x8C072D], // 340° x4
];

// Example built-in built from a curated flat set (demonstrates fromColors).
const List<int> _kGrayscale = [
  0xFFFFFF, 0xE6E6E6, 0xCCCCCC, 0xB3B3B3, 0x999999, 0x808080,
  0x666666, 0x4D4D4D, 0x333333, 0x1A1A1A, 0x000000,
];
