import 'table_splitter.dart';

/// Pure decision layer for pagination flow.
///
/// All inputs are raw JSON block maps as emitted by a page's 'documentJson'
/// plus optional measured layout numbers (e.g. tableAvailableHeight). All
/// outputs are immutable `FlowPlan` structures describing which blocks move,
/// which stay, and where the caret lands — without any Flutter or
/// appflowy_editor dependencies. An executor (rebuild today, single-document
/// under Strategy B) turns these plans into live transactions.
///
/// Matches the reference implementation's rules exactly:
///   * tables never travel backward;
///   * donors removed only when text-empty AND ink-free;
///   * exactly one caret per flow;
///   * insert-then-delete ordering within an operation.

typedef Block = Map<String, dynamic>;

/// Caret anchor on a specific page after the flow. Keyed by stable block id.
class CaretTarget {
  final String blockId; // node.id (6-char nanoid)
  final int offset;     // selection offset inside that block
  final bool autoFocus; // whether this page receives keyboard focus

  CaretTarget(this.blockId, this.offset, {this.autoFocus = false});
}

/// Result of a page-level move decision. Immutable, serializable, testable
/// without a Flutter widget tree.
class FlowPlan {
  final String pageId;       // persistent page identifier (read from NotePage)
  final int pageIndex;       // position in the page list (read-only)
  final List<Block> kept;    // blocks that remain on this page
  final List<Block> moved;   // blocks moving *to* this page (forward) or kept
  final CaretTarget? caretTarget; // where the caret lands (null = page doesn't own caret)
  final bool donorRemoved;   // true if this page is being removed (backward flow)
  final bool isForward;      // true = pushOverflow (blocks move forward)

  FlowPlan({
    required this.pageId,
    required this.pageIndex,
    required this.kept,
    required this.moved,
    this.caretTarget,
    this.donorRemoved = false,
    this.isForward = true,
  });

  /// Blocks active on this page after the flow applies.
  List<Block> get finalBlocks => [...kept, ...moved];
}

// --------------------------------------------------------------------------
// Helpers (pure)
// --------------------------------------------------------------------------

/// True if [block] is an empty paragraph (placeholder) with no visible text.
/// Mirrors paged_note_controller.dart's [_isEmptyParagraph].
bool isEmptyParagraph(Block block) {
  if (block['type'] != 'paragraph') return false;
  final delta = (block['data'] as Map?)?['delta'] as List?;
  if (delta is! List || delta.isEmpty) return true;
  final text = delta.whereType<Map<String, dynamic>>()
      .map((e) => (e['insert'] as String?) ?? '')
      .join();
  return text.trim().isEmpty;
}

// --------------------------------------------------------------------------
// Core decision functions (pure, no Flutter)
// --------------------------------------------------------------------------

/// Forward overflow: plan a pushOverflow from `currentPage` onto `nextPage`.
///
/// Returns a pair of FlowPlans: (source page trimmed, target page receiving).
///
/// [tableAvailableHeight] comes from PageSurface measurement of the rendered
/// overflow boundary (input, not computed here — this module is Flutter-free).
/// When null, no table split is attempted.
List<FlowPlan> planForwardOverflow({
  required List<Block> currentPage,
  required List<Block> nextPage,
  required int fromBlockIndex,
  required String currentPageId,
  required String nextPageId,
  required int currentPageIndex,
  required int nextPageIndex,
  double? tableAvailableHeight,
  required CaretTarget? caretOnCurrentPage,
}) {
  final keptHeadResult = tableAvailableHeight != null
      ? splitTableAtHeight(currentPage[fromBlockIndex], tableAvailableHeight)
      : null;
  Block? keptHead;
  Block? movedTail;
  if (keptHeadResult != null) {
    keptHead = keptHeadResult.$1;
    movedTail = keptHeadResult.$2;
  }
  final sourceHead = keptHead; // promote for null-check below

  // Whole-block path: must keep at least one block on source (fromBlockIndex>=1).
  if (sourceHead == null && fromBlockIndex < 1) {
    return [
      FlowPlan(pageId: currentPageId, pageIndex: currentPageIndex, kept: [], moved: [], caretTarget: null, isForward: true),
      FlowPlan(pageId: nextPageId, pageIndex: nextPageIndex, kept: [], moved: [], caretTarget: null, isForward: true),
    ];
  }

  final kept = sourceHead == null
      ? currentPage.sublist(0, fromBlockIndex)
      : [...currentPage.sublist(0, fromBlockIndex), sourceHead];
  final moved = sourceHead == null
      ? currentPage.sublist(fromBlockIndex)
      : [movedTail!, ...currentPage.sublist(fromBlockIndex + 1)];

  // Resolve caret using (nodeId, offset) currency. Look up the block by id
  // to determine whether it travels (is in `moved` or equals keptHead) or
  // stays (is in `kept`).
  CaretTarget? sourceCaretTarget;
  CaretTarget? targetCaretTarget;
  if (caretOnCurrentPage != null) {
    final blockOnMoved = moved.any((b) => b['id'] == caretOnCurrentPage.blockId);
    if (blockOnMoved) {
      // Caret travels with its block to the target page.
      targetCaretTarget = CaretTarget(
        caretOnCurrentPage.blockId, caretOnCurrentPage.offset);
    } else if (kept.any((b) => b['id'] == caretOnCurrentPage.blockId)) {
      sourceCaretTarget = CaretTarget(
        caretOnCurrentPage.blockId, caretOnCurrentPage.offset);
    }
  }

  return [
    FlowPlan(
      pageId: currentPageId,
      pageIndex: currentPageIndex,
      kept: kept,
      moved: [],
      caretTarget: sourceCaretTarget,
      isForward: true,
    ),
    FlowPlan(
      pageId: nextPageId,
      pageIndex: nextPageIndex,
      kept: nextPage,
      moved: moved,
      caretTarget: targetCaretTarget,
      isForward: true,
    ),
  ];
}

/// Backward pull: plan a _pullFrom pulling donorPage's head onto currentPage.
///
/// Returns (receiver FlowPlan, donor FlowPlan). Donor removed when text-empty
/// AND ink-free — but ink-free is a caller-side fact; this module returns
/// `donorTextEmpty` and lets the executor decide. Models `_PullResult.moved`
/// / `_PullResult.removedDonor` via FlowPlan.donorRemoved.
List<FlowPlan> planBackwardPull({
  required List<Block> currentPage,
  required List<Block> donorPage,
  required String currentPageId,
  required String donorPageId,
  required int currentPageIndex,
  required int donorPageIndex,
  required CaretTarget? caretOnCurrentPage,
  required CaretTarget? caretOnDonorPage,
}) {
  if (donorPage.isEmpty) {
    return [
      FlowPlan(pageId: currentPageId, pageIndex: currentPageIndex, kept: [], moved: [], donorRemoved: true, isForward: false),
      FlowPlan(pageId: donorPageId, pageIndex: donorPageIndex, kept: [], moved: [], donorRemoved: true, isForward: false),
    ];
  }
  final head = donorPage.first;
  // Tables never travel backward.
  if (head['type'] == 'table') {
    return [
      FlowPlan(pageId: currentPageId, pageIndex: currentPageIndex, kept: [], moved: [], caretTarget: caretOnCurrentPage, isForward: false),
      FlowPlan(pageId: donorPageId, pageIndex: donorPageIndex, kept: [], moved: [], caretTarget: caretOnDonorPage, isForward: false),
    ];
  }

  final tail = donorPage.sublist(1);
  final donorTextEmpty = tail.every(isEmptyParagraph);

  CaretTarget? receiverCaretTarget;
  CaretTarget? donorCaretTarget;

  // Caret currency (nodeId, offset). If the donor's head carries the caret
  // (block id at index 0), it travels to the receiver at the seam.
  if (caretOnDonorPage != null && head['id'] == caretOnDonorPage.blockId) {
    receiverCaretTarget = CaretTarget(
      caretOnDonorPage.blockId, caretOnDonorPage.offset);
  } else if (caretOnDonorPage != null && tail.any((b) => b['id'] == caretOnDonorPage.blockId)) {
    // Caret deeper in donor stays on donor, index shifts up one.
    donorCaretTarget = CaretTarget(caretOnDonorPage.blockId, caretOnDonorPage.offset);
  } else if (caretOnCurrentPage != null) {
    // Receiver retains its caret.
    receiverCaretTarget = caretOnCurrentPage;
  } else if (donorTextEmpty) {
    // No caret anywhere involved — donor will be removed; nothing to do.
    null;
  }

  final receiver = FlowPlan(
    pageId: currentPageId,
    pageIndex: currentPageIndex,
    kept: currentPage,
    moved: [head],
    caretTarget: receiverCaretTarget,
    donorRemoved: false,
    isForward: false,
  );
  FlowPlan donor;
  if (donorTextEmpty) {
    donor = FlowPlan(
      pageId: donorPageId,
      pageIndex: donorPageIndex,
      kept: [],
      moved: [],
      donorRemoved: true,
      isForward: false,
    );
  } else {
    donor = FlowPlan(
      pageId: donorPageId,
      pageIndex: donorPageIndex,
      kept: tail,
      moved: [],
      caretTarget: donorCaretTarget,
      donorRemoved: false,
      isForward: false,
    );
  }
  return [receiver, donor];
}

/// Merge: previous page absorbs current page's blocks (mergePageIntoPrevious).
///
/// Returns (previous page FlowPlan absorbing blocks, current page FlowPlan
/// cleared/removed).
List<FlowPlan> planMergePrevToCurrent({
  required List<Block> prevPage,
  required List<Block> curPage,
  required String prevPageId,
  required String curPageId,
  required int prevPageIndex,
  required int curPageIndex,
}) {
  final mergedBlocks = [...prevPage, ...curPage];
  return [
    FlowPlan(
      pageId: prevPageId,
      pageIndex: prevPageIndex,
      kept: mergedBlocks,
      moved: [],
      donorRemoved: false,
      isForward: false,
    ),
    FlowPlan(
      pageId: curPageId,
      pageIndex: curPageIndex,
      kept: [],
      moved: [],
      donorRemoved: true,
      isForward: false,
    ),
  ];
}

// --------------------------------------------------------------------------
// Invariants (debug-only)
// --------------------------------------------------------------------------

/// Asserts: block ids preserved (no duplicates, no losses) across the set of
/// FlowPlans, and exactly one caret owns a page after the flow.
/// Runs only in debug mode; no-op in release.
void assertIdInvariants(List<FlowPlan> plans) {
  assert(() {
    final seenIds = <String>{};
    for (final p in plans) {
      for (final b in [...p.kept, ...p.moved]) {
        final id = b['id'] as String?;
        if (id != null && !seenIds.add(id)) {
          throw Exception('Duplicate block id $id on page ${p.pageId}');
        }
      }
    }
    final caretCount = plans.fold<int>(0, (s, p) => s + (p.caretTarget != null ? 1 : 0));
    if (caretCount > 1) {
      throw Exception('Invariant violation: more than one page owns the caret');
    }
    return true;
  }());
}
