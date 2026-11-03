import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scribble/scribble.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/note_editor_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/table_splitter.dart';

/// Vertical continuous scroll (default, document feel) vs horizontal PageView
/// (slideshow). Both render the same page widget — see PagedEditor.
enum PageLayoutMode { vertical, horizontal }

/// Outcome of one backward-reflow pull attempt (see PagedNoteController._pullFrom).
enum _PullResult { moved, removedDonor }

/// One page's identity + editing state. Reuses [NoteEditorController] (one
/// AppFlowy document + one ink layer) unchanged — a page IS a single-surface
/// note, so nothing about that class had to move.
class NotePage {
  NotePage({
    required this.pageId,
    required this.pageIndex,
    required this.controller,
  });

  final String pageId;
  final int pageIndex;
  final NoteEditorController controller;
}

/// A note as an ORDERED LIST OF DISCRETE PAGES (Xournal / Samsung-Notes style).
/// Maps 1:1 to the daemon's `NoteStorage.pages`. This class is where all the
/// paged BEHAVIOUR lives, so — because that behaviour is deliberately not what a
/// word processor does — here is why it behaves the way it does:
///
///  * **Pages are discrete, not a reflowing document.** Each page owns its own
///    AppFlowy document + ink layer ([NotePage.controller]). Content does NOT
///    reflow backward to fill a gap, and editing one page never re-lays-out the
///    others. Page ids are therefore stable — nothing auto-splits or renumbers
///    them. (An earlier build DID reflow continuously; it churned page ids into
///    a sparse mess, jumped the caret at boundaries, and fought the daemon's
///    stable-`page_id` versioning/analysis/sync. It was removed on purpose.)
///
///  * **Content flows FORWARD only, when a page fills.** [PageSurface] measures
///    the rendered layout and reports overflow; [pushOverflow] then moves the
///    overflowing tail onto the next page (created if needed) and the caret
///    follows. A TABLE that overflows is SPLIT at a row boundary ([_splitTable],
///    see helpers/table_splitter.dart) — the head stays on this page, the tail
///    flows — which is what keeps a page from ever becoming internally
///    scrollable. Any non-table block taller than a whole sheet just overflows.
///    Backspace at a page's start does the inverse, discretely:
///    [mergePageIntoPrevious] pulls that page's text up into the previous one.
///
///  * **Content also flows BACKWARD, one block at a time, when idle.** After a
///    content change that leaves a page underfull — a font-size change, a
///    delete, a merge — its next page's first block is pulled up so pages stay
///    filled. See [_runReflow] for the policy that keeps this from becoming the
///    continuous reflow that was removed: page ids are stable, donors are only
///    removed when empty AND ink-free, tables never travel backward, and pulls
///    fire only ≥ [_reflowSettle] after the last change.
///
///  * **Every page is a SEPARATE editor, so per-page state doesn't carry itself.**
///    Each page's driver has its own selection AND its own vim mode controller.
///    Cross-page operations rebuild the affected pages' controllers (a page has
///    no cheap way to move blocks into another page's live `EditorState`), and a
///    rebuilt editor starts fresh — which is exactly why [pushOverflow]/merge
///    have to (a) seed the caret onto exactly ONE page (`seedCaret:false` on the
///    other, or you get two visible cursors) and (b) copy the vim mode across
///    (`_applyVimState`, or insert-mode silently drops back to normal). The
///    controller remount is driven by `ObjectKey(controller)` in PagedEditor.
///
///  * **Ink is page-LOCAL and never crosses pages** — merge/overflow move text
///    only; a page's strokes stay with that page's index.
///
///  * **The "active" page is tracked by pointer-down** (PagedEditor's Listener),
///    because the single screen-level drawing dial + undo/redo act on whichever
///    page you last touched, not a page-per-dial.
///
/// Verified with `flutter analyze` + `flutter test` (Flutter SDK is now
/// available; 2026-11-02: 3 pre-existing suite failures live in unrelated
/// test files — due_today_strip, upcoming_engrams, hit_test_pass_through).
class PagedNoteController extends ChangeNotifier {
  PagedNoteController._(this._pages, {required VimModeController sharedVim})
    : _sharedVim = sharedVim {
    for (final p in _pages) {
      _initPage(p);
    }
  }

  /// ONE vim mode for the whole note, shared by every page's driver: vim is
  /// a text modality of the document, not a page property — per-page
  /// instances diverged ("prev page INSERT, next NORMAL") the moment a page
  /// was created or reflowed, because a rebuild re-minted a controller and
  /// the newly-picked side defaulted to normal. Rebuilds now inject this
  /// same instance, so a mode survives page churn and the scaffold's badge
  /// (resolves through every driver's `vimMode`) is one honest signal.
  ///
  /// OWNERSHIP: this controller owns it. Page drivers never dispose an
  /// injected vim controller (see AppFlowyTextDriver._ownsVimMode); it is
  /// disposed exactly once, in [dispose].
  final VimModeController _sharedVim;

  /// The drawing tool (pen colour+width / highlighter / eraser) currently
  /// selected on the single screen-level dial, expressed as a mutation applied
  /// to a page's ink notifier. Null until the user first picks a tool. Stored so
  /// the selection FOLLOWS across pages: it's broadcast to every page on pick
  /// (see [applyDrawingTool]) and applied to any page created afterwards (see
  /// [_initPage]). Undo/redo are NOT tools — they act on the active page only.
  void Function(ScribbleNotifier)? _activeTool;

  /// Select a drawing tool from the dial: remember it and apply it to EVERY
  /// page's ink notifier, so drawing on any page uses it immediately (no
  /// dependence on which page is active, and no pointer-dispatch ordering race).
  void applyDrawingTool(void Function(ScribbleNotifier) config) {
    _activeTool = config;
    for (final p in _pages) {
      config(p.controller.drawingNotifier);
    }
  }

  /// Uploads a picked image and returns the URL to embed. Set by the note
  /// context (EditorScaffold, which knows the bubble + note). Stored so it can
  /// be applied to every page's driver — including pages created later — so the
  /// "/image" slash item works on any page.
  Future<String?> Function(List<int> bytes, String filename)? _imageUploader;

  set imageUploader(
    Future<String?> Function(List<int> bytes, String filename)? uploader,
  ) {
    _imageUploader = uploader;
    for (final p in _pages) {
      final driver = p.controller.driver;
      if (driver is AppFlowyTextDriver) driver.imageUploader = uploader;
    }
  }

  /// Analysis-review-mode chunk stepping, forwarded to every page's driver so
  /// the 'n'/'N' character shortcuts (which live in AppFlowyTextDriver) can
  /// step the chunk cursor. Set by the scaffold from its AnalysisModeController.
  void Function(int delta)? _stepAnalysisChunk;

  set stepAnalysisChunk(void Function(int delta)? step) {
    _stepAnalysisChunk = step;
    for (final p in _pages) {
      final driver = p.controller.driver;
      if (driver is AppFlowyTextDriver) driver.onStepAnalysisChunk = step;
    }
  }

  /// Hook forwarded to every page's driver: called when 'n' is pressed in
  /// NORMAL mode to enter analysis-review mode. The scaffold wires this to
  /// lazy-load the analysis before flipping the mode, so pressing 'n' populates
  /// chunks without having to open the side panel first.
  VoidCallback? _enterAnalysisMode;

  set enterAnalysisMode(VoidCallback? hook) {
    _enterAnalysisMode = hook;
    for (final p in _pages) {
      final driver = p.controller.driver;
      if (driver is AppFlowyTextDriver) driver.onEnterAnalysisMode = hook;
    }
  }

  /// Hook forwarded to every page's driver: called when 'q' is pressed in
  /// NORMAL or ANALYSIS mode to toggle the full analysis panel (the
  /// overview tab). The scaffold wires this to open/close the panel without
  /// changing modes. (Rebound from 'o', which is vim's open-line key now.)
  VoidCallback? _toggleAnalysisPanel;

  set toggleAnalysisPanel(VoidCallback? hook) {
    _toggleAnalysisPanel = hook;
    for (final p in _pages) {
      final driver = p.controller.driver;
      if (driver is AppFlowyTextDriver) driver.onToggleAnalysisPanel = hook;
    }
  }

  /// Wire everything a freshly created page needs: the backspace-at-start merge
  /// and the live-reflow edit trigger. Reused pages (kept as-is across a reflow)
  /// are NOT passed through here — their wiring already stands, and re-adding
  /// the reflow listener would fire it twice per edit.
  void _initPage(NotePage page) {
    _wireMerge(page);
    // A page created after a tool was picked inherits it, so the pen/highlighter
    // /eraser stays consistent on brand-new pages.
    _activeTool?.call(page.controller.drawingNotifier);
    // New pages get the image uploader too, so "/image" works on any page.
    final driver = page.controller.driver;
    if (driver is AppFlowyTextDriver) {
      driver.imageUploader = _imageUploader;
      driver.onStepAnalysisChunk = _stepAnalysisChunk;
      driver.onEnterAnalysisMode = _enterAnalysisMode;
      driver.onToggleAnalysisPanel = _toggleAnalysisPanel;
      // Active-page bookkeeping follows the KEYBOARD: when this page's editor
      // acquires focus (tap, caret hand-off, analysis jump), activeController —
      // which the scaffold resolves the vim badge/toggles through — must point
      // HERE. Without it, a focus gain on a non-active page left the badge and
      // all mode switching bound to the previous page (keyboard in one page,
      // vim mode read from another — the 'mode switcher is tied to the previous
      // page' report).
      driver.onFocusGained = () {
        final idx = _pages.indexOf(page);
        if (idx != -1 && idx != _activeIndex) setActive(idx);
      };
      // Arbitrate shared-vim focus re-assertions: [_activeIndex] is
      // keyboard-following (above) plus pointer-down claims, i.e. "the page
      // the user is working on", so a toolbar mode flip — which fires every
      // page's vim listener at once — must let ONLY this predicate's page
      // [requestEditorFocus]. Identity lookup at call time, so it stays
      // correct as pages are added/removed/merged.
      driver.isKeyboardOwner = () {
        final idx = _pages.indexOf(page);
        return idx != -1 && idx == _activeIndex;
      };
    }
  }

  /// Wire a page's backspace-at-start to merge it into the previous page. The
  /// closure looks the page's index up by identity at call time, so it stays
  /// correct as pages are added/removed/merged.
  void _wireMerge(NotePage page) {
    final driver = page.controller.driver;
    if (driver is AppFlowyTextDriver) {
      driver.onBackspaceAtStart = () {
        final idx = _pages.indexOf(page);
        if (idx <= 0) return false; // first page (or gone): default backspace
        mergePageIntoPrevious(idx);
        return true;
      };
    }
  }

  final List<NotePage> _pages;
  int _activeIndex = 0;
  bool _drawingEnabled = false;

  /// Vim-enabled state per page, captured when drawing turns ON so it can be
  /// restored when drawing turns OFF (see [toggleDrawingMode]).
  final Map<String, bool> _vimEnabledBeforeDrawing = {};
  PageLayoutMode _layout = PageLayoutMode.vertical;

  List<NotePage> get pages => List.unmodifiable(_pages);
  int get activeIndex => _activeIndex;
  bool get drawingEnabled => _drawingEnabled;
  PageLayoutMode get layout => _layout;
  NoteEditorController get activeController => _pages[_activeIndex].controller;

  /// Build from `NoteStorage.pages`; falls back to a single page synthesised
  /// from the legacy `{document, ink}` shape when the note has no pages yet.
  factory PagedNoteController.fromNote({
    List<Map<String, dynamic>>? pages,
    Map<String, dynamic>? legacyDocument,
    List<Map<String, dynamic>>? legacyInk,
  }) {
    final c = PagedNoteController._(
      <NotePage>[],
      sharedVim: VimModeController(),
    );
    c._bootstrap(
      pages: pages,
      legacyDocument: legacyDocument,
      legacyInk: legacyInk,
    );
    return c;
  }

  void _bootstrap({
    List<Map<String, dynamic>>? pages,
    Map<String, dynamic>? legacyDocument,
    List<Map<String, dynamic>>? legacyInk,
  }) {
    if (pages != null && pages.isNotEmpty) {
      for (var i = 0; i < pages.length; i++) {
        final p = pages[i];
        final page = _makePage(
          pageId: (p['page_id'] as String?) ?? 'p$i',
          index: (p['page_index'] as num?)?.toInt() ?? i,
          document: p['document'] as Map<String, dynamic>?,
          ink: _inkOf(p['ink']),
          // The FIRST page owns the caret on open — a freshly opened note
          // must be immediately navigable without a click (nothing in
          // AppFlowy ever requests focus on its own).
          autoFocus: i == 0,
        );
        _pages.add(page);
        _initPage(page);
      }
    } else {
      final page = _makePage(
        pageId: 'p1', // matches the daemon's synthesised first-page id
        index: 0,
        document: legacyDocument,
        ink: legacyInk,
        autoFocus: true,
      );
      _pages.add(page);
      _initPage(page);
    }
    _pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  static List<Map<String, dynamic>>? _inkOf(Object? raw) =>
      raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : null;

  NotePage _makePage({
    required String pageId,
    required int index,
    Map<String, dynamic>? document,
    List<Map<String, dynamic>>? ink,
    int? caretBlockIndex,
    int? caretOffset,
    bool autoFocus = false,
    bool seedCaret = true,
  }) {
    final page = NotePage(
      pageId: pageId,
      pageIndex: index,
      controller: NoteEditorController(
        driver: AppFlowyTextDriver(
          initialDocumentJson: document,
          initialCaretBlockIndex: caretBlockIndex,
          initialCaretOffset: caretOffset,
          seedCaret: seedCaret,
          // Only the auto-focused page applies its seed caret immediately;
          // every other page holds it as a PENDING selection applied on
          // focus gain, so unfocused pages never render a phantom caret.
          ownsCaretSeed: autoFocus,
          // The note's ONE vim mode rides every (re)built page.
          injectedVim: _sharedVim,
        ),
        initialInkJson: ink,
      ),
    );
    // `autoFocus` here means "this page owns the caret": AppFlowy 6.x never
    // focuses its editor by itself (autoFocus only sets a selection), so the
    // request must be explicit. Deferred + re-armed by the driver so it lands
    // even when this page's editor subtree isn't mounted until a later frame.
    if (autoFocus) {
      final d = page.controller.driver;
      if (d is AppFlowyTextDriver) d.requestEditorFocus();
    }
    return page;
  }

  void setActive(int index) {
    if (index < 0 || index >= _pages.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Global draw/text toggle — applies to whichever page you're on.
  void toggleDrawingMode() {
    final enteringDrawing = !_drawingEnabled;
    _drawingEnabled = !_drawingEnabled;

    // Vim mode is a TEXT modality and must not be active while drawing —
    // its markers, shortcuts and analysis state are meaningless over the
    // ink surface. Disable it across every page on the way in, and restore
    // each page's own prior enabled-state on the way out (the text-vs-draw
    // toggle shouldn't silently change the user's vim preference).
    if (enteringDrawing) {
      _vimEnabledBeforeDrawing.clear();
      for (final page in _pages) {
        final d = page.controller.driver;
        if (d is AppFlowyTextDriver) {
          _vimEnabledBeforeDrawing[page.pageId] = d.vimMode.isEnabled;
          d.vimMode.setEnabled(false);
        }
      }
    } else {
      for (final page in _pages) {
        final d = page.controller.driver;
        if (d is AppFlowyTextDriver &&
            _vimEnabledBeforeDrawing[page.pageId] == true) {
          d.vimMode.setEnabled(true);
        }
      }
      _vimEnabledBeforeDrawing.clear();
      // Coming back to text: give the keyboard to the ACTIVE page's editor.
      // Registered AFTER the per-page vim listeners above, so this is the
      // deciding post-frame request (an active-page editor that was never
      // part of the vim broadcast still gets focus).
      final d = _pages[_activeIndex].controller.driver;
      if (d is AppFlowyTextDriver) d.requestEditorFocus();
    }

    notifyListeners();
  }

  void setLayout(PageLayoutMode mode) {
    _layout = mode;
    notifyListeners();
  }

  void toggleLayout() => setLayout(
    _layout == PageLayoutMode.vertical
        ? PageLayoutMode.horizontal
        : PageLayoutMode.vertical,
  );

  /// Next free `p{n}` id: max existing + 1, so a delete-then-add can't collide
  /// with a surviving page's id.
  String _nextPageId() {
    var maxNum = 0;
    for (final p in _pages) {
      final m = RegExp(r'^p(\d+)$').firstMatch(p.pageId);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }
    return 'p${maxNum + 1}';
  }

  void addPage() {
    final idx = _pages.length;
    final page = _makePage(
      pageId: _nextPageId(),
      index: idx,
      document: null,
      ink: null,
    );
    _pages.add(page);
    _initPage(page);
    _activeIndex = idx;
    notifyListeners();
  }

  void removePage(int index) {
    if (_pages.length <= 1 || index < 0 || index >= _pages.length) return;
    _pages.removeAt(index).controller.dispose();
    if (_activeIndex >= _pages.length) _activeIndex = _pages.length - 1;
    notifyListeners();
  }

  /// True while [pushOverflow] is rebuilding pages, so an overflow report that
  /// arrives mid-rebuild is ignored rather than recursing.
  bool _flowing = false;

  /// Forward-only overflow flow: the blocks from [fromBlockIndex] onward on page
  /// [pageIndex] no longer fit the sheet, so move them to the FRONT of the next
  /// page (creating one if this is the last page) and carry the caret with them
  /// so typing continues there.
  ///
  /// When the overflowing block is a TABLE and PageSurface hands us a measured
  /// height budget ([tableAvailableHeight]), the table is SPLIT at a row
  /// boundary instead of moved whole: the head stays on this page, the tail +
  /// following blocks flow. A non-table block moves whole (never splits), so its
  /// caret's (block, offset) maps directly — the moved block's new index is
  /// `oldIndex - fromBlockIndex`. A caret that was inside the split table is
  /// reseated onto this page's head table (cell-level re-seeding isn't
  /// supported — the driver seeds top-level blocks only; selecting the head is
  /// strictly better than no caret at all).
  ///
  /// Existing pages are NOT reflowed by THIS operation; content only ever
  /// moves DOWN here, so it terminates and never churns page ids upward the
  /// way the old continuous pagination did. (The backward counterpart is
  /// [_runReflow] — see that comment for the rules it keeps.) Reported by
  /// PageSurface, which measures the actual rendered block positions against
  /// the sheet.
  void pushOverflow(
    int pageIndex,
    int fromBlockIndex, {
    double? tableAvailableHeight,
  }) {
    if (_flowing || pageIndex < 0 || pageIndex >= _pages.length) return;
    final page = _pages[pageIndex];
    final children = List<Map<String, dynamic>>.from(
      (page.controller.documentJson['children'] as List?) ?? const [],
    );
    if (fromBlockIndex < 0 || fromBlockIndex >= children.length) return;

    // Table path FIRST: split the overflowing table at a row boundary, keeping
    // the rendering head on this page (this is what stops a page from becoming
    // internally scrollable). Falls back to whole-block movement when there is
    // no measured budget (safety) or the block isn't a table.
    Map<String, dynamic>? keptHead;
    Map<String, dynamic>? movedTail;
    if (children[fromBlockIndex]['type'] == 'table' &&
        tableAvailableHeight != null) {
      final split = splitTableAtHeight(
        children[fromBlockIndex],
        tableAvailableHeight,
      );
      if (split != null) {
        keptHead = split.$1;
        movedTail = split.$2;
      }
    }

    // Whole-block path: keep at least one block on this page (fromBlockIndex
    // >= 1); a single non-table block taller than a whole sheet can't be helped
    // without splitting, so leave it. Always allowed for a split table head.
    if (keptHead == null && fromBlockIndex < 1) return;

    _flowing = true;

    final kept =
        keptHead == null
            ? children.sublist(0, fromBlockIndex)
            : [...children.sublist(0, fromBlockIndex), keptHead];
    final moved =
        keptHead == null
            ? children.sublist(fromBlockIndex)
            : [movedTail!, ...children.sublist(fromBlockIndex + 1)];
    debugPrint(
      '[flow] push p$pageIndex from=$fromBlockIndex '
      'head=${children[fromBlockIndex]['type']} '
      'moved=${moved.map((e) => e['type']).toList()}',
    );

    // Capture the source page's caret AND vim mode before we tear it down.
    int? srcCaretBlock;
    int? srcCaretOffset;
    bool? wasInsert; // null → source page wasn't the active/vim-aware one
    var wasVimEnabled = true;
    var reseatedTableCaret = false;
    final driver = page.controller.driver;
    if (_activeIndex == pageIndex && driver is AppFlowyTextDriver) {
      final caret = driver.caret;
      if (caret != null && caret.path.length == 1) {
        srcCaretBlock = caret.path.first;
        srcCaretOffset = caret.offset;
      } else if (keptHead != null && caret?.path.first == fromBlockIndex) {
        // Caret inside the split table → reseat onto this page's head table.
        reseatedTableCaret = true;
        srcCaretBlock = fromBlockIndex;
        srcCaretOffset = 0;
      }
      wasInsert = driver.vimMode.isInsert;
      wasVimEnabled = driver.vimMode.isEnabled;
    }
    // Does the caret sit in a block that's moving? Then it travels to the next
    // page; otherwise it stays on this (trimmed) page — EXCEPT a caret reseated
    // onto the head table, which always stays put. Exactly ONE page gets a
    // caret — the other passes seedCaret:false so no second cursor lingers.
    final caretMoved =
        !reseatedTableCaret &&
        srcCaretBlock != null &&
        srcCaretBlock >= fromBlockIndex;
    final targetCaretBlock =
        caretMoved ? srcCaretBlock - fromBlockIndex : null; // index in `moved`

    // Rebuild this page with just the kept blocks (its ink stays). It holds the
    // caret only if the caret stayed here.
    final trimmed = _makePage(
      pageId: page.pageId,
      index: pageIndex,
      document: {'type': 'page', 'children': kept},
      ink: page.controller.inkJson,
      caretBlockIndex: caretMoved ? null : srcCaretBlock,
      caretOffset: caretMoved ? null : srcCaretOffset,
      autoFocus: !caretMoved && srcCaretBlock != null,
      seedCaret: false,
    );
    page.controller.dispose();
    _pages[pageIndex] = trimmed;
    _initPage(trimmed);

    late final NotePage target;
    if (pageIndex + 1 < _pages.length) {
      // Prepend the moved blocks to the existing next page (may cascade — that
      // page will report its own overflow next frame if it now doesn't fit).
      final next = _pages[pageIndex + 1];
      final nextChildren = List<Map<String, dynamic>>.from(
        (next.controller.documentJson['children'] as List?) ?? const [],
      );
      target = _makePage(
        pageId: next.pageId,
        index: pageIndex + 1,
        document: {
          'type': 'page',
          'children': [...moved, ...nextChildren],
        },
        ink: next.controller.inkJson,
        caretBlockIndex: targetCaretBlock,
        caretOffset: caretMoved ? srcCaretOffset : null,
        autoFocus: caretMoved,
        seedCaret: false,
      );
      next.controller.dispose();
      _pages[pageIndex + 1] = target;
    } else {
      // Last page overflowed → spill onto a fresh page.
      target = _makePage(
        pageId: _nextPageId(),
        index: pageIndex + 1,
        document: {'type': 'page', 'children': moved},
        ink: null,
        caretBlockIndex: targetCaretBlock,
        caretOffset: caretMoved ? srcCaretOffset : null,
        autoFocus: caretMoved,
        seedCaret: false,
      );
      _pages.add(target);
    }
    _initPage(target);

    // Vim mode is per-page (each driver owns a VimModeController that defaults to
    // normal), so a rebuild would silently drop you back to normal. Carry the
    // mode onto both rebuilt pages so typing keeps going in insert across the
    // page boundary. (Each `_applyVimState` fires that page's vim-listener,
    // whose focus re-assert request would RACE — the explicit request below,
    // registered after both, decides the winner.)
    if (wasInsert != null) {
      _applyVimState(trimmed, insert: wasInsert, enabled: wasVimEnabled);
      _applyVimState(target, insert: wasInsert, enabled: wasVimEnabled);
    }

    // Focus the page that OWNS the caret after the flow: the target when the
    // caret moved, the trimmed source when it stayed (or was reseated onto the
    // head table). Registered LAST so it is the deciding post-frame request.
    final focusDriver =
        caretMoved
            ? target.controller.driver
            : (srcCaretBlock != null ? trimmed.controller.driver : null);
    if (focusDriver is AppFlowyTextDriver) focusDriver.requestEditorFocus();

    if (caretMoved) _activeIndex = pageIndex + 1;
    _flowing = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Backward reflow: pages pull the next page's head block up when idle.
  //
  // Goal: after ANY content change that leaves a page underfull — a smaller
  // kBaseFontSize, a delete, a paragraph merge — text flows UP so pages stay
  // filled, the mirror image of pushOverflow. The rules below keep this from
  // becoming the continuous reflow that was deliberately removed (it churned
  // page ids into a sparse mess, jumped the caret at boundaries, and fought
  // the daemon's stable page_id/analysis versioning):
  //
  //  * PAGE IDS never churn. The receiver keeps its id; the donor keeps its
  //    id and is only removed when it is out of text AND holds no ink — the
  //    same rule mergePageIntoPrevious applies, so a page with ink is never
  //    destroyed by reflow.
  //  * BLOCK GRANULARITY: one block moves per measured page-pair per sweep,
  //    based on real rendered heights (not estimates). The next sweep pulls
  //    again until fit stops.
  //  * TABLES never travel backward: the forward splitter's halves are
  //    terminal states; table re-merging is a different (unbuildable) move.
  //    A donor whose head is a table is simply skipped, forever.
  //  * IDLE-GATED: pulls fire only >= _reflowSettle after the last content
  //    change. Every measurement re-arms that settle, and [notifyListeners]
  //    (any content change) invalidates the measured snapshot — so nothing
  //    ever remounts beneath a keystroke, and vim/focus hand-off mirrors
  //    pushOverflow's exactly-one-caret rule.
  //  * MEASURED IN DOCUMENT UNITS: PageSurface reports how much room the
  //    receiver has below its last block (freeHeight) and how tall the
  //    donor's first block is (headHeight). Because every page lays out at
  //    the same canonical width, a head block's height is identical on both
  //    sides of the move — no cross-page estimation is involved.
  //  * MOUNTED PAGES ONLY: the outer ListView builds a cache window, so a
  //    long note reflows as its pages come on screen (scrolling heals the
  //    rest). This is the deliberate trade for never measuring an unmounted
  //    editor.
  //
  //  Fit-margin note: a pull must leave >= _pullFitMargin spare room, more
  //  than the forward check's tolerance, so a post-pull overflow report can
  //  never evict the same block right back down (which would yo-yo).
  // ---------------------------------------------------------------------------

  /// Idle time after the last measured change before a backward pull fires.
  /// Long enough that typing (every keystroke re-arms the settle from the
  /// fresh surface report) never sees a pull mid-sentence, short enough to
  /// feel automatic.
  static const Duration _reflowSettle = Duration(milliseconds: 600);

  /// Document-pixel spare room a donor head must clear on the receiver.
  /// Deliberately > the forward check's 0.5 tolerance: pull placement is
  /// then provably non-overflowing, so the same block can never ping-pong.
  static const double _pullFitMargin = 8.0;

  // Pull sweeps cap defensively against pathological loops; 200 is far past
  // any sane note (200 pulls would move 200 blocks in one sweep).
  static const int _pullSweepCap = 200;

  /// Latest per-page fill report from each mounted PageSurface: how much
  /// document space is free below the last block, and how tall the page's
  /// first block is. Cleared on every controller notify and every pull, so a
  /// decision is never built on a stale layout.
  final Map<int, ({double? freeHeight, double? headHeight})> _fillStats = {};

  Timer? _reflowTimer;

  /// Called by PageSurface after each laid-out frame for a MOUNTED page: the
  /// document-units free space below the block stack, and the height of this
  /// page's own first block (which is what a PREVIOUS page may pull up).
  /// Silent — reporting must not notify, or this loop feeds itself.
  void onPageMeasured(int pageIndex, double? freeHeight, double? headHeight) {
    if (_flowing || pageIndex < 0 || pageIndex >= _pages.length) return;
    if (freeHeight == null || freeHeight <= 0) return; // can't receive
    _fillStats[pageIndex] = (freeHeight: freeHeight, headHeight: headHeight);
    _reflowTimer?.cancel();
    _reflowTimer = Timer(_reflowSettle, () {
      _reflowTimer = null;
      _runPullSweep();
    });
  }

  /// Any controller change invalidates pending reflow decisions: the stats
  /// describe a layout that may no longer exist. The next post-frame reports
  /// re-populate within a frame either way.
  @override
  void notifyListeners() {
    _fillStats.clear();
    _reflowTimer?.cancel();
    _reflowTimer = null;
    super.notifyListeners();
  }

  /// One idle-settle sweep: pull every eligible (receiver, donor) pair,
  /// ascending. Process-order matters — page i's donation to i-1 frees MORE
  /// space on i, which i uses to receive from i+1 later in the same sweep,
  /// so a cascade converges in one sweep rather than waiting one settle per
  /// page. Fit is tracked in-memory between pulls (receiver shrinks by the
  /// head it just took; donor grows because its content shifted up) and
  /// re-measured on the next frame for the next sweep.
  void _runPullSweep() {
    if (_flowing) return;
    _flowing = true;
    var pulls = 0;
    try {
      for (var i = 0; i + 1 < _pages.length && pulls < _pullSweepCap; i++) {
        final stats = _fillStats[i];
        final donorStats = _fillStats[i + 1];
        final head = donorStats?.headHeight;
        final free = stats?.freeHeight;
        if (stats == null || donorStats == null) continue;
        if (free == null || head == null) continue; // unmeasured side
        if (free < head + _pullFitMargin) continue;
        final result = _pullFrom(i);
        if (result == null) continue;
        pulls++;
        if (result == _PullResult.removedDonor) {
          // The donor is gone: page indices past it shifted by one, so the
          // in-memory stats keyed by index are now pointing one page down.
          // Drop the donor's slot and re-key everything above it — the sweep
          // can then keep cascading with correct pairings.
          final removedAt = i + 1;
          final values = <int, ({double? freeHeight, double? headHeight})>{};
          _fillStats.forEach((key, value) {
            if (key == removedAt) return;
            values[key > removedAt ? key - 1 : key] = value;
          });
          _fillStats
            ..clear()
            ..addAll(values);
        }
        // In-memory bookkeeping until the next measured frame — the sweep
        // uses updated numbers instead of re-laying-out between pulls. The
        // head heights are leveled to null because a moved block changes who
        // the donor's head IS; only a fresh measurement knows its height.
        final nextStats = _fillStats[i + 1];
        _fillStats[i] = (
          freeHeight: (free - head).clamp(0.0, double.infinity),
          headHeight: null, // receiver's head changed; re-measure next sweep
        );
        if (nextStats != null && result == _PullResult.moved) {
          _fillStats[i + 1] = (
            freeHeight: (nextStats.freeHeight ?? 0) + head,
            headHeight: null, // new head is the donor's former second block
          );
        }
      }
    } finally {
      _flowing = false;
      _fillStats.clear();
    }
    if (pulls > 0) notifyListeners();
  }

  /// Move the next page's first block onto page [pageIndex]'s tail. Mirrors
  /// [pushOverflow]'s rebuild/caret/vim machinery. Returns nothing:
  ///  * null = no move (no donor, table head, guard failed),
  ///  * [._PullResult.moved] = the head pulled up,
  ///  * [._PullResult.removedDonor] = the donor drained (it was empty text
  ///    + inkless → page break removed; see mergePageIntoPrevious for why).
  _PullResult? _pullFrom(int pageIndex) {
    final page = _pages[pageIndex];
    final next = _pages[pageIndex + 1];
    if (pageIndex >= _pages.length - 1 || _pages.length < 2) return null;

    final doc = page.controller.documentJson;
    final nextDoc = next.controller.documentJson;
    final children = List<Map<String, dynamic>>.from(
      (doc['children'] as List?) ?? const [],
    );
    final nextChildren = List<Map<String, dynamic>>.from(
      (nextDoc['children'] as List?) ?? const [],
    );
    if (nextChildren.isEmpty) return null;
    final head = nextChildren.first;
    if ((head as Map?)?['type'] == 'table') return null; // see sweep comment
    debugPrint(
      '[flow] pull p$pageIndex head=${head['type']} '
      'level=${((head['data'] as Map?)?['level'])} '
      'donorNext=${nextChildren.map((e) => e['type']).toList()}',
    );

    // State capture BEFORE tearing pages down. Only the ACTIVE page has a
    // canonical selection — AppFlowy nulls the selection of every unfocused
    // page — so the receiver/donor caret is read exactly once below, from the
    // side that is active, if either.
    final donorDriver = next.controller.driver;
    final receiverDriver = page.controller.driver;
    final donorIsActive = _activeIndex == pageIndex + 1;
    final receiverIsActive = _activeIndex == pageIndex;
    final activeDriver =
        donorIsActive
            ? donorDriver
            : receiverIsActive
            ? receiverDriver
            : null;
    final donorCaret =
        donorIsActive && donorDriver is AppFlowyTextDriver
            ? donorDriver.caret
            : null;
    final receiverCaret =
        receiverIsActive && receiverDriver is AppFlowyTextDriver
            ? receiverDriver.caret
            : null;
    bool? wasInsert;
    var wasVimEnabled = true;
    if (activeDriver is AppFlowyTextDriver) {
      wasInsert = activeDriver.vimMode.isInsert;
      wasVimEnabled = activeDriver.vimMode.isEnabled;
    }

    // How the caret hands off. Block-0 carets are IN the head, so they travel
    // with it to the receiver's seam; deeper donor carets just shift up one
    // index. Nested paths (table cells) can't be reseeded sub-block, so they
    // reseat at block level like pushOverflow does at the seam.
    var caretOnReceiver = false;
    var caretStaysOnDonor = false;
    int? donorCaretOffset;
    if (donorCaret != null) {
      final donorBlock =
          donorCaret.path.length == 1 ? donorCaret.path.first : null;
      if (donorBlock == 0) {
        caretOnReceiver = true;
        donorCaretOffset = donorCaret.path.length == 1 ? donorCaret.offset : 0;
      } else if (donorBlock != null && donorBlock > 0) {
        caretStaysOnDonor = true;
        donorCaretOffset = donorCaret.offset;
      }
      // donorCaret == null (no selection) → no caret hand-off at all.
    }

    // RECEIVER rebuild: drop a trailing empty paragraph filler first (mirror
    // of mergePageIntoPrevious) so pulling into the seam doesn't strand a
    // blank line — UNLESS the receiver's caret lives in that filler, which
    // would mis-seed it on the head instead.
    final recvChildren = [...children];
    final lastIdx = recvChildren.length - 1;
    final receiverInTrailingFiller =
        receiverCaret != null &&
        receiverCaret.path.length == 1 &&
        receiverCaret.path.first == lastIdx &&
        lastIdx > 0 &&
        _isEmptyParagraph(recvChildren.last);
    if (!receiverInTrailingFiller &&
        recvChildren.length > 1 &&
        _isEmptyParagraph(recvChildren.last)) {
      recvChildren.removeLast();
    }
    final seamIndex = recvChildren.length;

    // Receiver caret targets:
    //  - donor's head carries the caret (block 0) → reseed at the seam, same
    //    offset.
    //  - receiver was already active → reseed at the SAME (block, offset);
    //    the trailing-filler drop is skipped above, so the index is untouched.
    //  - nested receiver caret → block-level reseat, offset 0.
    //  - otherwise the page rebuilds caret-less (it held no selection anyway).
    int? recvCaretBlock;
    int? recvCaretOffset;
    var recvAutoFocus = false;
    if (caretOnReceiver) {
      recvCaretBlock = seamIndex;
      recvCaretOffset = donorCaretOffset;
      recvAutoFocus = true;
    } else if (receiverCaret != null) {
      recvCaretBlock =
          receiverCaret.path.length == 1
              ? receiverCaret.path.first
              : receiverCaret.path.first;
      recvCaretOffset =
          receiverCaret.path.length == 1 ? receiverCaret.offset : 0;
      recvAutoFocus = true;
    }

    final newReceiver = _makePage(
      pageId: page.pageId,
      index: pageIndex,
      document: {
        'type': 'page',
        'children': [...recvChildren, head],
      },
      ink: page.controller.inkJson,
      caretBlockIndex: recvCaretBlock,
      caretOffset: recvCaretOffset,
      autoFocus: recvAutoFocus,
      seedCaret: false,
    );
    debugPrint(
      '[flow] pull rebuilt receiver=$pageIndex ${(newReceiver.controller.documentJson['children'] as List).map((e) => e['type']).toList()}',
    );
    page.controller.dispose();
    _pages[pageIndex] = newReceiver;
    _initPage(newReceiver);
    // DONOR rebuild: what's left after the head. When every remaining block
    // is an empty paragraph the donor is text-empty — keep it only if it
    // holds ink, else drop it (page break removed; ids beyond shift down).
    // `rest.every(...)` covers the empty case too ([].every is true), so one
    // check stands for "nothing with text remains".
    final rest = nextChildren.sublist(1);
    final donorTextEmpty = rest.every(_isEmptyParagraph);
    var donorRemoved = false;
    if (donorTextEmpty) {
      if (_pageHasInk(next)) {
        // Ink is page-local and never moves: keep this page, now empty of
        // text, holding its strokes.
        final emptied = _makePage(
          pageId: next.pageId,
          index: pageIndex + 1,
          document: _emptyDoc(),
          ink: next.controller.inkJson,
        );
        next.controller.dispose();
        _pages[pageIndex + 1] = emptied;
        _initPage(emptied);
      } else {
        next.controller.dispose();
        _pages.removeAt(pageIndex + 1);
        donorRemoved = true;
      }
    } else {
      // Donor keeps its remaining blocks; its caret shifts up one index with
      // the head's departure, offset preserved. Nested carets were already
      // resolved to a (block, 0) reseat above.
      final donor = _makePage(
        pageId: next.pageId,
        index: pageIndex + 1,
        document: {'type': 'page', 'children': rest},
        ink: next.controller.inkJson,
        caretBlockIndex: caretStaysOnDonor
            ? (donorCaret!.path.first - 1)
            : null,
        caretOffset: caretStaysOnDonor ? donorCaretOffset : null,
        autoFocus: caretStaysOnDonor,
        seedCaret: false,
      );
      debugPrint(
        '[flow] pull donor rebuilt=$pageIndex ${(donor.controller.documentJson['children'] as List).map((e) => e['type']).toList()}',
      );
      next.controller.dispose();
      _pages[pageIndex + 1] = donor;
      _initPage(donor);
    }

    // Vim: copy only when one of the two pages held THE canonical mode — a
    // rebuild silently resets to normal, which would drop you out of insert.
    if (wasInsert != null) {
      _applyVimState(newReceiver, insert: wasInsert, enabled: wasVimEnabled);
      if (!donorRemoved) {
        _applyVimState(
          _pages[pageIndex + 1],
          insert: wasInsert,
          enabled: wasVimEnabled,
        );
      }
    }

    // Active-page bookkeeping + focus. Exactly ONE page owns the caret after
    // the pull:
    //  * caret travelled with the head → receiver is active and focused;
    //  * caret stayed on the donor → donor is active and focused;
    //  * receiver was already active (its caret reseeded) → still active;
    //  * donor removed while holding the caret → receiver gets focus (the
    //    driver revives the caret at its first block; the vanished block was
    //    the head's filler anyway). Not a caret seed — just the keyboard.
    // Registered last so it is the deciding post-frame request (each
    // _applyVimState also fires that page's vim focus re-assert).
    if (caretStaysOnDonor && !donorRemoved) {
      _activeIndex = pageIndex + 1;
      final d = _pages[pageIndex + 1].controller.driver;
      if (d is AppFlowyTextDriver) d.requestEditorFocus();
    } else if (caretOnReceiver ||
        receiverCaret != null ||
        (donorRemoved && donorIsActive)) {
      _activeIndex = pageIndex;
      final d = _pages[pageIndex].controller.driver;
      if (d is AppFlowyTextDriver) d.requestEditorFocus();
    }
    return _PullResult.moved;
  }

  /// Copy vim mode (enabled + normal/insert) onto a rebuilt page's driver.
  ///
  /// Largely vestigial since vim became a note-level SHARED controller (every
  /// rebuilt driver injects `_sharedVim`, so the mode never resets across
  /// rebuilds at all). Kept so the idempotent re-assertion still covers the
  /// not-yet-injected case and because entering insert (rather than just
  /// being in it) matters to any listeners that keyed off the transition.
  void _applyVimState(
    NotePage page, {
    required bool insert,
    required bool enabled,
  }) {
    final d = page.controller.driver;
    if (d is! AppFlowyTextDriver) return;
    d.vimMode.setEnabled(enabled);
    if (insert) {
      d.vimMode.enterInsertMode();
    } else {
      d.vimMode.enterNormalMode();
    }
  }

  /// Backspace at the very start of page [index] pulls only its TYPED CONTENT up
  /// into the end of the previous page. Text and ink are separate layers:
  ///
  ///   * text (the document blocks) moves up to the previous page; the caret
  ///     lands at the seam;
  ///   * ink NEVER moves — strokes are page-local and only the ink tools (eraser)
  ///     may remove them;
  ///   * the emptied page is removed ONLY if it has no ink. If it still holds
  ///     ink, the page stays (now text-empty) so backspace can't destroy ink.
  void mergePageIntoPrevious(int index) {
    if (index <= 0 || index >= _pages.length) return;
    final prev = _pages[index - 1];
    final cur = _pages[index];

    final prevDoc = Map<String, dynamic>.from(prev.controller.documentJson);
    final curDoc = cur.controller.documentJson;
    final prevChildren = List<Map<String, dynamic>>.from(
      (prevDoc['children'] as List?) ?? const [],
    );
    final curChildren = List<Map<String, dynamic>>.from(
      (curDoc['children'] as List?) ?? const [],
    );

    // Drop a single trailing empty paragraph on the previous page so the seam
    // isn't a stray blank line (pages often end on an empty block).
    if (prevChildren.length > 1 && _isEmptyParagraph(prevChildren.last)) {
      prevChildren.removeLast();
    }
    final seamIndex = prevChildren.length; // caret lands at first merged block
    final mergedDoc = {
      ...prevDoc,
      'children': [...prevChildren, ...curChildren],
    };
    debugPrint('[flow] merge p$index-1->$index prev=${prevChildren.map((e)=>e['type']).toList()} cur=${curChildren.map((e)=>e['type']).toList()} merged=${(mergedDoc['children'] as List).map((e)=>e['type']).toList()}');

    // Rebuild the PREVIOUS page with the merged text. Its OWN ink is passed back
    // through untouched — ink is never combined across pages.
    final newPrev = _makePage(
      pageId: prev.pageId,
      index: index - 1,
      document: mergedDoc,
      ink: prev.controller.inkJson,
      caretBlockIndex: seamIndex,
      autoFocus: true,
    );
    prev.controller.dispose();
    _pages[index - 1] = newPrev;
    _initPage(newPrev);

    if (_pageHasInk(cur)) {
      // Ink stays page-local: keep this page, just clear its now-moved text.
      final emptied = _makePage(
        pageId: cur.pageId,
        index: index,
        document: _emptyDoc(),
        ink: cur.controller.inkJson,
      );
      cur.controller.dispose();
      _pages[index] = emptied;
      _initPage(emptied);
    } else {
      // No ink → nothing left on the page, so the page break is removed.
      cur.controller.dispose();
      _pages.removeAt(index);
    }

    _activeIndex = index - 1;
    notifyListeners();
  }

  static bool _isEmptyParagraph(Map<String, dynamic> block) {
    if (block['type'] != 'paragraph') return false;
    final delta = (block['data'] as Map?)?['delta'];
    if (delta is! List || delta.isEmpty) return true;
    final text =
        delta
            .whereType<Map>()
            .map((e) => (e['insert'] ?? '').toString())
            .join();
    return text.isEmpty;
  }

  /// True if the page has any ink strokes. `inkJson` is a single-element list
  /// holding one `Sketch.toJson()` (`{lines: [...]}`).
  static bool _pageHasInk(NotePage page) {
    final ink = page.controller.inkJson;
    if (ink.isEmpty) return false;
    final lines = (ink.first['lines'] as List?) ?? const [];
    return lines.isNotEmpty;
  }

  static Map<String, dynamic> _emptyDoc() => {
    'type': 'page',
    'children': [
      {
        'type': 'paragraph',
        'data': {
          'delta': [
            {'insert': ''},
          ],
        },
      },
    ],
  };

  /// Serialise to the `NoteStorage.pages` shape for save/sync.
  List<Map<String, dynamic>> toPagesJson() => [
    for (var i = 0; i < _pages.length; i++)
      {
        'page_id': _pages[i].pageId,
        'page_index': i,
        'document': _pages[i].controller.documentJson,
        'ink': _pages[i].controller.inkJson,
      },
  ];

  @override
  void dispose() {
    _reflowTimer?.cancel();
    for (final p in _pages) {
      p.controller.dispose();
    }
    // The shared vim controller is owned here, not by any page driver, so it
    // is disposed exactly once — after every page driver is gone.
    _sharedVim.dispose();
    super.dispose();
  }
}
