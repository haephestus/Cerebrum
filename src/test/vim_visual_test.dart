import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/blocks/table/table_keys.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart';

/// Headless verification of vim `v` — character-wise visual select.
///
/// Scope checked headlessly:
///   * `v` enters visual mode with the anchor pinned at the caret;
///   * h/l/j/k/0/$ extend the selection from the HEAD (anchor fixed),
///     including movement BACK ACROSS the anchor (selection reversal);
///   * `d` deletes the selected content — even across block boundaries —
///     exits to normal mode, and restores a caret AppFlowy would otherwise
///     leave null (same trap the 'dd' test documents);
///   * `v` again / Escape collapse back to the head (normal mode);
///   * `i` abandons the selection to insert-at-selection-start;
///   * `o` swaps the endpoint with the anchor instead of opening a line;
///   * insert-mode `v` types normally (return false), analysis-mode `v`
///     is a swallowed no-op.
///
/// NOT headlessly testable (widget-backed `node.selectable`): the word
/// motions `w`/`b` — their visual branch shares the same extension path
/// but the stepping itself is live-only, exactly like normal-mode w/b.
///
/// Handlers are invoked directly on the events produced by
/// [VimCharacterShortcuts.getCharacterShortcuts] — the same limitation as
/// every other vim test in this repo (character shortcuts run through the
/// package's internal IME dispatch, which is not exported in 6.x).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<CharacterShortcutEvent> events(VimModeController mode) =>
      VimCharacterShortcuts.getCharacterShortcuts(
        mode,
        onStepAnalysisChunk: null,
        onEnterAnalysisMode: null,
        onToggleAnalysisPanel: null,
      );

  CharacterShortcutEvent eventFor(
    VimModeController mode,
    String character,
    String keyHint,
  ) {
    final eventsForMode = [...events(mode)];
    return eventsForMode.singleWhere(
      (e) => e.character == character && e.key.contains(keyHint),
    );
  }

  /// The raw-key (command shortcut) path — how j/k/h/l reach the editor
  /// when the IME isn't attached. Built through the same mode controller.
  CommandShortcutEvent rawEventFor(
    VimModeController mode,
    String command,
    String keyHint,
  ) {
    return [
      ...EditorShortcuts.getCustomShortcuts(mode),
      ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
    ].singleWhere((e) => e.command == command && e.key.contains(keyHint));
  }

  EditorState getState(
    List<String> lines, {
    required int nodeIndex,
    required int offset,
  }) {
    final state = EditorState(
      document: Document(
        root: Node(
          type: 'document',
          children: [for (final line in lines) paragraphNode(text: line)],
        ),
      ),
    );
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [nodeIndex], offset: offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return state;
  }

  List<String> textOf(EditorState state) => [
    for (final child in state.document.root.children)
      child.delta?.toPlainText() ?? '',
  ];

  Selection sel(EditorState state) => state.selection!;

  test("'v' enters visual mode with the anchor pinned at the caret", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 3);

    final handled = await eventFor(mode, 'v', 'visual').execute(state);

    expect(handled, isTrue);
    expect(mode.value, VimMode.visual);
    // Compare the record's fields — records with a List<int> field are
    // structurally unequal here because Dart list == is identity.
    expect(mode.visualAnchor!.path, [0]);
    expect(mode.visualAnchor!.offset, 3);
    expect(
      state.selection!.isCollapsed,
      isTrue,
      reason: 'selection starts collapsed; motion grows it',
    );
  });

  test(
    "'l' extends the selection forward; further 'l' keeps growing",
    () async {
      final mode = VimModeController(VimMode.normal);
      final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 1);
      await eventFor(mode, 'v', 'visual').execute(state);

      await eventFor(mode, 'l', 'right').execute(state);
      expect(
        sel(state),
        Selection(
          start: Position(path: [0], offset: 1),
          end: Position(path: [0], offset: 2),
        ),
      );

      await eventFor(mode, 'l', 'right').execute(state);
      expect(
        sel(state),
        Selection(
          start: Position(path: [0], offset: 1),
          end: Position(path: [0], offset: 3),
        ),
        reason: 'the anchor stays put; only the head advances',
      );
    },
  );

  test("'h' reverses the selection through and past the anchor", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 2);
    await eventFor(mode, 'v', 'visual').execute(state);

    // Forward twice, backward three times — vim reversal semantics.
    await eventFor(mode, 'l', 'right').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [0], offset: 4),
      ),
    );

    await eventFor(mode, 'h', 'left').execute(state);
    await eventFor(mode, 'h', 'left').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [0], offset: 2),
      ),
      reason: 'collapsed back onto the anchor',
    );

    await eventFor(mode, 'h', 'left').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 2),
      ),
      reason: 'past the anchor the selection flips to the other side',
    );
  });

  test("'j'/'k' extend across lines at the same column", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta', 'gamma'], nodeIndex: 0, offset: 2);
    await eventFor(mode, 'v', 'visual').execute(state);

    await eventFor(mode, 'j', 'down').execute(state);
    final afterJ = sel(state).normalized;
    expect(afterJ.start, Position(path: [0], offset: 2));
    expect(
      afterJ.end,
      Position(path: [1], offset: 2),
      reason: "'beta' (4 chars) can host column 2 unchanged",
    );

    await eventFor(mode, 'j', 'down').execute(state);
    expect(
      sel(state).normalized.end,
      Position(path: [2], offset: 2),
      reason: "'gamma' (5 chars) also clips nothing at col 2",
    );

    await eventFor(mode, 'k', 'up').execute(state);
    expect(
      sel(state).normalized.end,
      Position(path: [1], offset: 2),
      reason: 'the head walks back up the column',
    );
  });

  test("'j' clamps the column on short target lines", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef', 'xy'], nodeIndex: 0, offset: 4);
    await eventFor(mode, 'v', 'visual').execute(state);

    await eventFor(mode, 'j', 'down').execute(state);
    final selection = sel(state).normalized;
    expect(
      selection.end,
      Position(path: [1], offset: 2),
      reason: "target line has 2 chars; column 4 clamps to its end",
    );
  });

  test("'0' extends to the head line's column 0; '\$' to its end", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 3);
    await eventFor(mode, 'v', 'visual').execute(state);

    await eventFor(mode, '0', 'line start').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 3),
      ),
    );

    await eventFor(mode, r'$', 'line end').execute(state);
    // The head sits at col 0 after '0' (anchor still at col 3); '$'
    // extends the HEAD to the line end. vim: the selection shows 3..6.
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 3),
        end: Position(path: [0], offset: 6),
      ),
    );
  });

  test("'G' extends to document end", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);

    final handled = rawEventFor(mode, 'shift+g', 'document end').execute(state);

    expect(handled, KeyEventResult.handled);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [1], offset: 4),
      ),
    );
  });

  test("'d' deletes the selection and exits to normal mode", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 2);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);

    final handled = await eventFor(mode, 'd', 'delete line').execute(state);

    expect(handled, isTrue);
    expect(textOf(state), ['abef'], reason: 'offsets 2..4 (cd) removed');
    expect(mode.value, VimMode.normal);
    expect(mode.visualAnchor, isNull);
    expect(
      state.selection,
      isNotNull,
      reason: 'a delete must not orphan the caret',
    );
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 2)),
      reason: 'caret rests where the deleted text vacated',
    );
  });

  test("'d' deletes across block boundaries", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta', 'gamma'], nodeIndex: 0, offset: 3);
    await eventFor(mode, 'v', 'visual').execute(state);
    // Head down twice — selection spans end of line 0 through start of line 2.
    await eventFor(mode, 'j', 'down').execute(state);
    await eventFor(mode, 'j', 'down').execute(state);
    expect(sel(state).isCollapsed, isFalse);

    await eventFor(mode, 'd', 'delete line').execute(state);

    // The package's multi-node merge in deleteSelection keeps the text
    // BEFORE the start offset of the first node and AFTER the end offset
    // of the last one — 'gamma' only loses its first 3 chars because the
    // head rests on its col 3 when 'd' fires.
    expect(textOf(state), ['alpma']);
    expect(mode.value, VimMode.normal);
  });

  test("'x' behaves like 'd' in visual mode", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);

    await eventFor(mode, 'x', 'visual delete').execute(state);

    expect(textOf(state), ['acdef']);
    expect(mode.value, VimMode.normal);
  });

  test("'v' again exits, collapsing to the head", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);

    await eventFor(mode, 'v', 'visual').execute(state);

    expect(mode.value, VimMode.normal);
    expect(mode.visualAnchor, isNull);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 3)),
      reason: 'cursor survives at the last head position, like vim',
    );
    expect(textOf(state), ['abcdef'], reason: 'exiting deletes nothing');
  });

  test("Escape exits visual mode, collapsing to the head", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);

    final result = EditorShortcuts.getCustomShortcuts(
      mode,
    ).singleWhere((e) => e.command == 'escape').execute(state);

    expect(result, KeyEventResult.handled);
    expect(mode.value, VimMode.normal);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 2)),
    );
  });

  test("'i' from visual mode abandons the selection to its start", () async {
    final mode = VimModeController(VimMode.normal);
    // Backward-through anchor: extend from col 3 back to col 1 so the
    // selection's reading-order start is the head, not the anchor.
    final state = getState(['abcdef'], nodeIndex: 0, offset: 3);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'h', 'left').execute(state);
    await eventFor(mode, 'h', 'left').execute(state);

    final handled = await eventFor(mode, 'i', 'insert mode').execute(state);

    expect(handled, isTrue);
    expect(mode.value, VimMode.insert);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 1)),
      reason: "vim's 'i' in visual starts typing at the selection start",
    );
    expect(textOf(state), ['abcdef'], reason: "'i' itself deletes nothing");
  });

  test(
    "'o' in visual mode swaps endpoints instead of opening a line",
    () async {
      final mode = VimModeController(VimMode.normal);
      final state = getState(['abcdef'], nodeIndex: 0, offset: 1);
      await eventFor(mode, 'v', 'visual').execute(state);
      await eventFor(mode, 'l', 'right').execute(state);
      await eventFor(mode, 'l', 'right').execute(state);

      final handled = await eventFor(mode, 'o', 'open line').execute(state);

      expect(handled, isTrue);
      expect(mode.value, VimMode.visual, reason: 'stays in visual mode');
      expect(mode.visualAnchor!.path, [0]);
      expect(
        mode.visualAnchor!.offset,
        3,
        reason: 'the anchor becomes the old head',
      );
      expect(
        state.selection!.normalized,
        Selection(
          start: Position(path: [0], offset: 1),
          end: Position(path: [0], offset: 3),
        ),
        reason: 'the selection itself is unchanged by the swap',
      );
      expect(textOf(state), ['abcdef'], reason: "no extra line was opened");
    },
  );

  test("raw-key 'j'/'h' extend the selection (IME-less path)", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);

    rawEventFor(mode, 'j', 'raw-key').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [1], offset: 1),
      ),
    );

    rawEventFor(mode, 'h', 'raw-key').execute(state);
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [1], offset: 0),
      ),
      reason: 'h steps to col 0 of the SAME line — no wrap before col 0',
    );
  });

  test("raw-key arrows extend in visual mode too", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['alpha', 'beta'], nodeIndex: 0, offset: 2);
    await eventFor(mode, 'v', 'visual').execute(state);

    rawEventFor(mode, 'arrow down', 'raw-key').execute(state);
    expect(sel(state).normalized.end, Position(path: [1], offset: 2));

    rawEventFor(mode, 'arrow up', 'raw-key').execute(state);
    expect(
      sel(state).normalized.end,
      Position(path: [0], offset: 2),
      reason: 'arrow up walks the head back but the head stays the head',
    );
  });

  test("insert mode: 'v' is just a letter (falls through)", () async {
    final mode = VimModeController(VimMode.insert);
    final state = getState(['abc'], nodeIndex: 0, offset: 0);

    final handled = await eventFor(mode, 'v', 'visual').execute(state);

    expect(handled, isFalse, reason: 'must reach the IME and type');
    expect(mode.value, VimMode.insert);
  });

  test('analysis mode: v is a swallowed no-op', () async {
    final mode = VimModeController(VimMode.analysis);
    final state = getState(['abc'], nodeIndex: 0, offset: 0);
    final before = state.selection;

    final handled = await eventFor(mode, 'v', 'visual').execute(state);

    expect(handled, isTrue);
    expect(mode.value, VimMode.analysis);
    expect(state.selection, before);
  });

  test("'n'/'o'/'q' don't type through a live visual selection", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['abcdef'], nodeIndex: 0, offset: 1);
    await eventFor(mode, 'v', 'visual').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);

    // Each of these must be swallowed (return true) AND not fall through
    // to typing — a fall-through would replace the whole selection.
    expect(await eventFor(mode, 'n', 'chunk').execute(state), isTrue);
    expect(await eventFor(mode, 'q', 'panel').execute(state), isTrue);
    expect(
      (await eventFor(mode, 'y', 'unmapped').execute(state)),
      isTrue,
      reason: 'the catch-all must swallow in visual mode too',
    );
    expect(
      sel(state).normalized,
      Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 2),
      ),
      reason: 'selection untouched by non-motion keys',
    );
  });

  test('visual selection inside a table cell stays cell-contained', () async {
    // Head-in-cell branch: motions collapse to the head and behave like
    // normal mode inside the cell (no cross-cell extension). Assert the
    // selection doesn't escape the cell and mode stays visual.
    final mode = VimModeController(VimMode.normal);
    final cellPara = paragraphNode(text: 'cell');
    final cell = Node(
      type: CerebrumTableCellKeys.type, // 'table/cell' — matches the fork
      children: [cellPara],
      attributes: {'rowPosition': 0, 'colPosition': 0},
    );
    final state = EditorState(
      document: Document(
        root: Node(
          type: 'document',
          children: [
            Node(type: 'table', children: [cell]),
            paragraphNode(text: 'after'),
          ],
        ),
      ),
    );
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0, 0, 0], offset: 1)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await eventFor(mode, 'v', 'visual').execute(state);
    expect(mode.value, VimMode.visual);

    // Right twice: only limited by the cell text length; the head must
    // stay within the cell paragraph.
    await eventFor(mode, 'l', 'right').execute(state);
    await eventFor(mode, 'l', 'right').execute(state);
    expect(mode.value, VimMode.visual);
    expect(sel(state).normalized.end.path, [
      0,
      0,
      0,
    ], reason: 'visual h/l never escapes the cell');
    // Down from the cell: same containment (the cell router eats it).
    await eventFor(mode, 'j', 'down').execute(state);
    expect(
      sel(state).normalized.end.path,
      [0, 0, 0],
      reason: 'j at the cell edge is swallowed, not an escape hatch',
    );
  });
}
