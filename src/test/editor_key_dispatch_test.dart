import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart'
    as commands;

/// Proves whether Escape / Backspace actually REACH our command shortcut
/// handlers through AppFlowyEditor's real key dispatch.
///
/// Every other vim test in this repo calls `shortcut.handler(editorState)`
/// directly. That skips `KeyboardServiceWidget._onKeyEvent` entirely — the
/// loop that iterates `commandShortcutEvents` and calls
/// `canRespondToRawKeyEvent`. A handler can be perfectly correct and still be
/// unreachable because the key never gets dispatched, which is exactly the
/// failure these tests exist to catch.
Future<void> _pumpEditor(
  WidgetTester tester,
  VimModeController mode,
  EditorState state, {
  bool autoFocus = true,
  FocusNode? focusNode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          autoFocus: autoFocus,
          focusNode: focusNode,
          // Without this the scroll service calls jumpTo() on selection
          // change, which needs a real Scrollable and throws a TypeError
          // mid-frame. That aborts the build before the keyboard service
          // finishes wiring, so keys silently go nowhere — a harness
          // artifact that would look exactly like the real bug.
          disableScrollService: true,
          commandShortcutEvents: [
            ...commands.EditorShortcuts.getCustomShortcuts(mode),
            ...standardCommandShortcutEvents,
          ],
          characterShortcutEvents: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EditorState _stateWithText() {
  final state = EditorState(
    document: Document(
      root: Node(type: 'document', children: [paragraphNode(text: 'hello')]),
    ),
  );
  state.updateSelectionWithReason(
    Selection.collapsed(Position(path: [0], offset: 5)),
    reason: SelectionUpdateReason.uiEvent,
  );
  return state;
}

void main() {
  testWidgets('Escape reaches the vim normal-mode shortcut', (tester) async {
    final mode = VimModeController(VimMode.insert);
    final state = _stateWithText();

    await _pumpEditor(tester, mode, state);

    expect(mode.value, VimMode.insert, reason: 'precondition');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      mode.value,
      VimMode.normal,
      reason: 'Escape must flip insert -> normal through real dispatch',
    );
  });

  testWidgets('Escape reaches the handler even in analysis mode', (
    tester,
  ) async {
    final mode = VimModeController(VimMode.analysis);
    final state = _stateWithText();

    await _pumpEditor(tester, mode, state);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      mode.value,
      VimMode.normal,
      reason: 'Escape must flip analysis -> normal through real dispatch',
    );
  });

  // The driver builds AppFlowyEditor with autoFocus:false and hands the
  // keyboard service its OWN FocusNode, relying on requestEditorFocus()
  // (a post-frame requestFocus) to give it the keyboard. autoFocus:true
  // never focuses in AppFlowy 6.x — it only overwrites the selection.
  // These mirror the driver's real configuration.
  testWidgets('Escape works with the driver config (autoFocus:false + node)', (
    tester,
  ) async {
    final mode = VimModeController(VimMode.insert);
    final state = _stateWithText();
    final node = FocusNode();

    await _pumpEditor(
      tester,
      mode,
      state,
      autoFocus: false,
      focusNode: node,
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue, reason: 'precondition: node must hold focus');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      mode.value,
      VimMode.normal,
      reason: 'Escape must work under the driver\'s own wiring',
    );
  });

  // The driver calls notifyListeners() on EVERY transaction, and
  // EditorSurface's AnimatedBuilder rebuilds driver.buildEditor(context) each
  // time — so a brand-new AppFlowyEditor widget is constructed on every
  // keystroke while reusing the same editorState + the same editorFocusNode.
  // AppFlowyEditor's didUpdateWidget sets `services = null`, rebuilding the
  // KeyboardServiceWidget and its inner Focus. If that Focus re-attach costs
  // the node its focus, every hardware key dies while IME typing (a separate
  // platform channel) keeps working.
  testWidgets('Escape survives rebuild churn with a reused FocusNode', (
    tester,
  ) async {
    final mode = VimModeController(VimMode.insert);
    final state = _stateWithText();
    final node = FocusNode();

    Widget build() => MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          autoFocus: false,
          focusNode: node,
          disableScrollService: true,
          commandShortcutEvents: [
            ...commands.EditorShortcuts.getCustomShortcuts(mode),
            ...standardCommandShortcutEvents,
          ],
          characterShortcutEvents: const [],
        ),
      ),
    );

    await tester.pumpWidget(build());
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue, reason: 'precondition');

    // Rebuild the editor the way the driver's transaction stream does.
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
    }

    debugPrint('FOCUS AFTER CHURN: ${node.hasFocus}');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      mode.value,
      VimMode.normal,
      reason: 'Escape must still work after the editor has been rebuilt',
    );
  });

  testWidgets('Backspace deletes text through real dispatch', (tester) async {
    final mode = VimModeController(VimMode.insert);
    final state = _stateWithText();

    await _pumpEditor(tester, mode, state);

    expect(state.document.root.children.first.delta!.toPlainText(), 'hello');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(
      state.document.root.children.first.delta!.toPlainText(),
      'hell',
      reason: 'Backspace must delete through real dispatch',
    );
  });
}