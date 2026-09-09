import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:scribble/scribble.dart';

import '../../../../services/editor_settings_store.dart';

/// Concentric "tool wheel", inspired by the Concepts app's *Color Wheels*.
///
/// Two decoupled layers, both centred on a single draggable [_anchor]:
///
///   * **Hub** (SCALES with `_hubScale`) — a fixed-position cluster of controls:
///     a center disc (current colour + tool; tap = expand, long-press =
///     settings), tool chips at fixed bearings (pen/highlighter/eraser/undo/
///     redo), a concentric **size** dial ring, a **colour** readout, and a
///     **"+"** custom-colour button. Pinch/scroll resizes only this hub.
///   * **Colour wheel** (CONSTANT size, large) — a custom-swatch ring plus a
///     grid of swatches from the ACTIVE [WheelTheme]'s table: one angular sector
///     per hue family, each with a variable number of FIXED-height value bands,
///     so families of different sizes make a deliberately **ragged** outer edge.
///     Hex labels are toggleable (see [_HexToggle] / showHex); themes are
///     switchable/creatable in the settings sheet. It is deliberately bigger
///     than the screen so, docked in a corner, most of it sits **off-screen**;
///     you **drag to rotate** it 360° and **tap the visible swatch** you want.
///     Painter and hit-test both derive geometry from the table indices (via
///     [_cellColor] + [_paletteRotation]), so a tapped swatch is exactly the
///     colour drawn there.
///
/// Because the wheel runs off-screen, the interactive area is gated to the
/// *visible disc* by [_DiscHitRegion] — pointers outside it fall through to the
/// page canvas so you can still draw around/under the (huge) wheel.
///
/// Tool/colour/size changes flow through [onSelectTool] so they FOLLOW across
/// pages (see PagedNoteController). Undo/redo are page-LOCAL (run on [notifier]).
class ToolDialHub extends StatefulWidget {
  const ToolDialHub({
    super.key,
    required this.notifier,
    this.onSelectTool,
    this.partialEraser,
    this.eraserWidth,
  });

  /// The ACTIVE page's ink notifier — undo/redo + single-surface fallback.
  final ScribbleNotifier notifier;

  /// Broadcasts a persistent tool/colour/size mutation to every page.
  final void Function(void Function(ScribbleNotifier) config)? onSelectTool;

  /// Eraser mode toggle (partial ↔ whole), shared with the ink layer.
  final ValueNotifier<bool>? partialEraser;

  /// Eraser diameter (logical px), shared with the ink layer. The size selector
  /// writes to this while the eraser is active, so pages erase by the same size.
  final ValueNotifier<double>? eraserWidth;

  @override
  State<ToolDialHub> createState() => _ToolDialHubState();
}

enum _Tool { pen, highlighter, eraser, undo, redo }

/// Every hub control (tools + the "+" button). The size selector is NOT here —
/// it's a concentric ring around the whole hub (see _inSizeRing / _paintHub).
enum _Ctl { pen, highlighter, eraser, undo, redo, plus }

const Map<_Ctl, IconData> _ctlIcons = {
  _Ctl.pen: Icons.edit,
  _Ctl.highlighter: Icons.border_color,
  _Ctl.eraser: Icons.cleaning_services,
  _Ctl.undo: Icons.undo,
  _Ctl.redo: Icons.redo,
  _Ctl.plus: Icons.add,
};

const Map<_Ctl, _Tool> _ctlTool = {
  _Ctl.pen: _Tool.pen,
  _Ctl.highlighter: _Tool.highlighter,
  _Ctl.eraser: _Tool.eraser,
  _Ctl.undo: _Tool.undo,
  _Ctl.redo: _Tool.redo,
};

/// Fixed hub layout: (bearing° from straight-up clockwise, radius as a multiple
/// of the chip ring). Single source of truth — painter + hit-test both position
/// controls from this, so they can't drift.
const Map<_Ctl, (double, double)> _ctlLayout = {
  _Ctl.pen: (0, 1.0),
  _Ctl.redo: (65, 1.0),
  _Ctl.eraser: (130, 1.0),
  _Ctl.highlighter: (230, 1.0),
  _Ctl.undo: (295, 1.0),
  _Ctl.plus: (180, 1.0), // bottom
};

/// Per-tool stroke-width range (logical px). The size control maps drags into it.
/// The eraser's "width" is its diameter (the ink layer erases by half of it).
const Map<_Tool, ({double min, double max})> _widthRange = {
  _Tool.pen: (min: 1, max: 30),
  _Tool.highlighter: (min: 4, max: 60),
  _Tool.eraser: (min: 8, max: 72),
};

// --- Colour wheel: hue families around × values outward (fixed table) ---------
//
// Structure, not computation: each swatch lives at a fixed (sector, band)
// coordinate in the ACTIVE theme's table and both the painter and the hit-test
// derive their geometry from those indices, so a tapped cell is exactly the
// colour drawn there. Every band is a FIXED radial height ([_kBandThickness]);
// families have DIFFERENT band counts, so the outer edge is deliberately ragged
// — "islands" of unequal height, à la the Concepts colour wheel. The table
// itself comes from a [WheelTheme] (built-in or user-curated); see that model
// and [WheelTheme.fromColors] for how a curated colour set is arranged.
const double _kWheelInnerR = 180; // hole for the hub
const double _kCustomOuterR = 210; // custom-swatch ring: inner..this
const double _kBandThickness = 34; // fixed height per swatch band (tall cells)
const int _kMaxBands = 6; // longest family (keeps the table within the disc)
const double _kWheelOuterR =
    _kCustomOuterR + _kMaxBands * _kBandThickness; // max possible extent
// Swatches are drawn translucent (no opaque backing) so the page shows through;
// picking still yields the FULL opaque colour. Wedges sit edge-to-edge
// (connected) — set the gap fraction > 0 to separate them into tiles.
const double _kSwatchAlpha = 0.82;
const double _kSectorGapFrac = 0.0; // fraction of a wedge left as a gap

/// Colour of the swatch at (hue [sector], value [band]) in [pal], or null where
/// a family has no band there (the ragged edge / gaps). Shared by painter AND
/// hit-test.
Color? _cellColor(List<List<int>> pal, int sector, int band) {
  if (sector < 0 || sector >= pal.length) return null;
  final col = pal[sector];
  if (band < 0 || band >= col.length) return null;
  return Color(0xFF000000 | col[band]);
}

const double _deg = math.pi / 180;

/// A control's centre, given the hub centre [c] and chip-ring radius [ringR].
/// Bearing 0 = straight up, increasing clockwise (matches the wheel + hit-test).
Offset _ctlCentre(Offset c, _Ctl ctl, double ringR) {
  final (bearingDeg, factor) = _ctlLayout[ctl]!;
  final b = bearingDeg * _deg;
  return c + Offset(math.sin(b), -math.cos(b)) * (ringR * factor);
}

class _ToolDialHubState extends State<ToolDialHub> {
  // --- Hub geometry (scaled by _hubScale). ---
  static const double _baseCenterR = 30;
  static const double _baseRingR = 58; // chip-ring radius
  static const double _baseChipR = 17;
  static const double _baseSizeRingR = 104; // size-dial ring, around the chips
  static const double _baseSizeRingStroke = 9;
  static const double _baseLabelR = 86; // "N px" (top) + colour (bottom) pills

  double _minHubScale = 0.8;
  double _maxHubScale = 1.5;
  double _hubScale = 1.0;
  double _scaleAtGestureStart = 1.0;

  Offset? _anchor; // wheel/hub centre in overlay coords; null → default
  Offset _resolvedAnchor = Offset.zero; // last resolved anchor (for handlers)

  _Tool _tool = _Tool.pen;
  Color _penColor = Colors.black;
  String? _penColorName;
  final Map<_Tool, double> _toolWidths = {
    _Tool.pen: 4,
    _Tool.highlighter: 16,
    _Tool.eraser: 24,
  };
  List<CustomSwatch> _customColors = [];

  double _paletteRotation = 0.0;
  bool _expanded = false;
  bool _showHex = false; // per-cell hex labels on the wheel (toggle, persisted)

  // Colour-wheel themes: built-ins + user-curated, with one active. The active
  // theme's [WheelTheme.sectors] table is what the wheel paints and hit-tests.
  List<WheelTheme> _themes = WheelTheme.builtIns();
  WheelTheme _activeTheme = WheelTheme.fallback;
  List<List<int>> get _palette => _activeTheme.sectors;

  _DragMode _dragMode = _DragMode.move;
  double _lastRotateAngle = 0.0;
  bool _widthDirty = false;
  // Where inside the hub the move-drag was grabbed (finger − anchor). Kept so the
  // anchor tracks the finger ABSOLUTELY each frame — accumulating focalPointDelta
  // instead drifts/lags behind the cursor once frames drop under the wheel's
  // repaint. See _onScaleUpdate's move case.
  Offset _grabOffset = Offset.zero;

  double get _centerR => _baseCenterR * _hubScale;
  double get _ringR => _baseRingR * _hubScale;
  double get _chipR => _baseChipR * _hubScale;
  double get _sizeRingR => _baseSizeRingR * _hubScale;
  double get _sizeRingStroke => _baseSizeRingStroke * _hubScale;
  double get _labelR => _baseLabelR * _hubScale;
  // Outer extent of the hub (the size ring is the outermost element). Kept below
  // [_kWheelInnerR] so the hub never overlaps the wheel — with the 1.6 max scale
  // this stays ~172 < 180.
  double get _hubOuterR => _sizeRingR + _sizeRingStroke / 2 + 6;
  // Radius of the interactive disc (see [_DiscHitRegion]).
  double get _gateR => _expanded ? _kWheelOuterR : _hubOuterR;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    final s = await EditorSettingsStore.loadSettings();
    final custom = await EditorSettingsStore.loadCustomColors();
    final themes = await EditorSettingsStore.loadThemes();
    if (!mounted) return;
    final allThemes = [...WheelTheme.builtIns(), ...themes.custom];
    final active = allThemes.firstWhere(
      (t) => t.name == themes.active,
      orElse: () => allThemes.first,
    );
    setState(() {
      _themes = allThemes;
      _activeTheme = active;
      // Cap at 1.5 so the (now larger) hub + size ring stays inside the wheel
      // hole: _hubOuterR base ≈114.5 × 1.5 ≈172 < _kWheelInnerR (180).
      _minHubScale = s.minWheelScale.clamp(0.5, 1.5);
      _maxHubScale = s.maxWheelScale.clamp(_minHubScale, 1.5);
      _hubScale = _hubScale.clamp(_minHubScale, _maxHubScale);
      _toolWidths[_Tool.pen] = s.penWidth;
      _toolWidths[_Tool.highlighter] = s.highlighterWidth;
      _toolWidths[_Tool.eraser] = s.eraserWidth;
      _showHex = s.showHex;
      _customColors = custom;
    });
    // Seed the shared eraser size so pages erase by the persisted width even
    // before the eraser is first selected.
    widget.eraserWidth?.value = _toolWidths[_Tool.eraser]!;
  }

  EditorSettings get _settingsSnapshot => EditorSettings(
    minWheelScale: _minHubScale,
    maxWheelScale: _maxHubScale,
    penWidth: _toolWidths[_Tool.pen]!,
    highlighterWidth: _toolWidths[_Tool.highlighter]!,
    eraserWidth: _toolWidths[_Tool.eraser]!,
    showHex: _showHex,
  );

  /// Default resting anchor: inset from the bottom-left so the HUB stays fully
  /// on-screen while the big wheel overflows the left/bottom edges.
  Offset _defaultAnchor(BoxConstraints c) =>
      Offset(_hubOuterR + 24, c.maxHeight - _hubOuterR - 24);

  // --------------------------------------------------------------------------
  // Regions (all relative to _resolvedAnchor)
  // --------------------------------------------------------------------------

  double _bearingOf(Offset local) {
    final v = local - _resolvedAnchor;
    var b = math.atan2(v.dx, -v.dy);
    if (b < 0) b += 2 * math.pi;
    return b;
  }

  /// The hub control nearest [local], or null if none is within its chip.
  _Ctl? _ctlAt(Offset local) {
    _Ctl? best;
    var bestD = _chipR * 1.45;
    for (final ctl in _Ctl.values) {
      final d = (local - _ctlCentre(_resolvedAnchor, ctl, _ringR)).distance;
      if (d < bestD) {
        bestD = d;
        best = ctl;
      }
    }
    return best;
  }

  bool _inWheel(Offset local) {
    if (!_expanded) return false;
    final d = (local - _resolvedAnchor).distance;
    return d >= _kWheelInnerR && d <= _kWheelOuterR;
  }

  /// Whether [local] falls on the concentric size-dial ring (a generous band so
  /// it's grabbable by touch as well as a mouse).
  bool _inSizeRing(Offset local) {
    if (_widthRange[_tool] == null) return false;
    final d = (local - _resolvedAnchor).distance;
    return (d - _sizeRingR).abs() <= _sizeRingStroke / 2 + 12;
  }

  /// Map a 0..1 fraction onto the active tool's width range and store it.
  void _setWidthFraction(double f) {
    final range = _widthRange[_tool];
    if (range == null) return;
    _toolWidths[_tool] =
        range.min + f.clamp(0.0, 1.0) * (range.max - range.min);
    _widthDirty = true;
  }

  // --------------------------------------------------------------------------
  // Tap selection
  // --------------------------------------------------------------------------

  void _handleTap(Offset local) {
    final dist = (local - _resolvedAnchor).distance;
    if (dist <= _centerR) {
      setState(() => _expanded = !_expanded);
      return;
    }
    final ctl = _ctlAt(local);
    if (ctl != null) {
      if (ctl == _Ctl.plus) {
        _promptCustomColor();
      } else {
        _selectTool(_ctlTool[ctl]!);
      }
      return;
    }
    // Tap the size ring → jump to that value (bearing 0 = top, clockwise).
    if (_inSizeRing(local)) {
      setState(() => _setWidthFraction(_bearingOf(local) / (2 * math.pi)));
      _applyCurrentTool();
      EditorSettingsStore.saveSettings(_settingsSnapshot);
      return;
    }
    if (_inWheel(local)) _pickFromWheel(local);
  }

  void _pickFromWheel(Offset local) {
    final dist = (local - _resolvedAnchor).distance;
    final bearing = _bearingOf(local);
    if (dist <= _kCustomOuterR) {
      final slots = _customColors.length;
      if (slots == 0) return;
      final idx = _slotAt(bearing, slots);
      final s = _customColors[idx];
      _pickColor(s.color, name: s.name);
      return;
    }
    if (_palette.isEmpty) return;
    final band = ((dist - _kCustomOuterR) / _kBandThickness).floor();
    final sector = _slotAt(bearing, _palette.length);
    final color = _cellColor(_palette, sector, band);
    if (color == null) return; // ragged gap / beyond this family — not a swatch
    _pickColor(color, name: null);
  }

  /// Slot index for a bearing across [count] equal wedges, undoing rotation so
  /// it matches paint.
  int _slotAt(double bearing, int count) {
    var b = (bearing - _paletteRotation) % (2 * math.pi);
    if (b < 0) b += 2 * math.pi;
    return (b / (2 * math.pi / count)).floor().clamp(0, count - 1);
  }

  void _selectTool(_Tool tool) {
    if (tool == _Tool.undo) {
      if (widget.notifier.canUndo) widget.notifier.undo();
      return;
    }
    if (tool == _Tool.redo) {
      if (widget.notifier.canRedo) widget.notifier.redo();
      return;
    }
    if (tool == _Tool.eraser && _tool == _Tool.eraser) {
      final flag = widget.partialEraser;
      if (flag != null) setState(() => flag.value = !flag.value);
      return;
    }
    setState(() => _tool = tool);
    _applyCurrentTool();
  }

  void _pickColor(Color color, {required String? name}) {
    setState(() {
      _penColor = color;
      _penColorName = name;
      if (_tool == _Tool.eraser) _tool = _Tool.pen;
    });
    _applyCurrentTool();
  }

  void _applyCurrentTool() {
    final tool = _tool;
    final color = _penColor;
    final width = _toolWidths[tool] ?? 4;
    _dispatch((n) {
      switch (tool) {
        case _Tool.pen:
          n.setColor(color);
          n.setStrokeWidth(width);
          break;
        case _Tool.highlighter:
          n.setColor(color.withValues(alpha: 0.4));
          n.setStrokeWidth(width);
          break;
        case _Tool.eraser:
          n.setEraser();
          // Sizes scribble's own whole-stroke eraser (it erases within
          // `selectedWidth`); the partial eraser reads the shared notifier below.
          n.setStrokeWidth(width);
          break;
        case _Tool.undo:
        case _Tool.redo:
          break;
      }
    });
    // Keep the pages' partial eraser in step with the wheel's eraser size.
    if (tool == _Tool.eraser) widget.eraserWidth?.value = width;
  }

  void _dispatch(void Function(ScribbleNotifier) config) {
    final onSelect = widget.onSelectTool;
    if (onSelect != null) {
      onSelect(config);
    } else {
      config(widget.notifier);
    }
  }

  // --------------------------------------------------------------------------
  // Drag: move anchor / rotate wheel / resize hub / resize brush
  // --------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d) {
    _scaleAtGestureStart = _hubScale;
    _lastRotateAngle = _bearingOf(d.localFocalPoint);
    if (_inWheel(d.localFocalPoint)) {
      _dragMode = _DragMode.rotate;
    } else if (_inSizeRing(d.localFocalPoint)) {
      _dragMode = _DragMode.size;
    } else {
      _dragMode = _DragMode.move;
      _grabOffset = d.localFocalPoint - _resolvedAnchor;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, BoxConstraints c) {
    if (d.pointerCount >= 2) {
      setState(() {
        _hubScale = (_scaleAtGestureStart * d.scale).clamp(
          _minHubScale,
          _maxHubScale,
        );
      });
      return;
    }
    switch (_dragMode) {
      case _DragMode.move:
        setState(() {
          // Absolute: follow the finger directly (no delta accumulation).
          final next = d.localFocalPoint - _grabOffset;
          // Keep the HUB fully on-screen; the wheel may overflow.
          _anchor = Offset(
            next.dx.clamp(
              _hubOuterR,
              math.max(_hubOuterR, c.maxWidth - _hubOuterR),
            ),
            next.dy.clamp(
              _hubOuterR,
              math.max(_hubOuterR, c.maxHeight - _hubOuterR),
            ),
          );
        });
        break;
      case _DragMode.rotate:
        final ang = _bearingOf(d.localFocalPoint);
        var delta = ang - _lastRotateAngle;
        if (delta > math.pi) delta -= 2 * math.pi;
        if (delta < -math.pi) delta += 2 * math.pi;
        _lastRotateAngle = ang;
        setState(() => _paletteRotation += delta);
        break;
      case _DragMode.size:
        if (_widthRange[_tool] == null) break;
        // Angular: track the finger's bearing around the ring incrementally, so
        // there's no jump where the arc wraps at the top and it reads the same
        // for touch and mouse.
        final ang = _bearingOf(d.localFocalPoint);
        var delta = ang - _lastRotateAngle;
        if (delta > math.pi) delta -= 2 * math.pi;
        if (delta < -math.pi) delta += 2 * math.pi;
        _lastRotateAngle = ang;
        final cur = _widthFraction ?? 0.0;
        setState(() => _setWidthFraction(cur + delta / (2 * math.pi)));
        _applyCurrentTool();
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_widthDirty) {
      _widthDirty = false;
      EditorSettingsStore.saveSettings(_settingsSnapshot);
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    setState(() {
      _hubScale = (_hubScale - e.scrollDelta.dy * 0.0012).clamp(
        _minHubScale,
        _maxHubScale,
      );
    });
  }

  void _onLongPress(LongPressStartDetails d) {
    if ((d.localPosition - _resolvedAnchor).distance <= _centerR) {
      _openWheelSettings();
    }
  }

  // --------------------------------------------------------------------------
  // Dialogs
  // --------------------------------------------------------------------------

  Future<void> _promptCustomColor() async {
    final result = await showDialog<CustomSwatch>(
      context: context,
      builder: (_) => const _CustomColorDialog(),
    );
    if (result == null || !mounted) return;
    final updated = await EditorSettingsStore.addCustomColor(result);
    if (!mounted) return;
    setState(() => _customColors = updated);
    _pickColor(result.color, name: result.name);
  }

  Future<void> _openWheelSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder: (context, setSheet) {
              Widget slider(
                String label,
                double value,
                double lo,
                double hi,
                ValueChanged<double> onChanged,
              ) {
                return Row(
                  children: [
                    SizedBox(width: 84, child: Text(label)),
                    Expanded(
                      child: Slider(
                        min: lo,
                        max: hi,
                        value: value.clamp(lo, hi),
                        label: '${(value * 100).round()}%',
                        onChanged: (v) {
                          setSheet(() {});
                          onChanged(v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(value * 100).round()}%',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tool-hub size limits',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    slider('Minimum', _minHubScale, 0.5, 1.4, (v) {
                      setState(() {
                        _minHubScale = v;
                        if (_maxHubScale < _minHubScale)
                          _maxHubScale = _minHubScale;
                        _hubScale = _hubScale.clamp(_minHubScale, _maxHubScale);
                      });
                    }),
                    slider('Maximum', _maxHubScale, 0.6, 1.5, (v) {
                      setState(() {
                        _maxHubScale = v;
                        if (_maxHubScale < _minHubScale)
                          _minHubScale = _maxHubScale;
                        _hubScale = _hubScale.clamp(_minHubScale, _maxHubScale);
                      });
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      'Colour theme',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    for (final t in _themes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          t.name == _activeTheme.name
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color:
                              t.name == _activeTheme.name
                                  ? const Color(0xFF2E7BF6)
                                  : Colors.black45,
                        ),
                        title: Text(t.name),
                        subtitle: _themeStrip(t),
                        trailing:
                            t.builtIn
                                ? null
                                : IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete theme',
                                  onPressed: () async {
                                    await _deleteTheme(t);
                                    setSheet(() {});
                                  },
                                ),
                        onTap: () {
                          _selectTheme(t);
                          setSheet(() {});
                        },
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('New theme'),
                        onPressed: () async {
                          await _promptNewTheme();
                          setSheet(() {});
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
    await EditorSettingsStore.saveSettings(_settingsSnapshot);
  }

  /// A thin strip of a theme's first swatches, for the settings list.
  Widget _themeStrip(WheelTheme t) {
    final colors = <int>[];
    for (final s in t.sectors) {
      colors.addAll(s);
      if (colors.length >= 14) break;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          for (final c in colors.take(14))
            Container(width: 12, height: 12, color: Color(0xFF000000 | c)),
        ],
      ),
    );
  }

  Future<void> _persistThemes() => EditorSettingsStore.saveThemes(
    _themes.where((t) => !t.builtIn).toList(),
    _activeTheme.name,
  );

  void _selectTheme(WheelTheme t) {
    setState(() => _activeTheme = t);
    _persistThemes();
  }

  Future<void> _deleteTheme(WheelTheme t) async {
    if (t.builtIn) return;
    setState(() {
      _themes = _themes.where((x) => x.name != t.name).toList();
      if (_activeTheme.name == t.name) _activeTheme = _themes.first;
    });
    await _persistThemes();
  }

  Future<void> _promptNewTheme() async {
    final existing = _themes.map((t) => t.name.toLowerCase()).toSet();
    final result = await showDialog<WheelTheme>(
      context: context,
      builder: (_) => _ThemeEditorDialog(existingNames: existing),
    );
    if (result == null || !mounted) return;
    setState(() {
      _themes = [..._themes, result];
      _activeTheme = result;
    });
    await _persistThemes();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _resolvedAnchor = _anchor ?? _defaultAnchor(constraints);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: _DiscHitRegion(
                  center: _resolvedAnchor,
                  radius: _gateR,
                  child: GestureDetector(
                    onTapUp: (d) => _handleTap(d.localPosition),
                    onLongPressStart: _onLongPress,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: (d) => _onScaleUpdate(d, constraints),
                    onScaleEnd: _onScaleEnd,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _WheelPainter(
                          anchor: _resolvedAnchor,
                          centerR: _centerR,
                          ringR: _ringR,
                          chipR: _chipR,
                          sizeRingR: _sizeRingR,
                          sizeRingStroke: _sizeRingStroke,
                          labelR: _labelR,
                          expanded: _expanded,
                          tool: _tool,
                          penColor: _penColor,
                          penColorName: _penColorName,
                          eraserPartial: widget.partialEraser?.value ?? true,
                          rotation: _paletteRotation,
                          customColors: _customColors,
                          activeWidth: _toolWidths[_tool],
                          widthFraction: _widthFraction,
                          showHex: _showHex,
                          sectors: _palette,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Hex-label toggle for the wheel — only while it's expanded.
            if (_expanded)
              Positioned(
                left: 12,
                top: 12,
                child: _HexToggle(
                  value: _showHex,
                  onChanged: () {
                    setState(() => _showHex = !_showHex);
                    EditorSettingsStore.saveSettings(_settingsSnapshot);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  double? get _widthFraction {
    final range = _widthRange[_tool];
    if (range == null) return null;
    return ((_toolWidths[_tool]! - range.min) / (range.max - range.min)).clamp(
      0.0,
      1.0,
    );
  }
}

enum _DragMode { move, rotate, size }

/// Small pill that toggles the wheel's per-swatch hex labels. Floats at the
/// top-left while the wheel is expanded.
class _HexToggle extends StatelessWidget {
  const _HexToggle({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2E7BF6);
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.tag : Icons.tag_outlined,
                size: 16,
                color: value ? accent : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                value ? 'Hex on' : 'Hex off',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gates hit-testing to a disc of [radius] around [center] (overlay coords), so
/// the huge off-screen colour wheel only intercepts pointers where it's actually
/// visible — everything else falls through to the page canvas beneath.
class _DiscHitRegion extends SingleChildRenderObjectWidget {
  const _DiscHitRegion({
    required this.center,
    required this.radius,
    required Widget child,
  }) : super(child: child);

  final Offset center;
  final double radius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDiscHit(center, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderDiscHit renderObject) {
    renderObject
      ..center = center
      ..radius = radius;
  }
}

class _RenderDiscHit extends RenderProxyBox {
  _RenderDiscHit(this._center, this._radius);

  Offset _center;
  double _radius;

  set center(Offset v) => _center = v;
  set radius(double v) => _radius = v;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if ((position - _center).distance > _radius) return false;
    return super.hitTest(result, position: position);
  }
}

/// Laid-out [TextPainter]s keyed by their content, shared across repaints.
///
/// The wheel draws ~70 hex labels (plus icons/pills); laying each one out on
/// every frame is what made dragging the (huge) wheel stutter and trail the
/// cursor. Every label here is deterministic in its key — same text, size,
/// colour, font ⇒ identical layout — so we lay out once and reuse. Bounded by
/// the fixed palette; the only churn is the size/colour pills as they change.
final Map<String, TextPainter> _glyphCache = {};

TextPainter _cachedGlyph(String key, TextSpan span) {
  final hit = _glyphCache[key];
  if (hit != null) return hit;
  final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
    ..layout();
  _glyphCache[key] = tp;
  return tp;
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.anchor,
    required this.centerR,
    required this.ringR,
    required this.chipR,
    required this.sizeRingR,
    required this.sizeRingStroke,
    required this.labelR,
    required this.expanded,
    required this.tool,
    required this.penColor,
    required this.penColorName,
    required this.eraserPartial,
    required this.rotation,
    required this.customColors,
    required this.activeWidth,
    required this.widthFraction,
    required this.showHex,
    required this.sectors,
  });

  final Offset anchor;
  final double centerR;
  final double ringR;
  final double chipR;
  final double sizeRingR;
  final double sizeRingStroke;
  final double labelR;
  final bool expanded;
  final _Tool tool;
  final Color penColor;
  final String? penColorName;
  final bool eraserPartial;
  final double rotation;
  final List<CustomSwatch> customColors;
  final double? activeWidth;
  final double? widthFraction;
  final bool showHex;
  final List<List<int>> sectors; // active theme's arranged palette

  static const Color _accent = Color(0xFF2E7BF6);

  IconData _iconForTool(_Tool t) =>
      t == _Tool.eraser
          ? (eraserPartial ? Icons.cleaning_services : Icons.layers_clear)
          : _ctlIcons[_ctlFor(t)]!;

  _Ctl _ctlFor(_Tool t) => _ctlTool.entries.firstWhere((e) => e.value == t).key;

  @override
  void paint(Canvas canvas, Size size) {
    if (expanded) _paintWheel(canvas, anchor);
    _paintHub(canvas, anchor);
  }

  // --- Constant-size colour wheel: custom ring + hue/shade bands, hex-labelled.
  void _paintWheel(Canvas canvas, Offset c) {
    // No backing disc — the translucent swatches composite straight over the
    // page, so the wheel reads as a transparent overlay.

    // Custom-swatch ring (rotates with the wheel).
    final slots = customColors.length;
    if (slots > 0) {
      final sweep = 2 * math.pi / slots;
      final gap = sweep * _kSectorGapFrac;
      final base = -math.pi / 2 + rotation;
      for (var i = 0; i < slots; i++) {
        final start = base + i * sweep + gap / 2;
        final path = _annularSector(
          c,
          _kWheelInnerR,
          _kCustomOuterR,
          start,
          sweep - gap,
        );
        final s = customColors[i];
        canvas.drawPath(
          path,
          Paint()..color = s.color.withValues(alpha: _kSwatchAlpha),
        );
        if (s.color.toARGB32() == penColor.toARGB32()) {
          _outline(canvas, path);
        }
        if (showHex) {
          final mid = start + (sweep - gap) / 2;
          final at =
              c +
              Offset(math.cos(mid), math.sin(mid)) *
                  ((_kWheelInnerR + _kCustomOuterR) / 2);
          _drawText(
            canvas,
            at,
            _shortHex(s.color),
            size: 9,
            color: _readableOn(s.color),
          );
        }
      }
    } else {
      // No custom colours yet — just the hint (no opaque fill, stays transparent).
      _drawText(
        canvas,
        c + const Offset(0, -(_kWheelInnerR + _kCustomOuterR) / 2),
        'tap  +  to save colours',
        size: 9,
        color: Colors.black45,
      );
    }

    // Hue families (sectors) × value bands. Each band is a FIXED radial height,
    // so families with more colours reach further out → a ragged outer edge.
    final sectorCount = sectors.length;
    if (sectorCount == 0) return;
    final sweep = 2 * math.pi / sectorCount;
    final gap = sweep * _kSectorGapFrac; // narrow each wedge a touch
    final base = -math.pi / 2 + rotation;
    for (var sector = 0; sector < sectorCount; sector++) {
      final col = sectors[sector];
      final start = base + sector * sweep + gap / 2;
      for (var band = 0; band < col.length; band++) {
        final inner = _kCustomOuterR + band * _kBandThickness;
        final outer = inner + _kBandThickness;
        final path = _annularSector(c, inner, outer, start, sweep - gap);
        final color = Color(0xFF000000 | col[band]);
        canvas.drawPath(
          path,
          Paint()..color = color.withValues(alpha: _kSwatchAlpha),
        );
        if (color.toARGB32() == penColor.toARGB32()) _outline(canvas, path);
        if (showHex) {
          final mid = start + (sweep - gap) / 2;
          final at =
              c + Offset(math.cos(mid), math.sin(mid)) * ((inner + outer) / 2);
          _drawText(
            canvas,
            at,
            _shortHex(color),
            size: 8,
            color: _readableOn(color),
          );
        }
      }
    }
  }

  void _paintHub(Canvas canvas, Offset c) {
    // Soft backing so the hub reads over the wheel / page.
    canvas.drawCircle(c, _hubBackingR, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      _hubBackingR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black12,
    );

    // Tool + "+" chips.
    for (final ctl in [
      _Ctl.pen,
      _Ctl.redo,
      _Ctl.eraser,
      _Ctl.highlighter,
      _Ctl.undo,
      _Ctl.plus,
    ]) {
      final at = _ctlCentre(c, ctl, ringR);
      final isTool = _ctlTool.containsKey(ctl);
      final selected = isTool && _ctlTool[ctl] == tool;
      canvas.drawCircle(
        at,
        chipR,
        Paint()
          ..color =
              selected ? _accent.withValues(alpha: 0.18) : Colors.grey.shade100,
      );
      final icon =
          _ctlTool[ctl] == _Tool.eraser
              ? _iconForTool(_Tool.eraser)
              : _ctlIcons[ctl]!;
      _drawIcon(
        canvas,
        at,
        icon,
        size: chipR * 1.1,
        color: selected ? _accent : Colors.black54,
      );
    }

    // Size dial: a concentric ring around the hub. Only the FILLED arc + a knob
    // are drawn — the unfilled/max track is deliberately NOT painted. Drag
    // around it (or tap) to resize; see _onScaleUpdate / _handleTap.
    final frac = widthFraction;
    if (frac != null) {
      final ringRect = Rect.fromCircle(center: c, radius: sizeRingR);
      canvas.drawArc(
        ringRect,
        -math.pi / 2, // start at the top
        frac * 2 * math.pi, // clockwise for `frac` of the circle
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sizeRingStroke
          ..strokeCap = StrokeCap.round
          ..color = _accent,
      );
      // Knob at the arc end (bearing 0 = up, clockwise — matches hit-test).
      final knobAng = frac * 2 * math.pi;
      final knobAt =
          c + Offset(math.sin(knobAng), -math.cos(knobAng)) * sizeRingR;
      final knobR = sizeRingStroke * 0.95;
      canvas.drawCircle(knobAt, knobR, Paint()..color = Colors.white);
      canvas.drawCircle(
        knobAt,
        knobR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _accent,
      );
    }

    // "N px" readout, tucked at the top inside the ring.
    final sizeText = activeWidth == null ? '—' : '${activeWidth!.round()} px';
    _drawPill(canvas, c + Offset(0, -labelR), sizeText, fontSize: 10);

    // Colour readout pill (bottom, inside the ring).
    final colourAt = c + Offset(0, labelR);
    final colourText = penColorName ?? _shortHex(penColor, withHash: true);
    _drawPill(
      canvas,
      colourAt,
      colourText,
      fontSize: 10,
      bg: penColor,
      fg: _readableOn(penColor),
    );

    // Center disc: current colour + tool.
    final centreColor = tool == _Tool.eraser ? Colors.grey.shade300 : penColor;
    canvas.drawCircle(c, centerR, Paint()..color = centreColor);
    canvas.drawCircle(
      c,
      centerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black26,
    );
    _drawIcon(
      canvas,
      c,
      _iconForTool(tool),
      size: centerR * 0.9,
      color: _readableOn(centreColor),
    );
  }

  double get _hubBackingR => sizeRingR + sizeRingStroke / 2 + 4;

  void _outline(Canvas canvas, Path path) => canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white,
  );

  Path _annularSector(
    Offset c,
    double inner,
    double outer,
    double start,
    double sweep,
  ) {
    final outerRect = Rect.fromCircle(center: c, radius: outer);
    final innerRect = Rect.fromCircle(center: c, radius: inner);
    return Path()
      ..moveTo(c.dx + inner * math.cos(start), c.dy + inner * math.sin(start))
      ..lineTo(c.dx + outer * math.cos(start), c.dy + outer * math.sin(start))
      ..arcTo(outerRect, start, sweep, false)
      ..lineTo(
        c.dx + inner * math.cos(start + sweep),
        c.dy + inner * math.sin(start + sweep),
      )
      ..arcTo(innerRect, start + sweep, -sweep, false)
      ..close();
  }

  void _drawIcon(
    Canvas canvas,
    Offset at,
    IconData icon, {
    required double size,
    required Color color,
  }) {
    final tp = _cachedGlyph(
      'I|${icon.codePoint}|$size|${color.toARGB32()}|${icon.fontFamily}',
      TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
    );
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawText(
    Canvas canvas,
    Offset at,
    String text, {
    required double size,
    required Color color,
  }) {
    final tp = _cachedGlyph(
      'T|$text|$size|${color.toARGB32()}',
      TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
    );
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawPill(
    Canvas canvas,
    Offset at,
    String text, {
    required double fontSize,
    Color? bg,
    Color? fg,
  }) {
    final tp = _cachedGlyph(
      'P|$text|$fontSize|${(fg ?? Colors.black87).toARGB32()}',
      TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: fg ?? Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final rect = Rect.fromCenter(
      center: at,
      width: tp.width + fontSize * 1.4,
      height: tp.height + fontSize * 0.7,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    canvas.drawRRect(rrect, Paint()..color = bg ?? Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black12,
    );
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  String _shortHex(Color color, {bool withHash = false}) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final h = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    return withHash ? '#$h' : h;
  }

  Color _readableOn(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.anchor != anchor ||
      old.centerR != centerR ||
      old.ringR != ringR ||
      old.chipR != chipR ||
      old.sizeRingR != sizeRingR ||
      old.sizeRingStroke != sizeRingStroke ||
      old.labelR != labelR ||
      old.expanded != expanded ||
      old.tool != tool ||
      old.penColor != penColor ||
      old.penColorName != penColorName ||
      old.eraserPartial != eraserPartial ||
      old.rotation != rotation ||
      old.activeWidth != activeWidth ||
      old.widthFraction != widthFraction ||
      old.showHex != showHex ||
      !identical(old.sectors, sectors) ||
      !identical(old.customColors, customColors);
}

/// A minimal HSV custom-colour picker (no extra dependency): three sliders + an
/// optional name, returning a [CustomSwatch] on confirm.
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog();

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  double _h = 210;
  double _s = 0.7;
  double _v = 0.9;
  final _name = TextEditingController();

  Color get _color => HSVColor.fromAHSV(1, _h, _s, _v).toColor();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${(_color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
              alignment: Alignment.center,
              child: Text(
                hex,
                style: TextStyle(
                  color:
                      _color.computeLuminance() > 0.5
                          ? Colors.black87
                          : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _labelled(
              'Hue',
              Slider(
                min: 0,
                max: 360,
                value: _h,
                onChanged: (v) => setState(() => _h = v),
              ),
            ),
            _labelled(
              'Saturation',
              Slider(value: _s, onChanged: (v) => setState(() => _s = v)),
            ),
            _labelled(
              'Value',
              Slider(value: _v, onChanged: (v) => setState(() => _v = v)),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            Navigator.of(
              context,
            ).pop(CustomSwatch(_color, name.isEmpty ? hex : name));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _labelled(String label, Widget slider) => Row(
    children: [
      SizedBox(width: 80, child: Text(label)),
      Expanded(child: slider),
    ],
  );
}

/// Curate a custom colour theme: add colours by hex or via the picker, name it,
/// and confirm. The colours are auto-arranged into the wheel by
/// [WheelTheme.fromColors] — the user never edits the grid directly.
class _ThemeEditorDialog extends StatefulWidget {
  const _ThemeEditorDialog({required this.existingNames});

  /// Lower-cased names already in use, so we can reject duplicates.
  final Set<String> existingNames;

  @override
  State<_ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends State<_ThemeEditorDialog> {
  final _name = TextEditingController();
  final _hex = TextEditingController();
  final List<int> _colors = [];

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _addHex() {
    final c = CustomSwatch.parseHex(_hex.text);
    if (c == null) return;
    setState(() {
      _colors.add(c.toARGB32() & 0x00FFFFFF);
      _hex.clear();
    });
  }

  Future<void> _addViaPicker() async {
    final s = await showDialog<CustomSwatch>(
      context: context,
      builder: (_) => const _CustomColorDialog(),
    );
    if (s == null) return;
    setState(() => _colors.add(s.color.toARGB32() & 0x00FFFFFF));
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final nameTaken = widget.existingNames.contains(name.toLowerCase());
    final canCreate = name.isNotEmpty && !nameTaken && _colors.length >= 2;
    return AlertDialog(
      title: const Text('New colour theme'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Theme name',
                isDense: true,
                errorText: nameTaken ? 'Name already used' : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onSubmitted: (_) => _addHex(),
                    decoration: const InputDecoration(
                      labelText: '#RRGGBB',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add hex',
                  onPressed: _addHex,
                ),
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'Pick a colour',
                  onPressed: _addViaPicker,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_colors.isEmpty)
              const Text(
                'Add at least two colours.',
                style: TextStyle(color: Colors.black45, fontSize: 12),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _colors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _colors.removeAt(i)),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | _colors[i]),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              canCreate
                  ? () => Navigator.of(
                    context,
                  ).pop(WheelTheme.fromColors(name, List<int>.from(_colors)))
                  : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
