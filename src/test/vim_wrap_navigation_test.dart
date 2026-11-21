import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/features/editor/helpers/vim_move_controller.dart';
import 'package:cerebrum/features/editor/helpers/editor_commands.dart';

/// In-block (display-line) vim navigation: j/k must step through the
/// wrapped rows INSIDE one paragraph node before crossing to the
/// next block. Arrows already do this via Position.moveVertical;
/// vim now shares that path with a sibling-path fallback for
/// headless / layout-less states.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Long enough to wrap into several display rows at the default
  // test viewport: ~200 chars at 16pt in ~600px wraps repeatedly.
  final longText = ('alpha beta gamma delta epsilon zeta '
          'alpha beta gamma delta epsilon zeta '
          'alpha beta gamma delta epsilon zeta '
          'alpha beta gamma delta epsilon zeta ')
      .trim();

  EditorState wrapState() {
    final state = EditorState(
      document: Document(
        root: Node(
          type: 'page',
          children: [
            paragraphNode(text: longText),
            paragraphNode(text: 'tail'),
          ],
        ),
      ),
    );
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 3)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return state;
  }

  Future<void> pumpEditor(WidgetTester tester, EditorState state) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 500,
              child: AppFlowyEditor(
                editorState: state,
                editorScrollController: EditorScrollController(
                  editorState: state,
                  shrinkWrap: true,
                ),
                commandShortcutEvents: const [],
                characterShortcutEvents: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressJ(EditorState state, VimModeController mode) async {
    final shortcut = [
      ...EditorShortcuts.getCustomShortcuts(mode),
      ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
    ].singleWhere((e) => e.command == 'j' && e.key.contains('raw-key'));
    shortcut.execute(state);
  }

  Future<void> pressK(EditorState state, VimModeController mode) async {
    final shortcut = [
      ...EditorShortcuts.getCustomShortcuts(mode),
      ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
    ].singleWhere((e) => e.command == 'k' && e.key.contains('raw-key'));
    shortcut.execute(state);
  }

  testWidgets('j stays in the same wrapped paragraph before crossing blocks',
      (tester) async {
    final state = wrapState();
    final mode = VimModeController(VimMode.normal);
    await pumpEditor(tester, state);
    expect(state.selection!.start.path, [0]);
    expect(state.selection!.start.offset, 3);

    // Sanity: the paragraph really wraps (render box taller than one
    // row). Single-row height at the stock 16pt is ~24px; a wrapped
    // block is several times that.
    final height = state.getNodeAtPath([0])?.rect.height ?? 0;
    expect(height, greaterThan(60),
        reason: 'test precondition: long paragraph must wrap into multiple rows (height=$height)');

    await pressJ(state, mode);
    await tester.pumpAndSettle();
    expect(state.selection!.start.path, [0],
        reason: 'first j must stay inside the wrapped block, not skip to [1]');
    expect(state.selection!.start.offset, greaterThan(3),
        reason: 'j must advance within the block');

    // Walk further: must cross to [1] only after exhausting rows of [0].
    var crossed = false;
    for (var i = 0; i < 12 && !crossed; i++) {
      await pressJ(state, mode);
      await tester.pumpAndSettle();
      if (state.selection!.start.path.first == 1) crossed = true;
    }
    expect(crossed, isTrue, reason: 'repeated j eventually crosses blocks');

    final tailDelta = state.getNodeAtPath([1])?.delta?.length ?? 0;
    expect(state.selection!.start.offset, lessThanOrEqualTo(tailDelta));
  });

  testWidgets('k from a lower row of a wrapped paragraph steps up inside it',
      (tester) async {
    final state = wrapState();
    final mode = VimModeController(VimMode.normal);
    await pumpEditor(tester, state);

    // Move down twice first so we're on row ~3 of block 0.
    await pressJ(state, mode);
    await tester.pumpAndSettle();
    await pressJ(state, mode);
    await tester.pumpAndSettle();
    final midPath = List<int>.from(state.selection!.start.path);
    final midOffset = state.selection!.start.offset;
    expect(midPath.first, 0);

    await pressK(state, mode);
    await tester.pumpAndSettle();
    expect(state.selection!.start.path, [0],
        reason: 'k must stay inside the wrapped block');
    expect(state.selection!.start.offset, lessThan(midOffset),
        reason: 'k must move to an earlier offset');
  });

  testWidgets('visual j extends within the wrapped block', (tester) async {
    final state = wrapState();
    final mode = VimModeController(VimMode.normal);
    await pumpEditor(tester, state);

    // Enter visual mode (anchor at offset 3).
    final v = VimCharacterShortcuts.getCharacterShortcuts(mode)
        .singleWhere((e) => e.character == 'v');
    await v.handler(state);
    expect(mode.value, VimMode.visual);

    final shortcut = [
      ...EditorShortcuts.getCustomShortcuts(mode),
      ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
    ].singleWhere((e) => e.command == 'j' && e.key.contains('raw-key'));
    shortcut.execute(state);
    await tester.pumpAndSettle();

    final sel = state.selection!;
    expect(sel.isCollapsed, isFalse, reason: 'selection must have grown');
    // Both ends inside the wrapped block.
    expect(sel.start.path, [0]);
    expect(sel.end.path, [0]);
    expect(sel.end.offset, greaterThan(sel.start.offset));
    expect(mode.value, VimMode.visual);
  });

  test('h/l step over graphemes, not code units', () async {
    // "a" (1 unit) + "😀" (2 UTF-16 units, 1 grapheme) + "b" (1 unit).
    // l from 0 -> 1 (after 'a'), 1 -> 3 (skips the surrogate pair),
    // never 2. Same backward.
    EditorState mk(int offset) {
      final s = EditorState(
        document: Document(
          root: Node(
            type: 'document',
            children: [paragraphNode(text: 'a😀b')],
          ),
        ),
      );
      s.updateSelectionWithReason(
        Selection.collapsed(Position(path: [0], offset: offset)),
        reason: SelectionUpdateReason.uiEvent,
      );
      return s;
    }

    Future<int> press(String key, int from) async {
      final mode = VimModeController(VimMode.normal);
      final s = mk(from);
      final e = VimCharacterShortcuts.getCharacterShortcuts(mode)
          .singleWhere((ev) => ev.character == key);
      await e.handler(s);
      return s.selection!.start.offset;
    }

    expect(await press('l', 0), 1);
    expect(await press('l', 1), 3,
        reason: 'must skip the surrogate pair, not land at 2');
    expect(await press('h', 3), 1,
        reason: 'must step back over the whole grapheme');
    expect(await press('h', 1), 0);
  });

  test('e is the word-backward motion; b is not', () async {
    final mode = VimModeController(VimMode.normal);
    final chars = VimCharacterShortcuts.getCharacterShortcuts(mode);
    final eEvents = chars.where((e) => e.character == 'e').toList();
    expect(eEvents.length, 1,
        reason: 'e must not double-register via the catch-all '
            '(missing from _alreadyMapped would add a second dead event)');
    expect(eEvents.single.key, 'vim word backward');

    final bEvents = chars.where((e) => e.character == 'b').toList();
    expect(bEvents.length, 1,
        reason: 'b must fall to the catch-all (swallowed no-op), not a motion');
    expect(bEvents.single.key, contains('unmapped'),
        reason: 'b should be swallowed by the catch-all, not move');

    final raw = VimCharacterShortcuts.getRawKeyVimShortcuts(mode);
    expect(raw.where((e) => e.command == 'e').length, 1,
        reason: 'raw-key e must exist for the IME-less path');
    expect(raw.where((e) => e.command == 'w').length, 1);
    expect(raw.where((e) => e.command == 'b').length, 0,
        reason: 'b must not have a raw motion anymore');
  });

  test('e swallows in normal mode, types in insert mode', () async {
    EditorState mk() {
      final s = EditorState(
        document: Document(
          root: Node(
            type: 'document',
            children: [paragraphNode(text: 'foo bar baz')],
          ),
        ),
      );
      s.updateSelectionWithReason(
        Selection.collapsed(Position(path: [0], offset: 8)),
        reason: SelectionUpdateReason.uiEvent,
      );
      return s;
    }

    final normalMode = VimModeController(VimMode.normal);
    final eNormal = VimCharacterShortcuts.getCharacterShortcuts(normalMode)
        .singleWhere((e) => e.character == 'e' && e.key.contains('word'));
    expect(await eNormal.handler(mk()), isTrue,
        reason: 'normal mode consumes e');

    final insertMode = VimModeController(VimMode.insert);
    final eInsert = VimCharacterShortcuts.getCharacterShortcuts(insertMode)
        .singleWhere((e) => e.character == 'e' && e.key.contains('word'));
    expect(await eInsert.handler(mk()), isFalse,
        reason: 'insert mode must type e normally');
  });

  testWidgets('arrow down/up step display rows like j/k, not block ends',
      (tester) async {
    final state = wrapState();
    final mode = VimModeController(VimMode.normal);
    await pumpEditor(tester, state);

    CommandShortcutEvent raw(String command) =>
        [
          ...EditorShortcuts.getCustomShortcuts(mode),
          ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
        ].singleWhere((e) => e.command == command);

    raw('arrow down').execute(state);
    await tester.pumpAndSettle();
    expect(state.selection!.start.path, [0],
        reason: 'ArrowDown must stay in the wrapped block like j');
    expect(state.selection!.start.offset, greaterThan(3));

    raw('arrow up').execute(state);
    await tester.pumpAndSettle();
    expect(state.selection!.start.path, [0],
        reason: 'ArrowUp must step up inside the wrapped block like k');
    expect(state.selection!.start.offset, lessThanOrEqualTo(30),
        reason: 'ArrowUp must not jump to the block end');
  });
}
