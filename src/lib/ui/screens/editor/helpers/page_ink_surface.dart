import 'package:flutter/foundation.dart';
import 'package:scribble/scribble.dart';

import 'package:cerebrum/ui/screens/editor/helpers/page_ink_store.dart';

/// Strategy-B ink rendering rail: owns ONE [ScribbleNotifier] per pageId,
/// seeded from the [PageInkStore], and relays every notifier's sketch back
/// into the store on change.
///
/// Why one notifier per pageId (not per sheet widget): sheets are
/// rebuilt/disposed freely; ink must belong to the page, not the widget.
/// The page block asks [notifierFor] at build time and overlays the
/// [NoteDrawingLayer] on that sheet.
///
/// Drawing-enabled itself is a controller-level bool today (no notifier):
/// the scaffold triggers its own rebuild on toggle, exactly like it does
/// for the per-page ink layers in Strategy A.
class PageInkSurface {
  PageInkSurface({
    required this.store,
    this.partialEraser,
    this.eraserWidth,
  });

  /// The per-pageId payload book. Source of truth between strokes, boot
  /// and the note save.
  final PageInkStore store;

  /// Drawing-mode gate shared by every sheet. Controllers flip this from
  /// their toggleDrawingMode; sheets only render/absorb according to it.
  final ValueNotifier<bool> drawingEnabled = ValueNotifier<bool>(false);
  void setDrawingEnabled(bool enabled) => drawingEnabled.value = enabled;

  /// Shared eraser preference listenables (owned by the scaffold; null →
  /// the layer's built-in defaults).
  final ValueListenable<bool>? partialEraser;
  final ValueListenable<double>? eraserWidth;

  final Map<String, ScribbleNotifier> _notifiers = {};
  void Function(ScribbleNotifier)? _activeToolConfig;

  /// Fetch (or lazily create) the notifier for [pageId], pre-seeded with the
  /// store's payload for that page. An unparseable payload seeds blank —
  /// the store remains the record; ink that can't be rebuilt is skipped,
  /// never silently dropped from bookkeeping (it's removed only through
  /// [removePage]).
  ScribbleNotifier notifierFor(String pageId) {
    final existing = _notifiers[pageId];
    if (existing != null) return existing;

    final notifier = ScribbleNotifier();
    notifier.setAllowedPointersMode(ScribblePointerMode.all);
    final payload = store.inkOf(pageId);
    if (payload != null && payload.isNotEmpty) {
      try {
        notifier.setSketch(
          sketch: Sketch.fromJson(payload.first),
          addToUndoHistory: false,
        );
      } catch (e) {
        debugPrint('[ink-surface] ink for $pageId failed to parse: $e');
      }
    }
    _activeToolConfig?.call(notifier);
    _attachSketchListener(pageId, notifier);
    _notifiers[pageId] = notifier;
    return notifier;
  }

  /// Apply [config] to every live notifier now and to every notifier
  /// created later (the "drawing tool" API from Strategy A, fanned out).
  void applyDrawingTool(void Function(ScribbleNotifier notifier) config) {
    _activeToolConfig = config;
    for (final n in _notifiers.values) {
      config(n);
    }
  }

  /// Remove the notifier for [pageId] (page vanished for good) and tell
  /// the store to drop the payload.
  void removePage(String pageId) {
    _notifiers.remove(pageId)?.dispose();
    store.removeInk(pageId);
  }

  // -- internal --------------------------------------------------------------

  void _attachSketchListener(String pageId, ScribbleNotifier n) {
    var lastSketch = n.currentSketch;
    n.addListener(() {
      final sketch = n.currentSketch;
      if (identical(sketch, lastSketch)) return;
      lastSketch = sketch;
      // Persist the WHOLE sketch payload (the store's record for this
      // page), never merges—— stroke replacement is whole-sketch.
      store.setInk(pageId, [sketch.toJson()]);
    });
  }

  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
    _notifiers.clear();
  }
}
