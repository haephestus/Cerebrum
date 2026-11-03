import 'dart:convert' show jsonDecode, jsonEncode;

/// Strategy-B note codec: ONE document with `pageId`-stamped top-level
/// blocks, ink stored as `{pageId: [Sketch.toJson()]}`.
///
/// Why this shape exists. The Strategy-A note is a LIST of page documents,
/// each pairing one document with one ink sketch,
/// `{page_id, page_index, document, ink}`; the daemon syncs the list with
/// per-page LWW. Strategy B changes the granularity to ONE document whose
/// top-level children carry a `pageId` — sheets are rendered from runs of
/// same-pageId blocks. To keep the EXISTING save pipeline intact (local
/// write → markDirty → outbox push), a B note is written as a ONE-ELEMENT
/// pages list — `{page_id: 'main', page_index: 0, document, ink}` — so
/// callers never deal with two shapes and the sync's per-page rules
/// collapse to "one LWW key."
///
/// The codecs load EITHER shape:
///   * B shape: the single entry's `ink` is a `pageId`-to-payload map and
///     the document children carry pageId attributes.
///   * Legacy shape: a LIST of page entries (any length) whose `ink` is
///     the single-sketch list — this migrates to ONE document whose
///     children get pageId = the legacy page_id, and ink moves into the
///     map. Empty pages are dropped textually but kept as runs so ink
///     (an inked blank page) survives.
///
/// Migration losslessness rules:
///   * ids of blocks are PRESERVED (re-minting would orphan every image
///     ref, every ink coordinate — nothing about a note's content is
///     tied to page INDEX, only to block id and pageId);
///   * the legacy `ink` payload (already `[Sketch.toJson()]`) is copied
///     verbatim under the page's page_id;
///   * a legacy page with an empty delta paragraph and no ink still keeps
///     its empty paragraph so caret navigation feels identical to A.
///
/// Not attempted here: content reconciliation semantics for a daemon-merged
/// B note — that is deliberately a separate decision (semantic merge of
/// the one document vs. mixed formats per page) and is not made in code
/// without the storage contracts it concerns.

class StrategyBNotation {
  const StrategyBNotation({
    required this.document,
    required this.ink,
  });

  /// The ONE document — a `'page'` root whose children carry `pageId`.
  final Map<String, dynamic> document;

  /// `{pageId: [Sketch.toJson()]}` — ink never moves; it is attached to
  /// pageIds and survives all text flows under Strategy B.
  final InkMap ink;

  /// The ONE-ELEMENT pages list the existing save pipeline consumes.
  List<Map<String, dynamic>> toPages() => [
        {
          'page_id': 'main',
          'page_index': 0,
          'document': document,
          'ink': ink,
        },
      ];
}

typedef InkMap = Map<String, List<Map<String, dynamic>>>;

/// True when [pages] is already in Strategy-B shape (one entry whose `ink`
/// is a Map — the distinguishing trait from the legacy list-of-sketch
/// shape). False means a legacy note that needs migration.
bool isBShape(List<Map<String, dynamic>> pages) =>
    pages.length == 1 && pages[0]['ink'] is Map;

/// Decode a persisted pages list into B's single-document + ink map.
///
/// Accepts B shape (returns verbatim values, no deep copies — callers get
/// the parsed containers) and legacy shape (migrates, deep-copies, see the
/// library doc for the losslessness rules).
///
/// Throws [ArgumentError] when the input is not a usable pages list or an
/// A-shape note with no usable page.
StrategyBNotation fromPages(List<Map<String, dynamic>> pages) {
  if (pages.isEmpty) {
    throw ArgumentError('fromPages: empty pages list');
  }

  if (isBShape(pages)) {
    final entry = pages[0];
    final document = _documentOf(entry);
    final ink = _bInkOf(entry['ink'] as Map);
    if (!_isPaged(document)) {
      throw ArgumentError(
          'fromPages: B-shape entry does not hold a paged document');
    }
    return StrategyBNotation(document: document, ink: ink);
  }

  // Legacy migration: stamp each legacy page's blocks with that page's
  // page_id and join the runs in original order.
  final children = <dynamic>[];
  final ink = <String, List<Map<String, dynamic>>>{};
  for (final entry in pages) {
    final pageId = _pageIdOf(entry);
    final document = _documentOf(entry);
    if (!_isPaged(document)) {
      throw ArgumentError(
          'fromPages: legacy entry $pageId does not hold a document');
    }
    for (final child in (document['children'] as List<dynamic>)) {
      if (child is! Map) continue;
      // Deep-copy through JSON: storage round-trips can produce undertyped
      // nested maps (inferred from literals), and the nested maps are not
      // assignable through a typed cast — everything going through here
      // genuinely is JSON-safe, so this normalises it to plain
      // Map<String, dynamic>.
      final block = jsonDecode(jsonEncode(child)) as Map<String, dynamic>;
      final data = (block['data'] as Map?) ?? <String, dynamic>{};
      data['pageId'] = pageId;
      block['data'] = data;
      children.add(block);
    }
    final legacyInk = entry['ink'];
    if (legacyInk is List && legacyInk.isNotEmpty) {
      ink[pageId] = [
        for (final s in legacyInk)
          if (s is Map<String, dynamic>) s else if (s is Map) Map<String, dynamic>.from(s),
      ];
    }
  }
  final note = StrategyBNotation(
    document: {
      'type': 'page',
      'children': children,
    },
    ink: ink,
  );
  return note;
}

/// Convenience: decode + re-encode a legacy note to canonical B shape.
List<Map<String, dynamic>> migrateToB(List<Map<String, dynamic>> pages) =>
    fromPages(pages).toPages();

Map<String, dynamic> _documentOf(Map<String, dynamic> entry) {
  final raw = entry['document'];
  if (raw is String) {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  throw ArgumentError('fromPages: entry has no usable document');
}

String _pageIdOf(Map<String, dynamic> entry) {
  final raw = entry['page_id'];
  if (raw is String && raw.isNotEmpty) return raw;
  throw ArgumentError('fromPages: legacy entry has no page_id');
}

InkMap _bInkOf(Map map) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final e in map.entries) {
    final key = e.key;
    if (key is! String || key.isEmpty) continue;
    final raw = e.value;
    if (raw is! List || raw.isEmpty) continue;
    final sketches = <Map<String, dynamic>>[];
    for (final s in raw) {
      if (s is Map<String, dynamic>) {
        sketches.add(s);
      } else if (s is Map) {
        sketches.add(Map<String, dynamic>.from(s));
      }
    }
    if (sketches.isNotEmpty) out[key] = sketches;
  }
  return out;
}

bool _isPaged(Map<String, dynamic> document) =>
    document['type'] == 'page' && document['children'] is List;
