import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart';
import 'package:cerebrum/ui/screens/editor/helpers/greek_letters.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/text_editing_driver.dart';
// NEW: the proper code block builder (syntax highlighting, language
// switcher, copy button) — path assumes you saved it at
// features/editor/blocks/code_block/code_block_component.dart; adjust
// to wherever you actually put the file.
import 'package:cerebrum/ui/screens/editor/blocks/code_block/code_block_component.dart';
import 'package:cerebrum/ui/screens/editor/blocks/ai_block/ai_block_component.dart';
import 'package:cerebrum/ui/screens/editor/blocks/equation/equation_block_component.dart';
// The table fork: registered against the stock 'table' type to REPLACE the
// package builder. It caps table growth against the sheet and reports enough
// geometry for the row-level overflow split (see blocks/table/README.md).
import 'package:cerebrum/ui/screens/editor/blocks/table/table_block_component.dart';
// Canonical document-space constants: the editor is laid out at a FIXED size
// (inside a PageSurface page) and view zoom is applied around it, so these
// values are constants — no environment-derived scaling may re-enter here.
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_list_icons.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_slash_menu.dart';
// Fork of the stock paragraph block + AppFlowyRichText. Fixes the empty-delta
// caret impostor (14pt unstyled root → 16.3px caret on empty rows). The fork
// is described at the adjustTextSpan override in paged_fork/paged_rich_text.dart.
import 'package:cerebrum/ui/screens/editor/widgets/paged_fork/paged_paragraph_block_component.dart';

/// AppFlowy-backed [TextEditingDriver]. This is the only file that should
/// import `appflowy_editor` — everything above it (NoteEditorController,
/// EditorSurface, EditorScaffold) works against the interface, not this.
class AppFlowyTextDriver extends ChangeNotifier
    implements TextEditingDriver, VimModeAware {
  AppFlowyTextDriver({
    Map<String, dynamic>? initialDocumentJson,
    int? initialCaretBlockIndex,
    int? initialCaretOffset,
    bool seedCaret = true,

    /// True ONLY for the page designated to own the caret right now (the
    /// auto-focused opening page). With this false the seeded caret is held
    /// as a pending selection and applied on focus gain — an unfocused,
    /// never-touched page must not render a caret (phantom caret fix).
    this.ownsCaretSeed = false,

    /// Injected shared vim controller (see PagedNoteController): vim is a
    /// TEXT MODALITY, not a page property — "prev page INSERT, next NORMAL"
    /// was per-page vim instances diverging. Null builds a private one so
    /// standalone driver instantiations (tests, engine swaps) keep working.
    VimModeController? injectedVim,
  }) : vimMode = injectedVim ?? VimModeController(),
       // Only a controller THIS driver created may be disposed by it. An
       // injected one is owned by PagedNoteController and shared by every
       // page; disposing it from a page's dispose() killed it on the first
       // page rebuild ("VimModeController was used after being disposed").
       _ownsVimMode = injectedVim == null {
    _editorState = _buildEditorState(
      initialDocumentJson,
      initialCaretBlockIndex,
      initialCaretOffset,
      seedCaret,
    );
    // shrinkWrap: true → AppFlowyEditor lays the document out as a Column with
    // NO internal scroll view. Required when the editor is embedded inside
    // another scrollable (the paged editor stacks one editor per page inside a
    // ListView): a default (non-shrinkWrap) controller builds a
    // ScrollablePositionedList whose selection service can't find its
    // EditorScrollController provider once nested — the
    // "Could not find the correct Provider<EditorScrollController>" crash seen
    // on multi-page notes. Built once and reused across every buildEditor call.
    _scrollController = EditorScrollController(
      editorState: _editorState,
      shrinkWrap: true,
    );
    _transactionSub = _editorState.transactionStream.listen(
      (_) => notifyListeners(),
    );
    // [caret-debug] TEMP — print caret rect heights per selection change.
    _editorState.selectionNotifier.addListener(_debugCaretMetrics);
    // Narrow highlight-clear listener: when this page's vim mode LEAVES
    // analysis-review mode, drop the chunk highlight so it can't linger on
    // the document after you Esc back to normal/insert. This is deliberately
    // NOT `vimMode.addListener(notifyListeners)` (see the comment below) — it
    // only fires the clear when the mode actually leaves analysis, and the
    // clear itself is a real transaction AppFlowy already rebuilds for.
    vimMode.addListener(_onVimModeChanged);
    // Revive the caret when the editor regains keyboard focus. AppFlowy nulls
    // `editorState.selection` whenever this page's editor LOSES focus
    // (KeyboardServiceWidget._onFocusChanged) and never restores it on gain,
    // so a focused-but-selectionless editor looks exactly like the "page lost
    // focus" bug: no caret, and every vim motion guards on selection == null.
    // Focus listener: on GAIN revive/restore the caret and publish the gain to
    // the paged controller (active-page bookkeeping follows the keyboard); on
    // LOSS remember then clear the visual caret so an unfocused page never
    // keeps one. See _onFocusNodeChanged for why AppFlowy's own keyboard
    // service also nulls on loss and why drawing-mode flips stay exempt.
    editorFocusNode.addListener(_onFocusNodeChanged);
    // PHANTOM CARET: a page that is seeded with a caret but NOT designated to
    // own it keeps that selection until focus crosses it some day, and an
    // unfocused editor still RENDERS its selection as a caret — which is how
    // two pages ended up showing two carets that "competed for focus". Caret
    // seeding is withdrawn into a pending selection applied on focus gain.
    if (seedCaret && !ownsCaretSeed) {
      _pendingCaret = _editorState.selection;
      _editorState.selection = null;
    }
    // NOTE: deliberately NOT `vimMode.addListener(notifyListeners)` here.
    // EditorSurface's mode badge already listens to `vimMode` directly
    // (its own narrowly-scoped AnimatedBuilder), so forwarding vimMode
    // changes into this driver's notifyListeners was redundant — and
    // actively harmful: it fired a full-stack rebuild (recreating
    // AppFlowyEditor via EditorSurface's outer AnimatedBuilder, plus a
    // whole-scaffold setState via EditorScaffold._onEditorChanged) at
    // the exact moment vim mode changes, e.g. right when 'i' switches
    // normal -> insert. That rebuild landing right on top of the very
    // next keystroke's own transaction-triggered rebuild is what was
    // dropping the caret and eating the following keystroke — plain
    // click-to-focus typing never touches vimMode, so it never hit this
    // double-rebuild collision. It also meant toggling modes alone (no
    // actual edit) was incorrectly marking the note as having unsaved
    // changes via EditorScaffold's autosave scheduling.
  }

  late final EditorState _editorState;
  late final EditorScrollController _scrollController;
  late final StreamSubscription<dynamic> _transactionSub;
  late bool _wasInAnalysis = false;

  /// Whether this driver created [vimMode] itself (and therefore must dispose
  /// it). False when the controller was injected and is shared across pages.
  final bool _ownsVimMode;

  /// Keyboard focus for this page's editor, owned by the DRIVER (not the
  /// package): AppFlowy 6.x only focuses its keyboard-service node on a tap,
  /// and its `autoFocus:` flag merely SETS A SELECTION — it never requests
  /// focus. So the editor can only gain the keyboard through this node +
  /// [requestEditorFocus]; without it a note opens / a mode flips with no
  /// caret and the user has to click to navigate. Passed to AppFlowyEditor's
  /// `focusNode:` so the keyboard service uses THIS node and taps focus it.
  final FocusNode editorFocusNode = FocusNode(
    debugLabel: 'cerebrum-page-editor',
  );

  /// True when this page is designated to apply its seed caret immediately
  /// (the auto-focused opening page); all other pages pend it for focus gain.
  final bool ownsCaretSeed;

  /// The seeded caret held back by the phantom-caret fix (see the constructor)
  /// and applied the moment this editor acquires keyboard focus. Null once
  /// applied/superseded; paths are validated before applying because reflows
  /// may have moved blocks after seeding.
  Selection? _pendingCaret;

  /// The last selection this editor held before it lost focus. AppFlowy nulls
  /// the selection on focus loss and never restores it, so without this the
  /// only thing left on regain was [_reviveDefaultCaret] (first block) — the
  /// "caret jumps to the top of the page after the cursor leaves the screen"
  /// bug. On regain this is fed through [_applyPendingCaret], which validates
  /// the path and clamps the offset against the current document.
  Selection? _lastKnownCaret;

  /// Notified when this page's editor ACQUIRES keyboard focus — the paged
  /// controller uses it to keep active-page bookkeeping in sync with the
  /// KEYBOARD rather than with recent pointer-downs. Without it, focus moving
  /// to a non-active page (AppFlowy focuses its editor on tap, reflows hand
  /// focus off, back-forward flows) left activeController stale, so the
  /// scaffold's mode badge/toggles were bound to the previous page — and vim
  /// keys entered through that page never showed up anywhere. Callers may
  /// already have made the index change; the controller's setActive is
  /// guarded/no-op on no change.
  void Function()? onFocusGained;

  bool _disposed = false;

  /// Analysis-review-mode chunk stepping: +1 = next chunk, -1 = previous.
  /// Set by the scaffold (which owns the [AnalysisModeController]); the
  /// 'n'/'N' character shortcuts in analysis mode call it. Null until wired
  /// (analysis not loaded yet), in which case the keys are swallowed.
  void Function(int delta)? onStepAnalysisChunk;

  /// Called when the user enters analysis-review mode from NORMAL mode via the
  /// 'n' key. The scaffold wires this to lazy-load the analysis (and enter the
  /// mode), so pressing 'n' populates chunks even before the side panel has
  /// been opened. Null until wired, in which case entering analysis mode just
  /// flips the vim mode with no analysis to navigate.
  VoidCallback? onEnterAnalysisMode;

  /// Called when the user presses 'q' in NORMAL or ANALYSIS mode to toggle
  /// the full analysis panel (the overview tab) without switching vim
  /// modes. The scaffold wires this to open/close the panel (lazy-loading
  /// the analysis on first open). Null until wired — the key is a no-op
  /// then. (Rebound from 'o', which is vim's open-line key now.)
  VoidCallback? onToggleAnalysisPanel;

  /// Called when Backspace is pressed with the caret at the VERY START of this
  /// page's first block. Set by [PagedNoteController] to merge the page up into
  /// the previous one. Returns true if it handled the key (so the editor's own
  /// backspace is suppressed), false to let the default backspace run (e.g. this
  /// is already the first page). Null when the note isn't paged.
  bool Function()? onBackspaceAtStart;

  /// Uploads the picked image [bytes] (original [filename]) and returns the URL
  /// to embed, or null on failure/cancel. Set by [PagedNoteController] from the
  /// note context (it knows the bubble + note). Null until wired — the "Image"
  /// slash item is a no-op without it (e.g. an unsaved note has nowhere to
  /// store to yet).
  Future<String?> Function(List<int> bytes, String filename)? imageUploader;

  /// The current collapsed caret as `(path, offset)`, or null when there's no
  /// selection or it's a range. `path` is the block path (length 1 for a
  /// top-level block; longer when nested, e.g. inside a table cell). Used by
  /// [PagedNoteController] to snapshot the caret before an overflow/merge rebuild
  /// (which disposes this editor) so it can be re-seeded onto the rebuilt page.
  ({List<int> path, int offset})? get caret {
    final sel = _editorState.selection;
    if (sel == null || !sel.isCollapsed) return null;
    return (path: List<int>.from(sel.start.path), offset: sel.start.offset);
  }

  // Built ONCE and reused across every `buildEditor` call, rather than
  // being reconstructed from scratch on every rebuild.
  //
  // Every transaction — a typed character, a cursor move, anything —
  // runs through `_editorState.transactionStream.listen((_) =>
  // notifyListeners())` above, which (via NoteEditorController ->
  // EditorSurface's AnimatedBuilder) rebuilds this widget and calls
  // `buildEditor` again. If `commandShortcutEvents`/
  // `characterShortcutEvents` were rebuilt inline in `buildEditor` (as
  // `...EditorShortcuts.getCustomShortcuts(vimMode)` etc., which is what
  // this used to do), every single keystroke would hand AppFlowyEditor
  // a brand-new List of brand-new shortcut objects — same content, but
  // different identity every time. AppFlowyEditor uses these lists to
  // decide whether its internal keyboard/selection-overlay service
  // needs to reinitialize, so a "different" list on every keystroke
  // made it tear down and rebuild that service constantly, which is
  // what was dropping the caret after every character typed or every
  // normal-mode navigation move (both are transactions, so both hit
  // this path identically). Caching these once means AppFlowyEditor
  // sees the *same* lists across rebuilds and has no reason to
  // reinitialize anything.
  late final List<CommandShortcutEvent> _commandShortcutEvents = [
    // FIRST: intercept backspace-at-page-start so it merges into the previous
    // page instead of doing nothing. Returns ignored in every other case, so
    // normal backspace (and the vim/standard handlers below) run untouched.
    _mergeToPreviousPageOnBackspace(),
    ...EditorShortcuts.getCustomShortcuts(vimMode),
    // Raw-key vim shortcuts: j/k/l/h/n/N/o/arrows as COMMAND events so they
    // keep working when the text-input service isn't attached (whole-table
    // selections have no delta node, so character shortcuts silently die).
    // Command shortcuts run before the standard list (which contains the
    // tableCommands), so analysis-mode block navigation preempts the table's
    // edge-swallowing arrow handlers.
    ...VimCharacterShortcuts.getRawKeyVimShortcuts(
      vimMode,
      onStepAnalysisChunk: onStepAnalysisChunk,
      onEnterAnalysisMode: onEnterAnalysisMode,
      onToggleAnalysisPanel: onToggleAnalysisPanel,
    ),
    ...standardCommandShortcutEvents,
  ];

  CommandShortcutEvent _mergeToPreviousPageOnBackspace() {
    return CommandShortcutEvent(
      key: 'merge into previous page on backspace at start',
      getDescription:
          () =>
              'Backspace at the very start of a page merges it into the previous page',
      command: 'backspace',
      handler: (editorState) {
        final handler = onBackspaceAtStart;
        if (handler == null) return KeyEventResult.ignored;
        final sel = editorState.selection;
        if (sel == null || !sel.isCollapsed) return KeyEventResult.ignored;
        if (sel.start.offset != 0) return KeyEventResult.ignored;
        // Only the caret at offset 0 of the FIRST top-level block (path [0]).
        // TODO(tables): when that first block is a table this still fires and
        // flows the whole table up to the previous page. Deferred with the rest
        // of the table-specific pagination work — decide whether a table should
        // block/merge differently.
        final path = sel.start.path;
        if (path.length != 1 || path.first != 0) return KeyEventResult.ignored;
        return handler() ? KeyEventResult.handled : KeyEventResult.ignored;
      },
    );
  }
  // Same identity-stability reasoning as `_commandShortcutEvents` above:
  // built once, reused across every `buildEditor` call rather than
  // rebuilt inline.
  //
  // The "/" slash menu is not a separate constructor param on
  // AppFlowyEditor — it's just another CharacterShortcutEvent
  // (the built-in `slashCommand`, triggered by typing '/'). To add our
  // own items we build a replacement via `pagedSlashCommand(...)` — a
  // fork of the stock `customSlashCommand` whose menu positions itself in
  // TRUE screen px (the stock overlay math assumes the editor box is at
  // screen origin and its size doc-px == screen-px — both false under
  // PageSurface's fitted transform) — and swap it in for the default one
  // by filtering the stock list (non-mutating; see _characterShortcutEvents).
  //
  // standardSelectionMenuItems only exposes Heading 1-3 — the heading
  // block itself supports any level via its `HeadingBlockKeys.level`
  // attribute, the menu just doesn't surface higher levels by default.
  // The heading items below add H4-H6.

  // Same identity-stability reasoning as the shortcut/menu lists above:
  // built once, reused across every `buildEditor` call.
  //
  // CHANGED: was `_codeBlockType: ParagraphBlockComponentBuilder(...)`
  // with a plain monospace TextStyle — no highlighting, no language
  // switch, no copy action, just a mono-styled paragraph. Now registered
  // against `CodeBlockComponentBuilder` (see
  // features/editor/blocks/code_block/code_block_component.dart),
  // which layers real syntax highlighting (via flutter_highlight, no
  // dependency on appflowy_editor's version), a language dropdown, and
  // a copy button, while still delegating the actual editable text
  // rendering to `ParagraphBlockComponentBuilder` underneath — so all
  // the "why this is safe" reasoning from the old comment still holds,
  // this is strictly additive on top of it.
  late final Map<String, BlockComponentBuilder> _blockComponentBuilders = () {
    // Start from the stock paragraph builder and change ONLY its placeholder
    // style, so every other piece of stock paragraph configuration survives.
    // Rebuilding the config from scratch risked breaking the placeholder text.
    final stockParagraph =
        standardBlockComponentBuilderMap[ParagraphBlockKeys.type]
            as ParagraphBlockComponentBuilder;

    return <String, BlockComponentBuilder>{
      ...standardBlockComponentBuilderMap,

      // Heading sizes are body-RELATIVE, not the stock absolute 32/28/24/18pt
      // (which at kBaseFontSize=8 renders H1 as a 4x billboard). The multiplier
      // list is the single tuning knob — see page_space.dart. Weight stays bold
      // to match the stock look. The configuration is preserved from the stock
      // registration: without it the empty-heading placeholder ("Heading 1")
      // regresses to a blank space, because the default placeholderText is ' '.
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText:
              (node) => 'Heading ${node.attributes[HeadingBlockKeys.level]}',
        ),
        textStyleBuilder:
            (level) => TextStyle(
              fontSize: kHeadingFontSizeFor(level),
              fontWeight: FontWeight.bold,
            ),
      ),

      // PARAGRAPH — the placeholder style sizes the empty-line layout (a 24pt
      // test grew both the placeholder and the empty line), so it is pinned to
      // the body size and line height. Color is a fixed grey because this
      // field has no BuildContext to read the theme from.
      // Forked builder (was: stock ParagraphBlockComponentBuilder): the stock
      // AppFlowyRichText leaves the empty-delta root span unstyled → 14pt
      // impostor caret at rest. Same configuration, fixed span builder.
      ParagraphBlockKeys.type: PagedParagraphBlockComponentBuilder(
        configuration: stockParagraph.configuration.copyWith(
          placeholderText:
              (_) => 'Enter a / to insert a block, or start typing',
          placeholderTextStyle:
              (node, {textSpan}) => TextStyle(
                fontSize: kBaseFontSize,
                height: kLineHeight,
                color: const Color(0xFF8A8A8A),
              ),
        ),
      ),

      // LISTS — the stock entries from the spread above are REPLACED here only
      // to inject body-relative icon columns (PagedListIcons): the stock icon
      // builders hardcode a 26x22dp column for a 16pt body, which at the small
      // canonical body renders ~2x the text row height (the "gap under list
      // items that lineHeight didn't fix" — that gap is the icon column, outside
      // the rich text). Configurations/payload behavior kept identical to stock.
      TodoListBlockKeys.type: TodoListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) => AppFlowyEditorL10n.current.toDoPlaceholder,
        ),
        toggleChildrenTriggers: [
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
        ],
        iconBuilder: PagedListIcons.todo,
      ),
      BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText:
              (_) => AppFlowyEditorL10n.current.listItemPlaceholder,
        ),
        iconBuilder: PagedListIcons.bulleted,
      ),
      NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText:
              (_) => AppFlowyEditorL10n.current.listItemPlaceholder,
        ),
        iconBuilder: PagedListIcons.numbered,
      ),

      kCodeBlockType: CodeBlockComponentBuilder(),
      // TeX equation block (flutter_math_fork rendering; non-text node).
      kEquationBlockType: EquationBlockComponentBuilder(),
      // SCAFFOLD: inline AI-feedback block (read-only, generation is a TODO).
      kAiBlockType: AiBlockComponentBuilder(),
      // Table fork — overrides the stock 'table' entry from the spread above.
      // Guards in the fork cap table growth against the sheet, which the stock
      // builder can't do (it creates the same default-width cell regardless of
      // page size).
      'table': CerebrumTableBlockComponentBuilder(),
    };
  }();

  late final List<SelectionMenuItem> _slashMenuItems = [
    ...standardSelectionMenuItems,
    _headingMenuItem(4),
    _headingMenuItem(5),
    _headingMenuItem(6),
    _codeBlockMenuItem(),
    _equationMenuItem(),
    _imageMenuItem(),
    _aiBlockMenuItem(),
  ];

  /// "/image" → pick an image file, upload it via [imageUploader], and drop an
  /// image block where the caret is. Instance (not static) because it reaches
  /// [imageUploader]. No-op if the uploader isn't wired (unsaved note) or the
  /// pick is cancelled.
  SelectionMenuItem _imageMenuItem() {
    return SelectionMenuItem(
      getName: () => 'Image',
      icon:
          (editorState, isSelected, style) => SelectionMenuIconWidget(
            icon: Icons.image,
            isSelected: isSelected,
            style: style,
          ),
      keywords: ['image', 'img', 'picture', 'photo'],
      handler: (editorState, menuService, context) {
        // Fire-and-forget: the picker + upload are async, but the slash menu
        // handler is sync. The selection path is captured up front so the insert
        // lands where "/image" was even after the await.
        _pickUploadInsertImage(editorState);
      },
    );
  }

  Future<void> _pickUploadInsertImage(EditorState editorState) async {
    final uploader = imageUploader;
    final selection = editorState.selection;
    if (uploader == null || selection == null) return;
    final path = selection.start.path;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // need the bytes (works on desktop + web)
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;

    final url = await uploader(bytes, file!.name);
    if (url == null) return;

    // Replace the (now-"/image") node with the image block, or if that node has
    // real text, insert the image right after it.
    final node = editorState.getNodeAtPath(path);
    if (node == null) return;
    final transaction = editorState.transaction;
    final hasText = (node.delta?.toPlainText().trim().isNotEmpty) ?? false;
    if (hasText) {
      transaction.insertNode(path.next, imageNode(url: url));
    } else {
      transaction
        ..insertNode(path, imageNode(url: url))
        ..deleteNode(node);
    }
    await editorState.apply(transaction);
  }

  late final List<CharacterShortcutEvent> _characterShortcutEvents = [
    ...VimCharacterShortcuts.getCharacterShortcuts(
      vimMode,
      onStepAnalysisChunk: onStepAnalysisChunk,
      onEnterAnalysisMode: onEnterAnalysisMode,
      onToggleAnalysisPanel: onToggleAnalysisPanel,
    ),
    // Greek `\name` + space substitution. MUST stay after the vim list and
    // before the slash menu / standard events: character shortcuts dispatch
    // in order and stop at the first `true`, and this event must be able to
    // fall through (return false) to the standard markdown-on-space
    // conversions whenever the caret isn't directly after `\name` — see
    // GreekLetterShortcuts' header comment.
    ...GreekLetterShortcuts.events,
    pagedSlashCommand(_slashMenuItems),
    // Non-mutating filter: the old `..removeWhere(...)` edited the package's
    // GLOBAL standardCharacterShortcutEvents list in place.
    ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
  ];

  static SelectionMenuItem _headingMenuItem(int level) {
    return SelectionMenuItem(
      getName: () => 'H$level',
      // The built-in H1-H3 items render via SelectionMenuIconWidget(name:
      // 'h1'/'h2'/'h3', ...), which maps to bundled icon assets that only
      // exist for levels 1-3. There's no 'h4'/'h5'/'h6' asset to reuse, so
      // this reproduces the same "big H + small number" look by hand.
      // Colors are hardcoded rather than pulled from SelectionMenuStyle
      // since its exact field names weren't confirmed against your pinned
      // version — swap in the theme's real icon color if it looks off
      // next to H1-H3.
      icon:
          (editorState, isSelected, style) =>
              _HeadingIcon(level: level, isSelected: isSelected),
      keywords: ['h$level', 'heading$level', 'heading $level'],
      handler: (editorState, menuService, context) {
        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) return;
        final path = selection.start.path;
        final node = editorState.getNodeAtPath(path);
        if (node == null) return;

        final transaction =
            editorState.transaction
              ..insertNode(path, headingNode(level: level, delta: node.delta))
              ..deleteNode(node)
              ..afterSelection = Selection.collapsed(
                Position(path: path, offset: selection.start.offset),
              );
        editorState.apply(transaction);
      },
    );
  }

  /// "/ai" → drop a read-only AI-feedback block where the caret is (SCAFFOLD;
  /// generation is wired inside the block itself, currently a stub).
  static SelectionMenuItem _aiBlockMenuItem() {
    return SelectionMenuItem(
      getName: () => 'AI feedback',
      icon:
          (editorState, isSelected, style) => SelectionMenuIconWidget(
            icon: Icons.auto_awesome,
            isSelected: isSelected,
            style: style,
          ),
      keywords: ['ai', 'feedback', 'assistant', 'gpt'],
      handler: (editorState, menuService, context) {
        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) return;
        final path = selection.start.path;
        final node = editorState.getNodeAtPath(path);
        if (node == null) return;
        final hasText = (node.delta?.toPlainText().trim().isNotEmpty) ?? false;
        final transaction = editorState.transaction;
        if (hasText) {
          transaction.insertNode(path.next, aiBlockNode());
        } else {
          transaction
            ..insertNode(path, aiBlockNode())
            ..deleteNode(node);
        }
        editorState.apply(transaction);
      },
    );
  }

  static SelectionMenuItem _codeBlockMenuItem() {
    return SelectionMenuItem(
      getName: () => 'Code Block',
      icon:
          (editorState, isSelected, style) => SelectionMenuIconWidget(
            icon: Icons.code,
            isSelected: isSelected,
            style: style,
          ),
      keywords: ['code', 'code block', 'codeblock', '```'],
      handler: (editorState, menuService, context) {
        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) return;
        final path = selection.start.path;
        final node = editorState.getNodeAtPath(path);
        if (node == null) return;

        // CHANGED: was a hand-built `Node(type: _codeBlockType,
        // attributes: {blockComponentDelta: ...})` with no language
        // attribute. `codeBlockNode(...)` is the same shape plus a
        // default `language: 'plaintext'`, which CodeBlockComponentBuilder
        // reads to pick the highlight grammar and pre-select the
        // dropdown.
        final transaction =
            editorState.transaction
              ..insertNode(path, codeBlockNode(delta: node.delta))
              ..deleteNode(node)
              ..afterSelection = Selection.collapsed(
                Position(path: path, offset: selection.start.offset),
              );
        editorState.apply(transaction);
      },
    );
  }

  /// "/equation" (also "/latex", "/math") → opens the LaTeX dialog with a
  /// live preview and drops an equation_block where the caret is. Named
  /// static like the other menu items; the dialog itself lives in
  /// equation_block_component.dart so the block's own edit button reuses
  /// the exact same UI.
  ///
  /// Convenience: if you type `\frac` and hit enter from the slash menu,
  /// the inline quick-insertion parity with the ai block applies — a
  /// paragraph with content gets the block APPENDED after it, an empty
  /// paragraph is REPLACED, so formulae never eat surrounding prose.
  static SelectionMenuItem _equationMenuItem() {
    return SelectionMenuItem(
      getName: () => 'LaTeX equation',
      icon:
          (editorState, isSelected, style) => SelectionMenuIconWidget(
            icon: Icons.functions,
            isSelected: isSelected,
            style: style,
          ),
      keywords: ['equation', 'latex', 'math', 'formula', 'tex'],
      handler: (editorState, menuService, context) async {
        final source = await showEquationDialog(context);
        if (source == null || source.isEmpty) return;
        if (!context.mounted) return;

        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) return;
        final path = selection.start.path;
        final node = editorState.getNodeAtPath(path);
        if (node == null) return;

        // Same replacement/append split as the ai block: a paragraph with
        // text becomes the equation's parent header line, an empty
        // paragraph is subsumed by the block. NOTE: no explicit
        // afterSelection — the equation node is a non-text container, so
        // there's no caret to reassert on it (AppFlowy keeps the caret
        // where it can — same as the ai block's insertion).
        final transaction = editorState.transaction;
        if ((node.delta?.toPlainText().trim().isNotEmpty) ?? false) {
          transaction.insertNode(path.next, equationBlockNode(latex: source));
        } else {
          transaction
            ..insertNode(path, equationBlockNode(latex: source))
            ..deleteNode(node);
        }
        await editorState.apply(transaction);
      },
    );
  }

  @override
  /// This page's vim controller — SHARED across every page of one note when
  /// injected by PagedNoteController (see the constructor), so one mode exists
  /// for the document rather than one per page.
  final VimModeController vimMode;

  /// Exposed for anything AppFlowy-specific that needs it (there isn't
  /// much reason to reach for this outside of this file/tests).
  EditorState get editorState => _editorState;

  /// Fires whenever the selection changes (caret move, tap, range). Used by the
  /// analysis popover to react to which block the caret is in. This is the raw
  /// AppFlowy selection notifier, so listeners fire on every caret move.
  Listenable get selectionChanges => _editorState.selectionNotifier;

  /// The index of the TOP-LEVEL block the selection anchors on (its start side),
  /// or null when there's no selection / it's nested (e.g. inside a table
  /// cell). Works for BOTH the collapsed caret (normal editing) and the
  /// whole-block highlight selections analysis review uses — non-collapsed is
  /// not a reason to decline here, the popover keys on the block, not the
  /// caret. Used only for on-screen positioning (rectOfBlock); analysis is
  /// keyed by the stable [selectedBlockId], not this position.
  int? get selectedBlockIndex {
    final sel = _editorState.selection;
    if (sel == null) return null;
    final path = sel.start.path;
    return path.length == 1 ? path.first : null;
  }

  /// The STABLE id of the top-level block the selection anchors on, or null
  /// (same guards as [selectedBlockIndex]). This is the durable identity the
  /// daemon keys analysis to — it round-trips via documentJson, so tapping a
  /// block maps to its findings even after blocks above it are added/reordered.
  String? get selectedBlockId {
    final sel = _editorState.selection;
    if (sel == null) return null;
    final path = sel.start.path;
    if (path.length != 1) return null;
    return _editorState.getNodeAtPath([path.first])?.id;
  }

  /// The on-screen (global) rect of top-level block [index], or null if it isn't
  /// currently laid out. Used to anchor the analysis popover to the block.
  Rect? rectOfBlock(int index) {
    final node = _editorState.getNodeAtPath([index]);
    if (node == null || node.renderBox == null) return null;
    return node.rect;
  }

  @override
  void focusBlockById(String blockId) {
    final document = _editorState.document;
    int? targetPathIndex;

    // Simple search through the root children for the matching ID.
    for (int i = 0; i < document.root.children.length; i++) {
      final node = document.root.children[i];
      if (node.id == blockId) {
        targetPathIndex = i;
        break;
      }
    }

    if (targetPathIndex != null) {
      _editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: [targetPathIndex], offset: 0)),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  // Stable ids of the blocks this page currently highlights (the active
  // analysis chunk). Cleared when the page leaves analysis mode (see
  // [_onVimModeChanged]).
  Set<String> _highlightedBlockIds = <String>{};

  /// Highlight (or clear) the blocks whose stable id is in [blockIds] by
  /// setting the built-in `bgColor` node attribute (see
  /// [blockComponentBackgroundColor]). Passing null for [colorString] clears
  /// the highlight on those blocks. Used by analysis-review mode to visually
  /// mark the current chunk. Searches ALL levels (not just top-level blocks)
  /// so nested blocks (e.g. inside a table cell) are found too.
  ///
  /// Tracks the highlighted ids so [_onVimModeChanged] can clear them when the
  /// page leaves analysis-review mode.
  void setChunkHighlight(List<String> blockIds, String? colorString) {
    if (blockIds.isEmpty) {
      debugPrint('[setChunkHighlight] no blockIds provided — nothing to do');
      return;
    }
    final wanted = blockIds.toSet();
    _highlightedBlockIds =
        colorString == null
            ? _highlightedBlockIds.difference(wanted)
            : _highlightedBlockIds.union(wanted);

    final nodes = <Node>[];
    for (final child in _editorState.document.root.children) {
      _collectById(child, wanted, nodes);
    }
    debugPrint(
      '[setChunkHighlight] ids=$blockIds matched=${nodes.length} '
      'color=${colorString ?? 'null'}',
    );
    if (nodes.isEmpty) return;

    final transaction = _editorState.transaction;
    for (final node in nodes) {
      if (colorString == null) {
        transaction.updateNode(node, {blockComponentBackgroundColor: null});
      } else {
        transaction.updateNode(node, {
          blockComponentBackgroundColor: colorString,
        });
      }
    }
    _editorState.apply(transaction);
  }

  /// Fired by [vimMode] changes. When the page leaves analysis-review mode,
  /// drop the active chunk highlight so it can't linger on the document after
  /// Esc / editing resumes. Narrowly scoped — does NOT call notifyListeners.
  void _onVimModeChanged() {
    final inAnalysis = vimMode.isAnalysis;
    if (_wasInAnalysis && !inAnalysis && _highlightedBlockIds.isNotEmpty) {
      final ids = _highlightedBlockIds.toList();
      _highlightedBlockIds = <String>{};
      setChunkHighlight(ids, null);
    }
    _wasInAnalysis = inAnalysis;

    // Re-assert keyboard focus across every vim flip that happens ON this
    // page: Esc (insert→normal, analysis→normal), 'i' (→insert), 'n'
    // (→analysis), and the toolbar mode switch (which momentarily focuses
    // the button that toggled it). Keys arrive on THIS driver only when it is
    // the page the user is interacting with, so requesting self-focus is
    // correct in every single-page case.
    //
    // Deliberately gated on isEnabled: the drawing toggle broadcasts
    // `setEnabled(false)` to EVERY page on the way in, and those pages must
    // NOT steal the keyboard (drawing owns it). The drawing toggle's way out
    // re-requests focus itself, on the ACTIVE page only (see
    // PagedNoteController.toggleDrawingMode).
    if (vimMode.isEnabled) {
      requestEditorFocus();
    }
  }

  /// Fired when this page's editor focus node gains or loses focus.
  ///
  /// On GAIN: revive the caret if AppFlowy nulled it during the unfocused
  /// spell (see the registration comment in the constructor for why AppFlowy
  /// is the one doing the nulling), restore the pending seed caret — or, failing
  /// that, the LAST KNOWN caret from before focus was lost — and publish the
  /// gain so the paged controller can re-point active-bookkeeping at THIS page
  /// (the keyboard owner is the source of truth for the scaffold's vim
  /// badge/toggles, not pointer downs).
  ///
  /// On LOSS: remember the selection, then clear the visual caret so an
  /// unfocused page never keeps one — AppFlowy's own keyboard service clears
  /// its side, and this covers the states where that listener isn't mounted
  /// yet (a remounted page whose selection survives in the cached
  /// EditorState). Without clearing, lost-focus pages kept rendering the stale
  /// caret of a previous spell — the "two carets competing" state the
  /// phantom-caret seeding produced.
  void _onFocusNodeChanged() {
    if (_disposed) return;
    // Drawing mode owns the pointer, not the text caret: don't revive or
    // publish caret semantics from focus flips while drawing is on.
    if (!vimMode.isEnabled) return;
    // A slash menu is intentionally stealing keyboard focus from this page
    // (keyboardService.disable() unfocuses the editor node). The menu needs
    // editorState.selection INTACT — every stock menu item handler's first
    // line is `if (selection == null || !isCollapsed) return;` — so the
    // loss-side caret clearing below would silently break Enter-to-insert.
    // Skip the whole loss branch while the menu owns the keyboard.
    if (isPagedSlashMenuOpen) return;
    if (!editorFocusNode.hasFocus) {
      final selection = editorState.selection;
      if (selection != null) {
        // Remember where the caret was so regaining focus resumes HERE
        // instead of jumping to the first block.
        _lastKnownCaret = selection;
        editorState.updateSelectionWithReason(
          null,
          reason: SelectionUpdateReason.uiEvent,
        );
      }
      return;
    }
    // GAIN, in priority order: pending seed first (it knows the exact caret
    // the page was seeded with), then the last known caret from the previous
    // focus spell, then the standard end-of-line revive on the first block.
    if (editorState.selection == null) {
      _pendingCaret ??= _lastKnownCaret;
      _applyPendingCaret();
    }
    if (editorState.selection == null) {
      _reviveDefaultCaret();
    }
    onFocusGained?.call();
  }

  /// Restore the pending seed caret, only if its path still resolves in the
  /// current document (a reflow may have moved/merged the seeded block).
  void _applyPendingCaret() {
    final pending = _pendingCaret;
    if (pending == null) return;
    _pendingCaret = null;
    // Walk to the path's node; a reflow could have made it unreachable.
    Node node = editorState.document.root;
    for (final index in pending.start.path) {
      if (node.children.length <= index) return; // stale: let the default run
      node = node.children[index];
    }
    final length = node.delta?.length ?? 0;
    final offset = pending.start.offset.clamp(0, length).toInt();
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: node.path, offset: offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// The pre-existing revive: end-of-line caret on the document's first block,
  /// used when there's no pending seed or last-known caret (focus regained on
  /// a page that was never interacted with).
  void _reviveDefaultCaret() {
    final children = editorState.document.root.children;
    if (children.isEmpty) return;
    final target = children.first;
    final len = target.delta?.length ?? 0;
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: target.path, offset: len)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// Requests keyboard focus for this page's editor: the caret renders here
  /// and vim/arrow navigation keys land here. Safe when already focused
  /// (no-op); safe to call from a key handler (deferred a frame). On a page
  /// remount the new editor only attaches this focus node on a LATER frame, so
  /// the request re-arms (bounded) until the node is attached — otherwise a
  /// request fired right after `_makePage` would land on the old, about-to-be
  /// disposed node and vanish.
  void requestEditorFocus({int attempts = 0}) {
    if (_disposed || attempts > 6) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || editorFocusNode.hasFocus) return;
      // An open slash menu owns the keyboard: the menu's own Focus took
      // primary focus the frame after mounting, and a retry from an earlier
      // vim flip / focus change would steal it back — Enter then dies in the
      // (disabled) editor keyboard service. Drop the retry silently; the
      // menu hands focus back on dismissal.
      if (isPagedSlashMenuOpen) return;
      editorFocusNode.requestFocus();
      if (!editorFocusNode.hasFocus) {
        requestEditorFocus(attempts: attempts + 1);
      }
    });
  }

  /// Depth-first walk collecting nodes whose stable id is in [wanted].
  void _collectById(Node node, Set<String> wanted, List<Node> out) {
    if (wanted.contains(node.id)) out.add(node);
    for (final child in node.children) {
      _collectById(child, wanted, out);
    }
  }

  @override
  Map<String, dynamic> get documentJson =>
  // AppFlowy's Node.toJson() drops the node id (and Node.fromJson ignores
  // it), so a plain toJson() gives blocks NO stable identity — the daemon
  // then falls back to fragile positional ids for tap-a-block analysis.
  // Emit each node's id here and restore it on load (see _restoreNodeIds)
  // so a block keeps ONE identity across edits/reloads/sync — the same
  // contract ink strokes already have via their stroke id.
  _nodeToJsonWithId(_editorState.document.root);

  @override
  Widget buildEditor(BuildContext context) {
    // All sizes are CANONICAL document units: pages host this editor inside a
    // FittedBox'd fixed-size document space (see page_surface.dart /
    // page_space.dart), and view zoom scales paint — never this layout. A
    // page's editor is identical on a 4K monitor and a laptop screen; the
    // FittedBox absorbs the difference.
    //
    // DefaultTextStyle clamp: the caret's `max(main, placeholder)` branch
    // measures paragraphs from Frame N while styles resolve from Frame N+1.
    // On the empty→first-character transition the main RichText briefly has
    // a ROOT span with NO fontSize (verified via the [para] dump:
    // "[h=16.0 fs=null/null]") — an unstyled span falls back to the ambient
    // DefaultTextStyle (Material's bodyMedium = 14pt), so the caret metric
    // becomes 14pt Roboto ≈ 16.3px ≈ 2× the 8pt row, and the package's
    // BlockSelectionArea paint loop can draw that inflated rect for a beat.
    // Clamping the inherited default to OUR body metrics makes the transient
    // resolve to 10px (fs 8 × kLineHeight 1.25) — identical to the settled
    // row. Only fontSize/height are set: color/family keep inheriting the
    // ambient theme exactly as before.
    return DefaultTextStyle(
      style: const TextStyle(fontSize: kBaseFontSize, height: kLineHeight),
      child: AppFlowyEditor(
        editorState: _editorState,
        // Embed as a non-scrolling Column so this editor coexists with the
        // paged ListView (see _scrollController). Without it, nesting the
        // editor's own scroll view inside the page list throws the
        // "Provider<EditorScrollController>" error on multi-page notes.
        editorScrollController: _scrollController,
        // Never let a page's editor drive scrolling to chase the caret. Each page
        // is a bounded sheet inside the outer page ListView; auto-scroll-into-view
        // would scroll that OUTER list — which showed up as the view lurching to
        // the previous page after a backspace-merge, and "jumping to a new page"
        // when Enter pushed the caret past the sheet. The user scrolls the page
        // list themselves. (Gates desktop_scroll_service's scrollTo.)
        disableAutoScroll: true,
        disableScrollService: false,

        // Hand the keyboard service OUR focus node (see [editorFocusNode]) —
        // this is the only handle through which [requestEditorFocus] can work.
        focusNode: editorFocusNode,

        // Always false. AppFlowy 6.x's autoFocus does NOT focus: it merely
        // overwrites the selection with `Selection(path[0])` on mount — which
        // would clobber the caret the driver seeded (end-of-last-line, or the
        // merge/overflow seam). Real focus is [requestEditorFocus], called by
        // the controller on exactly the page that owns the caret.
        autoFocus: false,
        // Carries the standard block builders plus the 'code_block' type
        // added above (registered against CodeBlockComponentBuilder with
        // syntax highlighting). Cached field — see _blockComponentBuilders.
        blockComponentBuilders: _blockComponentBuilders,
        // Custom shortcuts go FIRST: AppFlowyEditor stops at the first
        // matching shortcut whose handler returns `handled`. The standard
        // library ships its own Escape binding (used to collapse
        // selection / dismiss popups) — with standard shortcuts checked
        // first, that binding swallowed Escape before
        // `mode.enterNormalMode()` ever ran, so Escape looked like a
        // no-op instead of returning to normal mode. Same reasoning
        // applies to characterShortcutEvents.
        //
        // These are cached fields (see above), NOT rebuilt here, so the
        // same List/object identity survives every rebuild.
        commandShortcutEvents: _commandShortcutEvents,
        // Carries the customized "/" slash menu (standard items + H4-H6 +
        // Code Block) via pagedSlashCommand — the page-space-aware fork of
        // customSlashCommand (see widgets/paged_slash_menu.dart). There is no
        // separate `selectionMenuItems` constructor param.
        characterShortcutEvents: _characterShortcutEvents,
        // ANALYSIS MODE: wraps every rendered block in a tap-interceptor that
        // selects the WHOLE block (cursor-less highlight) instead of letting the
        // editor drop an editable caret. Passes through untouched in normal and
        // insert modes — see [_buildBlockWrapper].
        blockWrapper: _buildBlockWrapper,
        editorStyle: EditorStyle.desktop(
          //cursorColor
          padding: EdgeInsets.symmetric(horizontal: kBaseHorizontalPadding),
          textStyleConfiguration: TextStyleConfiguration(
            text: TextStyle(
              color: context.cerebrum.text.strong, // wire to your theme token
              fontSize: kBaseFontSize,
            ),
            // Single knob for caret height AND row leading slack AND page
            // density — see kLineHeight in page_space.dart.
            lineHeight: kLineHeight,
          ),
        ),
      ),
    );
  }

  /// Wraps every rendered block in [_AnalysisTapCapture] so that, in analysis
  /// review mode, clicking a block highlights the block instead of placing a
  /// typing caret. The wrapper sits INSIDE the editor's selection gesture
  /// detector, so its deeper tap recognizer wins the gesture arena and the
  /// editor's own tap-to-caret path never runs. In every other mode the block
  /// is returned untouched (zero behavior change for normal/insert editing).
  ///
  /// Also prepends a faint "H1"/"H2"/… gutter tag to every non-empty heading
  /// block. The tag is pure chrome — it is NOT part of the node's delta and is
  /// never persisted, selected, or copied. Empty headings are left alone so
  /// the stock "Heading N" placeholder isn't shadowed by a redundant tag.
  ///
  /// Why the heading tag lives HERE (in blockWrapper) rather than in a forked
  /// HeadingBlockComponentBuilder: the pinned appflowy_editor narrows
  /// `BlockComponentBuilder.build` to return `BlockComponentWidget`, so a
  /// subclass override can't return a plain `Row` without also subclassing
  /// BlockComponentWidget — whose abstract getters/constructor shape vary
  /// between 5.x and 6.x. `blockWrapper` is typed as
  /// `Widget Function(BuildContext, {Node, Widget})` and accepts any Widget,
  /// so it sidesteps the version-specific class entirely. See [_HeadingWithLevelTag].
  Widget _buildBlockWrapper(
    BuildContext context, {
    required Node node,
    required Widget child,
  }) {
    if (node.type == HeadingBlockKeys.type) {
      final isEmpty = node.delta?.isEmpty ?? true;
      if (!isEmpty) {
        final level =
            (node.attributes[HeadingBlockKeys.level] as num?)?.toInt() ?? 1;
        child = _HeadingWithLevelTag(level: level, child: child);
      }
    }
    return _AnalysisTapCapture(
      vimMode: vimMode,
      editorState: _editorState,
      node: node,
      child: child,
    );
  }

  static const _emptyDocument = {
    "type": "page",
    "children": [
      {
        "type": "paragraph",
        "data": {
          "delta": [
            {"insert": ""},
          ],
        },
      },
    ],
  };

  static EditorState _buildEditorState(
    Map<String, dynamic>? initial, [
    int? caretBlockIndex,
    int? caretOffset,
    bool seedCaret = true,
  ]) {
    final docJson = initial ?? _emptyDocument;
    final state = _constructEditorState(docJson);

    // Seed the caret. `caretBlockIndex` targets a specific top-level block:
    // the backspace-merge passes it with offset 0 (the seam); the reflow's
    // caret hand-off passes an explicit `caretOffset` to land the caret exactly
    // where the user was typing. Otherwise the caret goes to the END of the last
    // line, so a focused page is immediately editable with no click.
    final children = state.document.root.children;
    if (caretBlockIndex != null && children.isNotEmpty) {
      final idx = caretBlockIndex.clamp(0, children.length - 1).toInt();
      // Clamp the offset to the target block's length (a non-text or shorter
      // block can't hold an offset carried over from a longer one).
      final blockLen = children[idx].delta?.length ?? 0;
      final off = (caretOffset ?? 0).clamp(0, blockLen).toInt();
      state.updateSelectionWithReason(
        Selection.collapsed(Position(path: [idx], offset: off)),
        reason: SelectionUpdateReason.uiEvent,
      );
      return state;
    }

    // No explicit caret target. Seed the default end-of-line caret ONLY when
    // asked — a page that shouldn't hold the cursor (e.g. the source page after
    // an overflow flow moved the caret to the next page) passes seedCaret:false
    // so it doesn't render a second, lingering cursor.
    if (seedCaret) {
      final lastNode = state.document.last;
      if (lastNode != null) {
        final offset = lastNode.delta?.length ?? 0;
        state.updateSelectionWithReason(
          Selection.collapsed(Position(path: lastNode.path, offset: offset)),
          reason: SelectionUpdateReason.uiEvent,
        );
      }
    }

    return state;
  }

  // Split out from `_buildEditorState` specifically so the try/catch
  // can use `return` in each branch. Assigning a single `final` local
  // from both a try block and its catch block is a Dart compile error
  // (assignment_to_final_local) even though only one branch ever
  // actually runs — a separate function that returns directly from
  // each branch avoids that restriction entirely.
  static EditorState _constructEditorState(Map<String, dynamic> docJson) {
    try {
      final state = EditorState(
        document: Document.fromJson({'document': docJson}),
      );
      // Document.fromJson mints fresh nanoids and discards any persisted `id`,
      // so restore the stored ids onto the freshly-built node tree. Without
      // this, the id would change on every load and tap-a-block mapping would
      // never be durable.
      final children = docJson['children'];
      if (children is List) {
        _restoreNodeIds(children, state.document.root.children);
      }
      return state;
    } catch (_) {
      return EditorState.blank();
    }
  }

  /// Serialise a node (recursively) INCLUDING its `id`. Mirrors AppFlowy's
  /// Node.toJson() shape (`type` / `data` / `children`) and adds `id` at every
  /// level so block identity round-trips to the daemon.
  static Map<String, dynamic> _nodeToJsonWithId(Node node) {
    final map = Map<String, dynamic>.from(node.toJson());
    map['id'] = node.id;
    final kids = node.children;
    if (kids.isNotEmpty) {
      map['children'] = kids.map(_nodeToJsonWithId).toList(growable: false);
    }
    return map;
  }

  /// Walk the raw JSON tree and the freshly-parsed node tree in parallel,
  /// copying each persisted `id` back onto its node (Node.id is mutable). The
  /// two trees are structurally identical because the nodes were just built
  /// from this same JSON, so positional pairing is exact.
  static void _restoreNodeIds(List<dynamic> jsonNodes, List<Node> nodes) {
    final count =
        jsonNodes.length < nodes.length ? jsonNodes.length : nodes.length;
    for (var i = 0; i < count; i++) {
      final j = jsonNodes[i];
      if (j is! Map) continue;
      final id = j['id'];
      if (id is String && id.isNotEmpty) {
        nodes[i].id = id;
      }
      final childJson = j['children'];
      if (childJson is List) {
        _restoreNodeIds(childJson, nodes[i].children);
      }
    }
  }

  // [caret-debug] TEMP — caret rect heights on every selection change, plus
  // (only when the caret height is anomalous, i.e. bigger than a body row)
  // a ONE-LINE dump of every RenderParagraph under the selected node with
  // its box height and span fontSize. debugPrint is throttled, so emitting
  // one line per paragraph per selection change dropped the dump entirely —
  // anomaly-gating + concatenation is what makes it survive.
  void _debugCaretMetrics() {
    if (_disposed) return;
    final sel = _editorState.selection;
    final node =
        sel == null ? null : _editorState.getNodeAtPath(sel.start.path);
    final rects = sel != null ? _editorState.selectionRects() : const <Rect>[];
    final heights = rects
        .map(
          (r) => "${r.height.toStringAsFixed(1)}@${r.top.toStringAsFixed(1)}",
        )
        .join(" ");
    debugPrint(
      '[caret-debug] mode=${vimMode.isNormal
          ? "normal"
          : vimMode.isInsert
          ? "insert"
          : vimMode.isAnalysis
          ? "analysis"
          : "visual"} '
      'path=${sel?.start.path} offset=${sel?.start.offset} '
      'type=${node?.type} emptyDelta=${(node?.delta?.isEmpty ?? true)} '
      'rects=$heights',
    );
    if (rects.isEmpty ||
        (rects.every((r) => r.height <= 12) && node?.delta?.isEmpty != true)) {
      return;
    }
    final el = node?.context;
    if (el == null || !el.mounted) return;
    final root = el.findRenderObject();
    if (root == null) {
      debugPrint('[para] node render object unavailable');
      return;
    }
    final dump = StringBuffer();
    _dumpParagraphs(root, dump);
    debugPrint('[para] ANOMALY-CARET $heights :: $dump');
  }

  void _dumpParagraphs(RenderObject ro, StringBuffer dump) {
    if (ro is RenderParagraph) {
      final span = ro.text;
      final TextSpan ts = span is TextSpan ? span : const TextSpan();
      final TextSpan child =
          ts.children?.whereType<TextSpan>().firstOrNull ?? ts;
      final plain = ts.toPlainText();
      dump.write(
        '[h=${ro.size.height.toStringAsFixed(1)} fs=${ts.style?.fontSize}/${child.style?.fontSize} '
        '"${plain.substring(0, math.min(16, plain.length))}"] ',
      );
    }
    ro.visitChildren((child) => _dumpParagraphs(child, dump));
  }

  @override
  void dispose() {
    _disposed = true;
    _transactionSub.cancel();
    _editorState.selectionNotifier.removeListener(_debugCaretMetrics);
    vimMode.removeListener(_onVimModeChanged);
    editorFocusNode.removeListener(_onFocusNodeChanged);
    editorFocusNode.dispose();
    _scrollController.dispose();
    // Only dispose a vim controller this driver created. The injected one is
    // shared across pages and disposed by PagedNoteController.dispose().
    if (_ownsVimMode) vimMode.dispose();
    super.dispose();
  }
}

/// Renders "H" + a small trailing number, matching the visual pattern of
/// the package's built-in H1-H3 slash-menu icons (big letter, small
/// subscript-style digit) for the H4-H6 items this file adds. Sizing and
/// color are approximate — nudge `fontSize`/color to match exactly if it
/// looks slightly off next to the built-in H1-H3 icons in your theme.
class _HeadingIcon extends StatelessWidget {
  const _HeadingIcon({required this.level, required this.isSelected});

  final int level;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color =
        isSelected
            ? context.cerebrum.code.selection
            : context.cerebrum.code.textDefault;
    return SizedBox(
      width: 20,
      height: 18,
      child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'H',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              TextSpan(
                text: '$level',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Analysis-review tap interceptor, one per rendered block.
///
/// When its page's vim mode is ANALYSIS, wraps the block in an opaque
/// GestureDetector whose tap selects the WHOLE block as a non-collapsed range —
/// the same no-caret highlight shape the table builder already produces. Because
/// the wrapper renders inside the editor's selection gesture detector, this
/// deeper recognizer wins the gesture arena: the editor's own tap handler never
/// fires, so it never drops an editable collapsed caret in review mode.
///
/// Empty blocks (start == end) still collapse to a caret — there is no range to
/// highlight on a block with no content, and this matches what the editor does
/// natively for zero-length selection.
class _AnalysisTapCapture extends StatelessWidget {
  const _AnalysisTapCapture({
    required this.vimMode,
    required this.editorState,
    required this.node,
    required this.child,
  });

  final VimModeController vimMode;
  final EditorState editorState;
  final Node node;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VimMode>(
      valueListenable: vimMode,
      builder: (context, mode, _) {
        if (mode != VimMode.analysis) return child;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _selectWholeBlock(),
          child: child,
        );
      },
    );
  }

  void _selectWholeBlock() {
    final selectable = node.selectable;
    if (selectable == null) return;
    editorState.updateSelectionWithReason(
      Selection(start: selectable.start(), end: selectable.end()),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
}

/// A faint "H1"/"H2"/… label drawn in the left gutter of a heading block.
/// Rendered via [AppFlowyTextDriver._buildBlockWrapper] — NOT as part of the
/// delta, so it never appears in the document text, in a copy, or in the
/// saved JSON.
///
/// All sizes are DOCUMENT units: the page is laid out at canonical size inside
/// a FittedBox (see page_space.dart), so the tag scales with the page exactly
/// as the heading text does — no per-window/dpi math needed.
///
/// `fontSize` and `height` are pinned to the body's metrics so the tag reads
/// as a caption, not a second heading. If the driver's DefaultTextStyle clamp
/// in `buildEditor` is ever removed or moved, this stays visually correct
/// instead of inheriting the heading's (huge) inherited style.
class _HeadingWithLevelTag extends StatelessWidget {
  const _HeadingWithLevelTag({required this.level, required this.child});

  final int level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // 2px down so the tag lands on the heading's first baseline;
          // 6px right so it never kisses the heading's first glyph.
          padding: const EdgeInsets.only(top: 4, right: 3),
          child: Opacity(
            opacity: 0.8,
            child: Text(
              'H$level',
              style: TextStyle(
                fontSize: kBaseFontSize * 0.6,
                height: kLineHeight,
                fontWeight: FontWeight.w700,
                color: context.cerebrum.brand.accent,
              ),
            ),
          ),
        ),
        // Expanded, not Flexible: headings are full-width (their own
        // textAlign decides where the glyphs sit), so the child needs the
        // remaining space, not a shrink-wrap fit.
        Expanded(child: child),
      ],
    );
  }
}
