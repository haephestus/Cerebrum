import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:cerebrum/ui/screens/editor/helpers/flow_decision.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_runs.dart';
import 'package:cerebrum/ui/screens/editor/helpers/table_splitter.dart';

/// Strategy B feature flag: single-document pagination.
///
/// When true, the `'page'` block renders through [PageBlockComponentBuilder]
/// and overflow/backward-reflow run through [FlowTransactionExecutor]
/// against ONE EditorState (the note is a single document; sheets are just
/// runs of `pageId`-tagged blocks). The Strategy-B note model
/// (fromNote/toPagesJson over one document + the page-local ink map) has
/// landed behind this flag — legacy A-shape notes migrate in-memory on
/// open and persist in B shape on save (see `strategy_b_notes.dart`; the
/// sync contract reconciles the page-set shrink server-side).
const bool kUseSingleDocumentPagination = true;

/// Spare document-pixel room a pulled head must clear on the receiver —
/// deliberately greater than the forward check's 0.5 tolerance so a
/// post-pull overflow report can never evict the same block straight back
/// down (mirrors PagedNoteController._pullFitMargin).
const double _defaultPullFitMargin = 8.0;

typedef FlowBlock = Map<String, dynamic>;

/// The Strategy-B flow executor: turns measurement reports into
/// [FlowPlan]s through the decision layer (helpers/flow_decision.dart) and
/// applies each plan as ONE transaction on the one live EditorState.
///
/// Transaction shape is the spike's proven splice (two_sheet_spike_test
/// criterion 2): insert clones (identity preserved, `deepCopy: false` —
/// otherwise the package deep-copies and minted nanoids replace ours),
/// delete originals, `recordUndo: false`, caret follows its block.
///
/// Playback facts this is built on (verified against appflowy_editor 6.0.0
/// sources — editor_state.dart `_applyTransactionInLocal`,
/// document.dart `insert`/`delete`, transaction.dart):
///  * operations play IN ORDER against the live tree; playback is
///    PATH-based, never node-identity-based (`deleteNode(node)` snapshots
///    `node.path` eagerly at op-add time);
///  * `document.insert(path, nodes)` inserts BEFORE the path occupant; a
///    path == child count appends at the end;
///  * therefore: every DELETE path must be correct at its play time —
///    deletes are issued in DESCENDING original-index order (each plays
///    against a tree in which only higher original indices were removed),
///    and all INSERT paths are computed against the post-delete tree;
///  * clones are built with `Node(type:, id:, attributes:, children:)` —
///    the constructor stamps `id` verbatim. `Node.fromJson` MINTS a fresh
///    id and must not be used (§0's identity finding, re-proved for
///    Strategy B).
///
/// Rules mirrored from Strategy A's controller:
///  * exactly one caret after every flow — the planner decides; when the
///    caret's block is gone (removed text-empty ink-free donor tail) the
///    selection is simply left unset;
///  * flow splices are suppressed from undo;
///  * tables never travel backward (the forward splitter's halves are
///    terminal; a split table's halves never re-merge);
///  * a drained donor is dropped only when text-empty AND ink-free
///    ([pageHasInk]) — an inked donor keeps one empty paragraph tagged
///    with its OWN pageId so its sheet (and its ink) survives;
///  * after ANY applied move the cached fill stats are discarded; the
///    next measured frame re-reports (the `_fillStats.clear()` rule).
class FlowTransactionExecutor {
  FlowTransactionExecutor({
    required this.editorState,
    required this.pageHasInk,
    this.pullFitMargin = _defaultPullFitMargin,
    this.settle = const Duration(milliseconds: 600),
  });

  final EditorState editorState;

  /// Whether [pageId] holds ink strokes. Page-local ink is NOT part of the
  /// Strategy-B document — the per-pageId Scribble lookup belongs to the
  /// not-yet-landed note-model phase; driver wiring passes `(_) => false`
  /// until then, which is honest: with no ink stored anywhere, a drained
  /// donor may be removed.
  final bool Function(String pageId) pageHasInk;

  final double pullFitMargin;

  /// Idle time after the last underfill report before a backward pull
  /// sweeps (Strategy A's `_reflowSettle`). Tests pass [Duration.zero].
  final Duration settle;

  bool _busy = false;

  /// Tests disable the settle-driven sweep so pending timers never leak;
  /// pulls remain invocable through [debugSweep]. Production is unchanged
  /// at its default (enabled).
  bool _sweepsEnabled = true;

  Timer? _settleTimer;

  /// Per-sheet fill stats keyed by pageId. Strategy A keyed by list index
  /// and re-keyed on every donor removal; under Strategy B the pageId IS
  /// the stable key. Cleared after every applied move, sweep, and push.
  final Map<String, ({double free, double? head})> _stats = {};

  void dispose() {
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  // -- measurement in -------------------------------------------------------

  /// Forward overflow report (the page block's per-sheet measurement): the
  /// first GLOBAL top-level block no longer fitting its sheet's bottom.
  /// [tableAvailableHeight] is the measured budget the overflowing table
  /// head may keep on that sheet; whole-block moves ignore it.
  ///
  /// One move per report — the re-measure next frame drives the cascade.
  void onOverflow(
    String fromPageId,
    int fromBlockIndex, {
    double? tableAvailableHeight,
  }) {
    if (_busy) return;
    _busy = true;
    try {
      _push(fromBlockIndex, tableAvailableHeight);
    } finally {
      _stats.clear();
      _busy = false;
    }
  }

  /// Backward underfill report: [freeHeight] spare room below [pageId]'s
  /// last block, [headBlockHeight] that page's OWN first block (what a
  /// PREVIOUS page would receive pulling from here). Silent — nothing
  /// notifies, or this loop feeds itself.
  void onUnderfill(String pageId, double freeHeight, double? headBlockHeight) {
    if (_busy) return;
    // A full page reports no free space — but still legitimately reports
    // its own head-block height (what it would donate upward). Store the
    // pair either way; only an entry with NEITHER value is worthless.
    if (freeHeight <= 0) {
      if (headBlockHeight == null) {
        _stats.remove(pageId);
      } else {
        _stats[pageId] = (free: 0, head: headBlockHeight);
      }
      return;
    }
    _stats[pageId] = (free: freeHeight, head: headBlockHeight);
    // Tests disable sweeps to keep pending timers out of the fixture;
    // [debugSweep] applies the stored stats regardless.
    if (!_sweepsEnabled) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, _settleSweep);
  }

  // -- test hooks -----------------------------------------------------------

  /// Enable/disable the settle-driven sweep (tests: pending-timer hygiene).
  /// [debugSweep] still works either way — the flag gates ONLY the timer.
  void debugDisableSweeps({required bool disable}) => _sweepsEnabled = !disable;

  /// Run one backward-pull sweep now (tests).
  void debugSweep() => _sweep();

  // -- forward push ---------------------------------------------------------

  void _push(int fromBlockIndex, double? tableBudget) {
    final children = _children();
    if (fromBlockIndex < 0 || fromBlockIndex >= children.length) return;
    final runs = groupRunsByPageId(children);
    if (runs.isEmpty) return;

    var srcRunIdx = -1;
    for (final (i, r) in runs.indexed) {
      if (fromBlockIndex >= r.start &&
          fromBlockIndex < r.start + r.nodes.length) {
        srcRunIdx = i;
        break;
      }
    }
    if (srcRunIdx < 0) return;
    final srcRun = runs[srcRunIdx];
    final srcRunEnd = srcRun.start + srcRun.nodes.length;
    final sourceBlockNode = children[fromBlockIndex];
    final sourceBlockId = sourceBlockNode.id;
    final localFromOrig = fromBlockIndex - srcRun.start;

    // GEOMETRY FIRST: when the overflow block is a table WITH a measured
    // budget, split it at a row boundary BEFORE planning. The head half
    // replaces the source block and KEEPS its id (net in-place replacement:
    // the original node is deleted in the same transaction); the tail half
    // joins the moved blocks with a FRESH id (the splitter deep-clones the
    // source — both halves would otherwise carry the source's id). The
    // decision layer then plans the move of everything from the tail
    // onward, so identity/ownership still flows exclusively through
    // planForwardOverflow.
    var srcJson = [for (final n in srcRun.nodes) _blockJson(n)];
    var moveFromLocal = localFromOrig;
    var splitReseat = false;
    FlowBlock? splitHeadJson;
    if (sourceBlockNode.type == 'table' && tableBudget != null) {
      final split = splitTableAtHeight(srcJson[localFromOrig], tableBudget);
      if (split != null) {
        final (head, tail) = split;
        tail.remove('id'); // original keeps its id; the tail half is new
        srcJson = [
          ...srcJson.sublist(0, localFromOrig),
          head,
          tail,
          ...srcJson.sublist(localFromOrig + 1),
        ];
        splitHeadJson = head;
        moveFromLocal++;
        if (_caret()?.blockId == sourceBlockId) splitReseat = true;
      }
    }

    final targetRun =
        srcRunIdx + 1 < runs.length ? runs[srcRunIdx + 1] : null;
    final freshTarget = targetRun == null;
    final targetPageId = freshTarget ? _nextPageId(runs) : targetRun.pageId;
    final nextJson = freshTarget
        ? <FlowBlock>[]
        : [for (final n in targetRun.nodes) _blockJson(n)];

    // Caret input for the planner — only when the caret lives in the
    // SOURCE run (the planner resolves targets by id inside kept/moved; a
    // caret anywhere else has no basis to move). A split under the caret
    // reseats it onto the head half at offset 0 — Strategy A's rule:
    // cell-level reseed isn't supported; selecting the head is strictly
    // better than a lost caret.
    final rawCaret = _caret();
    final caretIsOnSrc =
        rawCaret != null && srcJson.any((b) => b['id'] == rawCaret.blockId);
    final planCaret = !caretIsOnSrc
        ? null
        : (splitReseat
            ? CaretTarget(rawCaret.blockId, 0)
            : CaretTarget(rawCaret.blockId, rawCaret.offset));

    final plans = planForwardOverflow(
      currentPage: srcJson,
      nextPage: nextJson,
      fromBlockIndex: moveFromLocal,
      currentPageId: srcRun.pageId,
      nextPageId: targetPageId,
      currentPageIndex: srcRun.start,
      nextPageIndex: freshTarget ? srcRunEnd : targetRun.start,
      caretOnCurrentPage: planCaret,
      // The split ran above — the planner sees pure whole-block moves.
      tableAvailableHeight: null,
    );

    assertIdInvariants(plans);
    final srcPlan = plans.first;
    final targetPlan = plans.last;
    // No-op plan (guard-failed: nothing to keep, nothing to move).
    if (srcPlan.kept.isEmpty &&
        srcPlan.moved.isEmpty &&
        targetPlan.kept.isEmpty &&
        targetPlan.moved.isEmpty) {
      return;
    }

    for (final b in targetPlan.moved) {
      final data = (b['data'] as Map?) ?? <String, dynamic>{};
      data['pageId'] = targetPageId;
      if ((b['data'] as Map?) == null) b['data'] = data;
    }

    // Transaction.add TRANSFORMS every later op against the ops already
    // recorded (insert at s shifts later paths ≥ s up by len; delete at d
    // shifts later paths > d down). Record order IS playback order, so the
    // only correct shape for a splice is INSERTS FIRST — their paths are
    // plain original indices landing before the original occupant — then
    // DELETES, whose paths stay original indices and are auto-shifted
    // (+insert count, then −1 per prior delete) to be right at play time.
    // (Delete-then-insert made the package shift the insert down a second
    // time: probe measured [t0, t2, t1] for what should be [t0, t1, t2].)
    final tx = editorState.transaction;
    final headClone =
        splitHeadJson != null ? _materialize(splitHeadJson) : null;
    final movedClones = [
      for (final b in targetPlan.moved) _materialize(b),
    ];
    final inserts = <Node>[
      if (headClone != null) headClone,
      ...movedClones,
    ];
    if (inserts.isNotEmpty) {
      tx.insertNodes([fromBlockIndex], inserts, deepCopy: false);
    }
    // DELETE the source-run suffix second, DESCENDING (original indices).
    for (var o = srcRunEnd - 1; o >= fromBlockIndex; o--) {
      tx.deleteNodesAtPath([o], 1);
    }

    // Caret follow: resolved by scanning the ARRANGEMENT this transaction
    // produces — no index arithmetic, the plan may not be split-aware.
    if (rawCaret != null) {
      final arrangement = <Node>[
        ...children.sublist(0, fromBlockIndex),
        if (headClone != null) headClone,
        ...movedClones,
        if (!freshTarget) ...targetRun.nodes,
        ...children.sublist(srcRunEnd),
      ];
      int? caretIdx;
      var caretOffset = rawCaret.offset;
      if (splitReseat) {
        caretIdx = fromBlockIndex; // reseat onto the in-place head half
        caretOffset = 0;
      } else {
        caretIdx = _indexOfId(arrangement, rawCaret.blockId);
      }
      if (caretIdx != null) {
        tx.afterSelection = Selection.collapsed(
          Position(path: [caretIdx], offset: caretOffset),
        );
      }
      // Caret not found (removed block): leave the selection untouched.
    }

    unawaited(
      editorState.apply(tx, options: const ApplyOptions(recordUndo: false)),
    );
    debugPrint(
      '[flow-b] push @$fromBlockIndex '
      'moved=${movedClones.map((n) => n.id).toList()} '
      'splitHead=${headClone?.id ?? '-'} target=$targetPageId',
    );
  }

  // -- backward pull --------------------------------------------------------

  /// Settle timer's callback: fires only when sweeps are enabled; the
  /// gated variant keeps [debugSweep] usable with sweeps disabled.
  void _settleSweep() {
    if (_sweepsEnabled) _sweep();
  }

  void _sweep() {
    _settleTimer = null;
    if (_busy) return;
    _busy = true;
    var pulled = false;
    try {
      pulled = _pullOnce();
    } finally {
      _stats.clear();
      _busy = false;
    }
    if (pulled) debugPrint('[flow-b] pull applied');
  }

  /// Try the first eligible (receiver, donor) pair; ONE pull per sweep.
  /// Cascades converge across sweeps as fresh measurements arrive.
  bool _pullOnce() {
    final children = _children();
    final runs = groupRunsByPageId(children);
    for (var i = 0; i + 1 < runs.length; i++) {
      final recv = runs[i];
      final donor = runs[i + 1];
      final recvStats = _stats[recv.pageId];
      final donorStats = _stats[donor.pageId];
      final head = donorStats?.head;
      if (recvStats == null || donorStats == null || head == null) continue;
      if (recvStats.free < head + pullFitMargin) continue;
      // Tables never travel backward — the forward splitter's output is
      // terminal (Strategy A rule, unchanged).
      if (donor.nodes.first.type == 'table') continue;
      // Inked donor reduced to a BLANK page: pulling its empty para up
      // swaps one filler for another regenerated filler — nothing
      // constructive moves and the pair re-fires every settle cycle
      // (the stats are re-published each measured frame with no decay).
      // Skip it; the sheet is kept purely for its ink. An UNinked blank
      // donor stays pull-eligible — that pull REMOVES the page break.
      if (donor.nodes.length == 1 &&
          _isEmptyNode(donor.nodes.first) &&
          pageHasInk(donor.pageId)) {
        continue;
      }
      return _applyPull(recv, donor, children);
    }
    return false;
  }

  bool _applyPull(PageRun recv, PageRun donor, List<Node> children) {
    final recvStart = recv.start;
    final recvEnd = recvStart + recv.nodes.length; // == donor.start
    final donorStart = donor.start;
    final donorEnd = donorStart + donor.nodes.length;
    final donorNodes = donor.nodes;

    final rawCaret = _caret();

    // RECEIVER drop rule (mirrors Strategy A's `_pullFrom`): the receiver's
    // trailing empty paragraph is dropped so the pulled head doesn't land
    // behind a blank line — unless the caret lives in that filler.
    var recvKept = recv.nodes;
    if (recvKept.length > 1 &&
        _isEmptyNode(recvKept.last) &&
        !(rawCaret != null && rawCaret.blockId == recvKept.last.id)) {
      recvKept = recvKept.sublist(0, recvKept.length - 1);
    }

    final recvJson = [for (final n in recvKept) _blockJson(n)];
    final donorJson = [for (final n in donorNodes) _blockJson(n)];
    final caretOnRecv =
        rawCaret != null && recvKept.any((n) => n.id == rawCaret.blockId)
            ? CaretTarget(rawCaret.blockId, rawCaret.offset)
            : null;
    final caretOnDonor =
        rawCaret != null && donorNodes.any((n) => n.id == rawCaret.blockId)
            ? CaretTarget(rawCaret.blockId, rawCaret.offset)
            : null;

    final plans = planBackwardPull(
      currentPage: recvJson,
      donorPage: donorJson,
      currentPageId: recv.pageId,
      donorPageId: donor.pageId,
      currentPageIndex: recvStart,
      donorPageIndex: donorStart,
      caretOnCurrentPage: caretOnRecv,
      caretOnDonorPage: caretOnDonor,
    );
    assertIdInvariants(plans);
    final recvPlan = plans.first;
    final donorPlan = plans.last;
    // No head to move (planner no-op) — nothing to apply.
    if (recvPlan.moved.isEmpty) return false;

    // Relabel: the head becomes property of the RECEIVER's page.
    final headJson = donorJson.first;
    final headDataMap = (headJson['data'] as Map?);
    final headData = headDataMap ?? <String, dynamic>{};
    headData['pageId'] = recv.pageId;
    if (headDataMap == null) headJson['data'] = headData;

    // DELETE accounting for the donor run (descending ops below):
    //   kept donor        → only the head leaves; the tail stays;
    //   removed, no ink   → the whole run goes (page break removed);
    //   removed, ink, tail paras exist → the head and every tail para
    //     except the LAST stay deleted (the survivor, tagged with the
    //     donor pageId, keeps the sheet);
    //   removed, ink, no tail (run == head only) → only the head para is
    //     deleted; a fresh empty paragraph (tagged donor.pageId) is
    //     inserted in its place. The head is ALWAYS among the deletes —
    //     a clone was inserted for it, so leaving the original would
    //     double the paragraph.
    final hasInk = pageHasInk(donor.pageId);
    var donorRemoved = donorPlan.donorRemoved;
    var donorDeleteCount = 0;
    var freshInkPara = false;
    Node? freshParaNode;
    if (donorRemoved && hasInk) {
      donorRemoved = false; // inked donor survives as an empty page
      if (donorNodes.length > 1) {
        donorDeleteCount = donorNodes.length - 1;
      } else {
        donorDeleteCount = 1;
        freshInkPara = true;
        freshParaNode = Node(
          type: 'paragraph',
          attributes: <String, dynamic>{
            'delta': [
              const {'insert': ''},
            ],
            'pageId': donor.pageId,
          },
        );
      }
    } else if (donorRemoved) {
      donorDeleteCount = donorNodes.length;
    } else {
      donorDeleteCount = 1; // just the head
    }

    final tx = editorState.transaction;
    // INSERTS FIRST (see _push for the transform mechanics): one op, paths
    // in original coordinates. The seam lands before the ORIGINAL occupant
    // at [recvStart + recvKept.length] — the receiver filler (if not
    // dropped) or the donor head. The fresh ink paragraph follows the head
    // in the same op so the head always precedes it.
    final seam = recvStart + recvKept.length;
    final inserts = <Node>[
      _materialize(headJson),
      if (freshInkPara && freshParaNode != null) freshParaNode,
    ];
    tx.insertNodes([seam], inserts, deepCopy: false);
    // Deletes second, path = ORIGINAL indices: the donor drop region as a
    // descending chain first, then the receiver's dropped filler (its
    // original index precedes the donor region) LAST — each op is
    // auto-transformed, and a lower-index delete is normalized against the
    // higher-index ones recorded before it.
    for (var o = donorStart + donorDeleteCount - 1; o >= donorStart; o--) {
      tx.deleteNodesAtPath([o], 1);
    }
    final recvDropped = recv.nodes.length - recvKept.length;
    if (recvDropped > 0) {
      tx.deleteNodesAtPath([recvEnd - 1], 1);
    }

    // One caret, plan-decided: scan the ARRANGEMENT this transaction
    // produces for the caret's block id.
    if (rawCaret != null) {
      // Arrangement (order matters): prefix origs, receiver kept origs,
      // head clone, fresh ink para, donor remainder, later origs. The
      // fresh ink para is emitted as the same node instance inserted above.
      final arrangement = <Node>[
        ...children.sublist(0, recvStart),
        ...recvKept,
        inserts.first, // the head clone — first node of the insert op
        if (freshInkPara && freshParaNode != null) freshParaNode,
        // Everything the donor deletes skipped over survives, in place.
        if (!donorRemoved)
          for (final n in donorNodes.skip(donorDeleteCount)) n,
        ...children.sublist(donorEnd),
      ];
      final caretIdx = _indexOfId(arrangement, rawCaret.blockId);
      if (caretIdx != null) {
        tx.afterSelection = Selection.collapsed(
          Position(path: [caretIdx], offset: rawCaret.offset),
        );
      }
      // Caret inside a REMOVED tail (text-empty, ink-free) → its block
      // is gone; leave the selection unset (the caret is revived on the
      // next focus, like Strategy A's donor-removal path).
    }

    unawaited(
      editorState.apply(tx, options: const ApplyOptions(recordUndo: false)),
    );
    debugPrint(
      '[flow-b] pull ${recv.pageId}<-${donor.pageId} seam=$seam '
      'donorRemoved=$donorRemoved '
      'keptInk=${hasInk && !donorPlan.donorRemoved}',
    );
    return true;
  }

  // -- shared helpers -------------------------------------------------------

  List<Node> _children() => editorState.document.root.children.toList();

  /// The caret in the decision layer's (blockId, offset) currency, or null
  /// when there is none, or when it sits in nested content — nested paths
  /// are not reseeded at sub-block level (Strategy A parity).
  CaretTarget? _caret() {
    final sel = editorState.selection;
    if (sel == null) return null;
    final cursor = sel.end;
    if (cursor.path.length != 1) return null;
    final children = editorState.document.root.children;
    if (cursor.path.first >= children.length) return null;
    return CaretTarget(children[cursor.path.first].id, cursor.offset);
  }

  /// Serialize a live node (and its whole subtree) to the shape the
  /// decision layer plans on — toJson plus a restored `id` at every level,
  /// identical to the app's documentJson getter / the spike's nodeWithId.
  FlowBlock _blockJson(Node node) {
    final map = Map<String, dynamic>.from(node.toJson());
    map['id'] = node.id;
    final kids = node.children;
    if (kids.isNotEmpty) {
      map['children'] = [for (final c in kids) _blockJson(c)];
    }
    return map;
  }

  /// Rebuild a Node (recursively) from planner JSON. Passes `id:` straight
  /// into the constructor — an absent or blank id mints a FRESH nanoid
  /// (the split-tail case). `Node.fromJson` is NOT used: it discards ids.
  Node _materialize(FlowBlock json) {
    final childJson = (json['children'] as List?) ?? const <dynamic>[];
    final children = <Node>[
      for (final c in childJson)
        if (c is Map<String, dynamic>) _materialize(Map.from(c)),
    ];
    final id = json['id'];
    final attrs = json['data'];
    return Node(
      type: json['type'] as String,
      id: id is String && id.isNotEmpty ? id : null,
      attributes: attrs is Map<String, dynamic> ? attrs : const <String, dynamic>{},
      children: children,
    );
  }

  int? _indexOfId(List<Node> nodes, String id) {
    for (final (i, n) in nodes.indexed) {
      if (n.id == id) return i;
    }
    return null;
  }

  /// True if the node is an empty paragraph — the live-node twin of
  /// Strategy A's `_isEmptyParagraph` (plaintext emptiness, not op count).
  bool _isEmptyNode(Node node) {
    if (node.type != 'paragraph') return false;
    final delta = node.delta;
    if (delta == null) return true;
    return delta.toPlainText().isEmpty;
  }

  /// Next free `p{n}` id: max existing + 1 (a delete-then-add can't
  /// collide with a surviving page's id — the controller's rule).
  String _nextPageId(List<PageRun> runs) {
    var maxNum = 0;
    for (final r in runs) {
      final m = RegExp(r'^p(\d+)$').firstMatch(r.pageId);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }
    return 'p${maxNum + 1}';
  }
}
