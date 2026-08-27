import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/editor/helpers/editor_commands.dart';
import 'package:cerebrum/ui/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/editor/controllers/text_editing_driver.dart';
// NEW: the proper code block builder (syntax highlighting, language
// switcher, copy button) — path assumes you saved it at
// features/editor/blocks/code_block/code_block_component.dart; adjust
// to wherever you actually put the file.
import 'package:cerebrum/ui/editor/blocks/code_block/code_block_component.dart';
import 'package:cerebrum/ui/editor/blocks/ai_block/ai_block_component.dart';

/// AppFlowy-backed [TextEditingDriver]. This is the only file that should
/// import `appflowy_editor` — everything above it (NoteEditorController,
/// EditorSurface, EditorScaffold) works against the interface, not this.
class AppFlowyTextDriver extends ChangeNotifier
    implements TextEditingDriver, VimModeAware {
  AppFlowyTextDriver({
    Map<String, dynamic>? initialDocumentJson,
    int? initialCaretBlockIndex,
    int? initialCaretOffset,
    bool autoFocus = false,
    bool seedCaret = true,
  }) {
    _autoFocus = autoFocus;
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
  bool _autoFocus = false;

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
  // own items we build a replacement via `customSlashCommand(...)` and
  // swap it in for the default one via `removeWhere`, same pattern
  // AppFlowy's own code-block extension example uses.
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
  late final Map<String, BlockComponentBuilder> _blockComponentBuilders = {
    ...standardBlockComponentBuilderMap,
    kCodeBlockType: CodeBlockComponentBuilder(),
    // SCAFFOLD: inline AI-feedback block (read-only, generation is a TODO).
    kAiBlockType: AiBlockComponentBuilder(),
  };

  late final List<SelectionMenuItem> _slashMenuItems = [
    ...standardSelectionMenuItems,
    _headingMenuItem(4),
    _headingMenuItem(5),
    _headingMenuItem(6),
    _codeBlockMenuItem(),
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
      icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
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
    ...VimCharacterShortcuts.getCharacterShortcuts(vimMode),
    customSlashCommand(_slashMenuItems),
    ...standardCharacterShortcutEvents
      ..removeWhere((element) => element == slashCommand),
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
      icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
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

  @override
  final VimModeController vimMode = VimModeController();

  /// Exposed for anything AppFlowy-specific that needs it (there isn't
  /// much reason to reach for this outside of this file/tests).
  EditorState get editorState => _editorState;

  /// Fires whenever the selection changes (caret move, tap, range). Used by the
  /// analysis popover to react to which block the caret is in. This is the raw
  /// AppFlowy selection notifier, so listeners fire on every caret move.
  Listenable get selectionChanges => _editorState.selectionNotifier;

  /// The index of the TOP-LEVEL block the collapsed caret sits in, or null when
  /// there's no caret / it's a range / it's nested (e.g. inside a table cell).
  /// Used only for on-screen positioning (rectOfBlock); analysis is keyed by the
  /// stable [selectedBlockId], not this position.
  int? get selectedBlockIndex {
    final sel = _editorState.selection;
    if (sel == null || !sel.isCollapsed) return null;
    final path = sel.start.path;
    return path.length == 1 ? path.first : null;
  }

  /// The STABLE id of the top-level block the collapsed caret sits in, or null
  /// (same guards as [selectedBlockIndex]). This is the durable identity the
  /// daemon keys analysis to — it round-trips via documentJson, so tapping a
  /// block maps to its findings even after blocks above it are added/reordered.
  String? get selectedBlockId {
    final sel = _editorState.selection;
    if (sel == null || !sel.isCollapsed) return null;
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
    return AppFlowyEditor(
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

      // Off by default: with one editor per page, all pages auto-focusing at
      // once fights for the keyboard and surfaced the "Null check operator used
      // on a null value" on open. Only a page created to receive focus (e.g.
      // the freshly-merged page after a backspace-merge) sets this true so the
      // caret lands there.
      autoFocus: _autoFocus,
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
      // Code Block) via customSlashCommand — see
      // _characterShortcutEvents above. There is no separate
      // `selectionMenuItems` constructor param.
      characterShortcutEvents: _characterShortcutEvents,
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
      final state =
          EditorState(document: Document.fromJson({'document': docJson}));
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
    final count = jsonNodes.length < nodes.length
        ? jsonNodes.length
        : nodes.length;
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

  @override
  void dispose() {
    _transactionSub.cancel();
    _scrollController.dispose();
    vimMode.dispose();
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
        isSelected ? const Color(0xFF2E7BF6) : const Color(0xFF44474D);
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
