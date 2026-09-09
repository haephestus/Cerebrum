import 'package:flutter/foundation.dart';

/// One reviewable analysis chunk, flattened for navigation. A chunk covers a
/// *set* of blocks (its `source_block_ids`) on one page, so selecting a chunk
/// selects that whole group.
@immutable
class AnalysisChunkRef {
  const AnalysisChunkRef({
    required this.chunkId,
    required this.pageId,
    required this.blockIds,
    required this.chunk,
  });

  final String chunkId;
  final String pageId;

  /// Stable block ids this chunk's analysis covers (may be several).
  final List<String> blockIds;

  /// The raw chunk payload (excerpt + findings), as built by
  /// EditorScaffold._flattenAndSortChunks — passed straight through so a
  /// reviewer widget can render it without re-deriving anything.
  final Map<String, dynamic> chunk;
}

/// SCAFFOLD — drives the vim "analysis" review mode (see [VimMode.analysis]).
///
/// Holds the ordered list of analysis chunks and a cursor into it, and exposes
/// step/jump actions plus two escape hatches the surrounding UI wires up:
///   * [onFocusChunk]  — "reveal" the current chunk (scroll to / highlight its
///                       blocks and/or show its popover). LEFT AS A TODO for the
///                       caller; the controller only tracks *which* chunk.
///   * [onOpenFullPanel] — "opt to see the full analysis" — open the side panel.
///
/// Intentionally UI-agnostic and page-agnostic: it knows chunk order and the
/// current index, nothing about widgets, so it can be unit-tested and re-wired.
class AnalysisModeController extends ChangeNotifier {
  List<AnalysisChunkRef> _chunks = const [];
  int _index = -1;

  /// Called whenever the selected chunk changes (step/jump/setChunks landing on
  /// a chunk). TODO(analysis-mode): wire this to scroll to + highlight the
  /// chunk's blocks and/or surface its popover.
  void Function(AnalysisChunkRef ref)? onFocusChunk;

  /// Called by [openFullPanel] — the UI opens the full analysis side panel.
  VoidCallback? onOpenFullPanel;

  List<AnalysisChunkRef> get chunks => _chunks;
  int get index => _index;
  int get count => _chunks.length;
  bool get hasChunks => _chunks.isNotEmpty;

  AnalysisChunkRef? get current =>
      (_index >= 0 && _index < _chunks.length) ? _chunks[_index] : null;

  /// Replace the chunk set (e.g. after analysis (re)loads). Keeps the cursor on
  /// the same chunkId if it still exists, else resets to the first chunk.
  void setChunks(List<AnalysisChunkRef> chunks) {
    final priorId = current?.chunkId;
    _chunks = List.unmodifiable(chunks);
    _index = _chunks.isEmpty
        ? -1
        : (priorId == null
            ? 0
            : _chunks.indexWhere((c) => c.chunkId == priorId).clamp(0, _chunks.length - 1));
    notifyListeners();
    _emitFocus();
  }

  void next() => _moveTo(_index + 1);
  void prev() => _moveTo(_index - 1);
  void jumpTo(int i) => _moveTo(i);

  /// Opt out of step-through and open the full analysis panel instead.
  void openFullPanel() => onOpenFullPanel?.call();

  void clear() {
    _chunks = const [];
    _index = -1;
    notifyListeners();
  }

  void _moveTo(int i) {
    if (_chunks.isEmpty) return;
    final next = i.clamp(0, _chunks.length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
    _emitFocus();
  }

  void _emitFocus() {
    final c = current;
    if (c != null) onFocusChunk?.call(c);
  }
}
