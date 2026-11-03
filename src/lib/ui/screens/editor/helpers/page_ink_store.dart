import 'package:flutter/foundation.dart';

typedef InkPayload = List<Map<String, dynamic>>;

/// Strategy-B ink store: pageId → one `Sketch.toJson()` payload.
///
/// In Strategy A, ink lived on `NoteEditorController` (one editor+ink pair
/// per page) and trusted `_pageHasInk`: a payload holds ink iff its sketch's
/// `lines` list is non-empty. Under Strategy B the note is ONE document whose
/// blocks carry a `pageId`, so strokes must be keyed by pageId instead of
/// page index — this store is that keying.
///
/// Why keyed and never index-remapped: under B, pageIds are minted once and
/// travel with their sheet (`p1` stays `p1` through forward pushes, pulls and
/// even into the pull-generated fresh empty paragraph; pages with ink are
/// never dropped, so no entry is ever stranded). Strategy A's index re-keying
/// on donor removal does not exist here.
///
/// The payload stays the Strategy-A byte shape — `[Sketch.toJson()]` — for
/// two reasons: (1) `NoteDrawingLayer` / `ScribbleNotifier.setSketch` consume
/// it verbatim, so a per-sheet renderer can be added without touching
/// storage; (2) old notes can be mass-migrated by lifting their per-page
/// payloads straight into this map when the Strategy-B note model lands.
///
/// Not persisted as-is: [toJson] flattens to `Map<String, dynamic>` — the
/// Strategy-B note shape is `{document: <single doc>, ink: {pageId: payload}}`.
class PageInkStore extends ChangeNotifier {
  PageInkStore();

  final Map<String, InkPayload> _pages = {};

  /// The Strategy-A ink test, pageId-keyed: true iff the payload holds a
  /// sketch whose `lines` list is non-empty. This is the exact predicate
  /// PagedNoteController._pageHasInk used, so pulled pages, page-removal
  /// decisions and merged ink-threshold rules behave identically under B.
  bool hasInk(String pageId) => _sketchHasLines(_pages[pageId]);

  /// The whole payload for [pageId] — `null` when the page has none yet,
  /// otherwise the `[Sketch.toJson()]` single-element shape
  /// (an inkless page's payload holds a sketch with zero lines).
  InkPayload? inkOf(String pageId) => _pages[pageId];

  /// Replace (or clear, with `null`) the payload for [pageId].
  void setInk(String pageId, InkPayload? payload) {
    if (payload == null) {
      if (_pages.remove(pageId) != null) notifyListeners();
      return;
    }
    if (_sketchHasLines(_pages[pageId]) == _sketchHasLines(payload) &&
        _pages[pageId] == payload) {
      return;
    }
    _pages[pageId] = payload;
    notifyListeners();
  }

  /// Drop [pageId] entirely. Only called when a suite vanishes for good
  /// (page break removed) — never while it is surviving as an inked blank
  /// (that is [hasInk]'s job to keep alive).
  void removeInk(String pageId) {
    if (_pages.remove(pageId) != null) notifyListeners();
  }

  // -- persistence ----------------------------------------------------------

  Map<String, dynamic> toJson() =>
      {for (final e in _pages.entries) e.key: e.value};

  factory PageInkStore.fromJson(Map<String, dynamic> json) {
    final store = PageInkStore();
    for (final e in json.entries) {
      final payload = e.value;
      if (payload is! List) {
        debugPrint('[ink-store] dropping malformed ink entry "${e.key}"');
        continue;
      }
      if (payload.isEmpty) continue;
      store._pages[e.key] = [
        for (final s in payload)
          if (s is Map<String, dynamic>) s,
      ];
    }
    return store;
  }

  // -- sketch payload semantics -----------------------------------------------

  /// A sketch's lines — the ink element of [inkOf], all maps.
  static List<dynamic> sketchLines(InkPayload? payload) {
    if (payload == null || payload.isEmpty) return const [];
    final raw = payload.first;
    final lines = raw['lines'];
    return lines is List ? lines : const [];
  }

  static bool _sketchHasLines(InkPayload? payload) =>
      sketchLines(payload).isNotEmpty;
}
