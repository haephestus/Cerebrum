import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart';

/// Headless verification of the 'o' rebinding: 'o' is now vim's
/// open-line-below command (new empty paragraph after the cursor's line,
/// insert mode on it) and the analysis-panel toggle moved to 'q'.
///
/// Handlers are invoked directly on the events produced by
/// [VimCharacterShortcuts.getCharacterShortcuts] — the same limitation as
/// every other vim test in this repo (character shortcuts run through the
/// package's internal IME dispatch, which is not exported in 6.x).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The full vim event list (same composition the driver builds), so
  // correct behavior can be asserted against the real dispatch INPUTS
  // rather than a single hand-picked event.
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

  test("'o' opens an empty line BELOW and flips to insert mode", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['first', 'second'], nodeIndex: 0, offset: 2);

    final handled = await eventFor(mode, 'o', 'open line').execute(state);

    expect(handled, isTrue, reason: 'normal mode consumes the key');
    expect(mode.value, VimMode.insert, reason: "vim 'o' enters insert mode");
    expect(
      textOf(state),
      ['first', '', 'second'],
      reason: "new blank paragraph inserted after the cursor's line",
    );
    expect(
      state.selection,
      Selection.collapsed(Position(path: [1], offset: 0)),
      reason: 'caret rests at the start of the new line',
    );
  });

  test("'o' at line end does not split the line's text", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['hello'], nodeIndex: 0, offset: 5);

    await eventFor(mode, 'o', 'open line').execute(state);

    // vim's 'o' never divides the line: the char stays whole and the new
    // line appears after it. (A caret-position split producing el/he/llo
    // halves would be 'S'-style behavior, not 'o'.)
    expect(textOf(state), ['hello', '']);
  });

  test("'o' mid-line does not split the line either", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['hello'], nodeIndex: 0, offset: 2);

    await eventFor(mode, 'o', 'open line').execute(state);

    expect(textOf(state), ['hello', '']);
  });

  test(
    "'o' inside a nested path (table-cell paragraph) opens after it",
    () async {
      final mode = VimModeController(VimMode.normal);
      final cell = Node(
        type: 'table/cell',
        children: [paragraphNode(text: 'cell text')],
      );
      final state = EditorState(
        document: Document(root: Node(type: 'document', children: [cell])),
      );
      state.updateSelectionWithReason(
        Selection.collapsed(Position(path: [0, 0], offset: 4)),
        reason: SelectionUpdateReason.uiEvent,
      );

      await eventFor(mode, 'o', 'open line').execute(state);

      // path.next on the cell paragraph ([0,0] -> [0,1]) inserts a sibling,
      // not a child — vim's 'o' opens beside the line, never inside it.
      expect(cell.children, hasLength(2));
      expect(cell.children[0].delta!.toPlainText(), 'cell text');
      expect(cell.children[1].delta!.toPlainText(), '');
      expect(
        state.selection,
        Selection.collapsed(Position(path: [0, 1], offset: 0)),
      );
    },
  );

  test("'o' in ANALYSIS mode swallows without editing", () async {
    final mode = VimModeController(VimMode.analysis);
    final state = getState(['only'], nodeIndex: 0, offset: 0);

    final handled = await eventFor(mode, 'o', 'open line').execute(state);

    expect(handled, isTrue, reason: 'review mode swallows the key');
    expect(mode.value, VimMode.analysis, reason: 'mode unchanged');
    expect(textOf(state), ['only'], reason: 'document untouched');
  });

  test("'o' in INSERT mode falls through and types", () async {
    final mode = VimModeController(VimMode.insert);
    final state = getState(['ab'], nodeIndex: 0, offset: 1);

    final handled = await eventFor(mode, 'o', 'open line').execute(state);

    expect(handled, isFalse, reason: 'insert mode lets the letter type');
    expect(textOf(state), ['ab']);
    expect(mode.value, VimMode.insert);
  });

  test('raw-key o works without IME (whole-table selection case)', () {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['solo'], nodeIndex: 0, offset: 0);

    final raw = VimCharacterShortcuts.getRawKeyVimShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: null,
    ).singleWhere((e) => e.command == 'o');

    final result = raw.handler(state);

    expect(result, KeyEventResult.handled);
    expect(mode.value, VimMode.insert);
    expect(textOf(state), ['solo', '']);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [1], offset: 0)),
    );
  });

  test("raw-key o in ANALYSIS mode swallows without editing", () {
    final mode = VimModeController(VimMode.analysis);
    final state = getState(['only'], nodeIndex: 0, offset: 0);

    final raw = VimCharacterShortcuts.getRawKeyVimShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: null,
    ).singleWhere((e) => e.command == 'o');

    final result = raw.handler(state);

    expect(result, KeyEventResult.handled, reason: 'swallowed');
    expect(mode.value, VimMode.analysis, reason: 'mode unchanged');
    expect(textOf(state), ['only'], reason: 'document untouched');
  });

  test('raw-key o in INSERT mode ignores the key (letter types normally)', () {
    final mode = VimModeController(VimMode.insert);
    final state = getState(['ab'], nodeIndex: 0, offset: 1);

    final raw = VimCharacterShortcuts.getRawKeyVimShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: null,
    ).singleWhere((e) => e.command == 'o');

    expect(raw.handler(state), KeyEventResult.ignored);
    expect(textOf(state), ['ab']);
  });

  test("'O' opens an empty line ABOVE and flips to insert mode", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['first', 'second'], nodeIndex: 1, offset: 2);

    final handled = await eventFor(mode, 'O', 'open line').execute(state);

    expect(handled, isTrue, reason: 'normal mode consumes the key');
    expect(mode.value, VimMode.insert, reason: "vim 'O' enters insert mode");
    expect(
      textOf(state),
      ['first', '', 'second'],
      reason: "new blank paragraph inserted before the cursor's line",
    );
    expect(
      state.selection,
      Selection.collapsed(Position(path: [1], offset: 0)),
    );
  });

  test("'O' on the FIRST line lands on index 0", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['only line'], nodeIndex: 0, offset: 4);

    await eventFor(mode, 'O', 'open line').execute(state);

    // Path.previous of [0] clamps to [0], and insertNode at [0] inserts
    // BEFORE the first child — so the old line shifts to [1].
    expect(textOf(state), ['', 'only line']);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 0)),
    );
  });

  test("'O' mid-line does not split the line either", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['hello'], nodeIndex: 0, offset: 2);

    await eventFor(mode, 'O', 'open line').execute(state);

    expect(textOf(state), ['', 'hello']);
  });

  test("'O' in ANALYSIS mode swallows without editing", () async {
    final mode = VimModeController(VimMode.analysis);
    final state = getState(['only'], nodeIndex: 0, offset: 0);

    final handled = await eventFor(mode, 'O', 'open line').execute(state);

    expect(handled, isTrue, reason: 'review mode swallows the key');
    expect(mode.value, VimMode.analysis, reason: 'mode unchanged');
    expect(textOf(state), ['only'], reason: 'document untouched');
  });

  test("'O' in INSERT mode falls through and types", () async {
    final mode = VimModeController(VimMode.insert);
    final state = getState(['ab'], nodeIndex: 0, offset: 1);

    final handled = await eventFor(mode, 'O', 'open line').execute(state);

    expect(handled, isFalse, reason: 'insert mode lets the capital type');
    expect(textOf(state), ['ab']);
    expect(mode.value, VimMode.insert);
  });

  test("raw-key shift+o opens a line ABOVE without IME", () {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['solo'], nodeIndex: 0, offset: 0);

    final raw = VimCharacterShortcuts.getRawKeyVimShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: null,
    ).singleWhere((e) => e.command == 'shift+o');

    final result = raw.handler(state);

    expect(result, KeyEventResult.handled);
    expect(mode.value, VimMode.insert);
    expect(textOf(state), ['', 'solo']);
    expect(
      state.selection,
      Selection.collapsed(Position(path: [0], offset: 0)),
    );
  });

  test("'q' toggles the panel in NORMAL mode", () async {
    final mode = VimModeController(VimMode.normal);
    final state = getState(['r'], nodeIndex: 0, offset: 0);
    var toggled = 0;

    final found = events(
      mode,
    ).singleWhere((e) => e.character == 'q' && e.key.contains('panel'));
    // Rebuild with the hook wired, mirroring how the driver's callers pass
    // onToggleAnalysisPanel through.
    final wired = VimCharacterShortcuts.getCharacterShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: () => toggled++,
    ).singleWhere((e) => e.character == 'q');

    final handled = await wired.execute(state);

    expect(handled, isTrue, reason: 'swallowed: panel keys never type');
    expect(toggled, 1);
    expect(mode.value, VimMode.normal, reason: 'mode must not flip');
    expect(textOf(state), ['r'], reason: 'document untouched');
    // The unwired build must expose the SAME single 'q' event (no dead
    // duplicate from the catch-all).
    expect(found, isNotNull);
  });

  test(
    "'q' toggles the panel in ANALYSIS mode without leaving review",
    () async {
      final mode = VimModeController(VimMode.analysis);
      final state = getState(['r'], nodeIndex: 0, offset: 0);
      var toggled = 0;

      final wired = VimCharacterShortcuts.getCharacterShortcuts(
        mode,
        onStepAnalysisChunk: null,
        onEnterAnalysisMode: null,
        onToggleAnalysisPanel: () => toggled++,
      ).singleWhere((e) => e.character == 'q');

      final handled = await wired.execute(state);

      expect(handled, isTrue);
      expect(toggled, 1);
      expect(mode.value, VimMode.analysis, reason: 'stays in review mode');
    },
  );

  test("'q' in INSERT mode falls through and types", () async {
    final mode = VimModeController(VimMode.insert);
    final state = getState(['ab'], nodeIndex: 0, offset: 1);
    var toggled = 0;

    final wired = VimCharacterShortcuts.getCharacterShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: () => toggled++,
    ).singleWhere((e) => e.character == 'q');

    final handled = await wired.execute(state);

    expect(handled, isFalse, reason: 'insert mode lets the letter type');
    expect(toggled, 0);
  });

  test("exactly ONE 'q' event exists — no dead catch-all duplicate", () {
    final mode = VimModeController(VimMode.normal);
    final all = events(mode).where((e) => e.character == 'q').toList();

    expect(
      all.length,
      1,
      reason:
          "if 'q' were missing from _alreadyMapped the catch-all would "
          'register a second, dead q event here',
    );
  });

  test("exactly ONE 'O' event exists — no dead catch-all duplicate", () {
    final mode = VimModeController(VimMode.normal);
    final all = events(mode).where((e) => e.character == 'O').toList();

    expect(
      all.length,
      1,
      reason:
          "if 'O' were missing from _alreadyMapped the catch-all would "
          'register a second, dead O event here',
    );
  });
}
