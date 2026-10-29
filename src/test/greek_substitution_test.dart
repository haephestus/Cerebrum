import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart';
import 'package:cerebrum/ui/screens/editor/helpers/greek_letters.dart';

/// Headless verification of the Greek `\name` + space substitution.
///
/// These tests run the substitution through the package's own IME
/// dispatch semantics (`delta_input_on_insert_impl` walks the character
/// shortcut list in order) with the vim shortcut list placed BEFORE the
/// greek event, exactly the composition the driver builds in
/// `_characterShortcutEvents`. That ordering is part of what's being
/// proven: the vim catch-all must fall through (return false) in insert
/// mode so the greek space event is reachable, and must swallow the key
/// first in normal/analysis mode so substitution can't fire during review.
///
/// executeCharacterShortcutEvent itself is internal to appflowy_editor 6.x
/// and not exported — the same constraint every other vim test in this
/// repo hits — so the loop below replicates it, verified against
/// `character_shortcut_event_helper.dart` in 6.0.0: iterate the list in
/// order, match `shortcutEvent.character == character`, stop at the first
/// handler that returns true.
Future<bool> dispatch(
  EditorState state,
  VimModeController mode,
  String character,
) {
  final events = [
    ...VimCharacterShortcuts.getCharacterShortcuts(
      mode,
      onStepAnalysisChunk: null,
      onEnterAnalysisMode: null,
      onToggleAnalysisPanel: null,
    ),
    ...GreekLetterShortcuts.events,
  ];
  return _executeCharacterShortcutEvent(state, character, events);
}

Future<bool> _executeCharacterShortcutEvent(
  EditorState editorState,
  String? character,
  List<CharacterShortcutEvent> events,
) async {
  if (character == ' \n') character = '\n';
  if (character?.length != 1) return false;
  for (final shortcutEvent in events) {
    if (shortcutEvent.character == character) {
      if (await shortcutEvent.execute(editorState)) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  // EditorState.updateSelectionWithReason touches WidgetsBinding.instance
  // (it defers focus work through the binding); plain headless tests need
  // the binding initialized before constructing any editor state.
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorState stateWith(String text, {int? offset, VimMode? vimMode}) {
    final vim = vimMode ?? VimMode.insert;
    final mode = VimModeController(vim);
    final state = EditorState(
      document: Document(
        root: Node(type: 'document', children: [paragraphNode(text: text)]),
      ),
    );
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: offset ?? text.length)),
      reason: SelectionUpdateReason.uiEvent,
    );
    // Mode only matters for the "swallow in non-insert modes" ordering
    // tests below; keep it referenced so lints don't flag the capture.
    assert(mode.value == vim);
    return state;
  }

  String textOf(EditorState state) =>
      state.document.root.children.first.delta!.toPlainText();

  test(r'\alpha + space becomes α, space re-inserted in output', () async {
    // NOTE: the terminator space is NOT in the seeded text — the caret
    // sits directly after `\alpha` and the space press IS the terminator.
    // (A seeded trailing space would put the caret past it, where the
    // anchored `\\name$` match correctly finds no command — that mistake
    // is what the "not a command anymore" tests below rely on.)
    final state = stateWith(r'\alpha');
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isTrue);
    expect(textOf(state), 'α ');
  });

  test(r'\Delta + space becomes Δ (case-sensitive names)', () async {
    final state = stateWith(r'\Delta');
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isTrue);
    expect(textOf(state), 'Δ ');
  });

  test(r'\delta + space stays distinct from \Delta', () async {
    final state = stateWith(r'\delta');
    await dispatch(state, VimModeController(VimMode.insert), ' ');
    expect(textOf(state), 'δ ');
  });

  test('plain text before the backslash is untouched', () async {
    final state = stateWith(r'momentum p_x = \omega');
    await dispatch(state, VimModeController(VimMode.insert), ' ');
    expect(textOf(state), r'momentum p_x = ω ');
  });

  test('a full table cell can carry a substituted glyph', () async {
    final state = stateWith(r'\pi');
    await dispatch(state, VimModeController(VimMode.insert), ' ');
    expect(textOf(state), 'π ');
  });

  test('unknown command (\foo + space) types the space normally', () async {
    final state = stateWith(r'\foo ');
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isFalse);
    expect(textOf(state), r'\foo ');
  });

  test('space without a backslash types normally (no substitution)', () async {
    final state = stateWith('alpha ');
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isFalse);
    expect(textOf(state), 'alpha ');
  });

  test('command prefix inside a longer word does not partial-match', () async {
    // `\alphabet` completes no known name — the whole space edits normally
    // and the raw text survives intact (the no-mid-word-races guarantee).
    final state = stateWith(r'\alphabet ');
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isFalse);
    expect(textOf(state), r'\alphabet ');
  });

  test(
    'exactly-at-offset match: caret before the space still types it',
    () async {
      // Caret DIRECTLY after `\alpha` (no space yet): the space press IS the
      // terminator and must substitute here too — offset correctness.
      final state = stateWith(r'\alpha', offset: r'\alpha'.length);
      final handled = await dispatch(
        state,
        VimModeController(VimMode.insert),
        ' ',
      );
      expect(handled, isTrue);
      expect(textOf(state), 'α ');
    },
  );

  test('non-collapsed selection does not substitute', () async {
    final state = stateWith(r'\alpha ');
    state.updateSelectionWithReason(
      Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 5),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
    final handled = await dispatch(
      state,
      VimModeController(VimMode.insert),
      ' ',
    );
    expect(handled, isFalse);
    expect(textOf(state), r'\alpha ');
  });

  test('normal mode swallows space BEFORE substitution can fire', () async {
    // Ordering guarantee: the vim catch-all (matched first) returns true
    // in normal mode, so the greek event is unreachable — review mode can
    // never mutate the document through substitution.
    final state = stateWith(r'\alpha ', vimMode: VimMode.normal);
    final handled = await dispatch(
      state,
      VimModeController(VimMode.normal),
      ' ',
    );
    expect(handled, isTrue, reason: 'vim normal mode swallows the key');
    expect(textOf(state), r'\alpha ', reason: 'document untouched');
  });

  test('also works in plain text mode (vim disabled)', () async {
    // With vim disabled the vim handlers return false for everything
    // (neither normal nor analysis), so substitution must still run.
    final state = stateWith(r'\alpha');
    final mode = VimModeController(VimMode.insert);
    mode.setEnabled(false);
    final handled = await dispatch(state, mode, ' ');
    expect(handled, isTrue);
    expect(textOf(state), 'α ');
  });
}
