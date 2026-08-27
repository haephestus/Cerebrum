import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/editor/controllers/vim_move_controller.dart';

/// Non-printable / multi-key vim commands: Escape, duplicate line, gg/G.
///
/// IMPORTANT: 'dd' and 'gg' are NOT here. AppFlowyEditor's
/// [CommandShortcutEvent] matches a single key label per `command:`
/// string (see `Keybinding.keyCode`, which does a lookup like
/// `keyToCodeMapping[keyLabel]!`) — it has no concept of "this key
/// pressed twice". A command string like `'d d'` gets treated as one
/// literal (invalid) key label, so the lookup returns null and the `!`
/// throws — on *every* keystroke, not just 'd', because command
/// shortcuts are matched against every incoming key regardless of which
/// one was pressed. That's what was producing the null-check crash and
/// making the editor freeze after the first typed character.
///
/// 'dd' and 'gg' are implemented as character-shortcut sequences instead
/// — see [VimCharacterShortcuts] and [VimModeController.matchSequence].
///
/// Same failure mode bit the Escape shortcut too: the key label table
/// only recognizes 'escape', not 'esc' — a single wrong/unrecognized
/// label anywhere in the registered shortcuts is enough to crash the
/// lookup on every keystroke, since command shortcuts are matched
/// against all incoming keys. Double-check any new `command:` string
/// against AppFlowyEditor's `key_mapping.dart` table before adding it.
///
/// Every handler here still bails out with [KeyEventResult.ignored] when
/// the editor isn't in normal mode, so nothing here can eat a keystroke
/// while the user is typing.
class EditorShortcuts {
  static List<CommandShortcutEvent> getCustomShortcuts(VimModeController mode) {
    return [
      _duplicateLineShortcut(mode),
      _moveToDocEndShortcut(mode),
      _escapeToNormalModeShortcut(mode),
    ];
  }

  // Ctrl+D = duplicate line
  static CommandShortcutEvent _duplicateLineShortcut(VimModeController mode) {
    return CommandShortcutEvent(
      key: 'Duplicate line',
      getDescription: () => 'Duplicate the current line',
      command: 'ctrl+d',
      handler: (editorState) => _duplicateLineHandler(editorState, mode),
    );
  }

  static KeyEventResult _duplicateLineHandler(
    EditorState editorState,
    VimModeController mode,
  ) {
    if (!mode.isNormal) return KeyEventResult.ignored;

    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    final transaction = editorState.transaction;
    final newNode = node.copyWith();
    transaction.insertNode(selection.end.path, newNode);
    editorState.apply(transaction);

    return KeyEventResult.handled;
  }

  // G = document end
  static CommandShortcutEvent _moveToDocEndShortcut(VimModeController mode) {
    return CommandShortcutEvent(
      key: 'Move to document end (vim G)',
      getDescription: () => 'Move the cursor to the end of the document',
      command: 'shift+g',
      handler: (editorState) => _moveToDocEndHandler(editorState, mode),
    );
  }

  static KeyEventResult _moveToDocEndHandler(
    EditorState editorState,
    VimModeController mode,
  ) {
    if (!mode.isNormal) return KeyEventResult.ignored;

    final lastNode = editorState.document.last;
    if (lastNode == null) return KeyEventResult.ignored;

    final delta = lastNode.delta;
    final offset = delta?.length ?? 0;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: lastNode.path, offset: offset)),
      reason: SelectionUpdateReason.uiEvent,
    );

    return KeyEventResult.handled;
  }

  // ESC = exit to normal mode (for vim modal editing)
  static CommandShortcutEvent _escapeToNormalModeShortcut(
    VimModeController mode,
  ) {
    return CommandShortcutEvent(
      key: 'Escape to normal mode',
      getDescription: () => 'Exit insert mode',
      command: 'escape',
      handler: (editorState) => _escapeHandler(mode),
    );
  }

  static KeyEventResult _escapeHandler(VimModeController mode) {
    mode.enterNormalMode();
    return KeyEventResult.handled;
  }
}

/// Single-character vim keys — h j k l w b 0 $ i, plus the 'dd'/'gg'
/// sequences. These MUST be [CharacterShortcutEvent]s, not
/// [CommandShortcutEvent]s: AppFlowyEditor only consults character
/// shortcuts to decide whether to swallow or insert a typed character.
/// In normal mode the handler consumes the key and moves the cursor; in
/// insert mode it returns false and the letter is typed exactly like any
/// other character.
///
/// Also registers a catch-all handler (see [_unmappedPrintable]) for
/// every other printable character. Without it, normal mode was an
/// allowlist rather than a real modal block — h/j/k/l/etc. were
/// intercepted, but any other key (e, a, digits, punctuation,
/// shift-cased letters, ...) had no handler at all and fell straight
/// through to ordinary typing regardless of mode. The catch-all closes
/// that gap by swallowing unmapped keys in normal mode and letting them
/// through untouched in insert mode.
class VimCharacterShortcuts {
  /// Every printable character NOT already handled as a vim motion
  /// above. Without this, normal mode is an allowlist instead of a real
  /// modal block: h/j/k/l/w/b/0/$/i/d/g get intercepted, but anything
  /// else (e/a/s/digits/punctuation/space/shift-cased letters like
  /// H/J/K/L/.../...) has no matching [CharacterShortcutEvent] at all,
  /// custom or standard, so it falls straight through to
  /// `standardCharacterShortcutEvents` and gets typed into the document
  /// regardless of mode. Real vim blocks by default and whitelists
  /// motions/commands; this whitelisted motions only and left
  /// everything else at its default (typing) behavior.
  ///
  /// The catch-all below swallows those keys while in normal mode and
  /// lets them through untouched in insert mode — same
  /// swallow-in-normal/pass-in-insert pattern as [_navOrType].
  ///
  /// Built as `allPrintable - alreadyMapped` (rather than hand-typing
  /// the exclusion list) specifically so a future addition to the
  /// motion list above doesn't silently double-register that character
  /// here too.
  ///
  /// NOTE: this makes unmapped keys true no-ops in normal mode rather
  /// than vim commands — real vim gives many of these single-letter
  /// meanings (x = delete char, a/A = append, o/O = open line, etc.).
  /// None of that is implemented here yet; this only closes the
  /// "normal mode doesn't actually block typing" gap. `G` (shift+g) is
  /// excluded below even though nothing else maps it as a *character*,
  /// because it's already handled as a [CommandShortcutEvent] in
  /// [EditorShortcuts] and command shortcuts are checked first — adding
  /// it here would just be dead code.
  static const _alreadyMapped = {
    'h',
    'j',
    'k',
    'l',
    'w',
    'b',
    '0',
    r'$',
    'i',
    'd',
    'g',
    'G',
  };

  static const _allPrintable =
      'abcdefghijklmnopqrstuvwxyz'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      '0123456789'
      ' !"#%&\'()*+,-./:;<=>?@[\\]^_`{|}~';

  static final _unmappedPrintable =
      _allPrintable
          .split('')
          .where((c) => !_alreadyMapped.contains(c))
          .toList();

  static List<CharacterShortcutEvent> getCharacterShortcuts(
    VimModeController mode,
  ) {
    return [
      CharacterShortcutEvent(
        key: 'vim left',
        character: 'h',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _moveCharacter(editorState, delta: -1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim down',
        character: 'j',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _moveToSiblingLine(editorState, delta: 1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim up',
        character: 'k',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _moveToSiblingLine(editorState, delta: -1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim right',
        character: 'l',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _moveCharacter(editorState, delta: 1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim word forward',
        character: 'w',
        handler:
            (editorState) => _navOrType(
              mode,
              () => editorState.moveCursorForward(SelectionMoveRange.word),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim word backward',
        character: 'b',
        handler:
            (editorState) => _navOrType(
              mode,
              () => editorState.moveCursorBackward(SelectionMoveRange.word),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim line start',
        character: '0',
        handler: (editorState) => _handleLineStart(mode, editorState),
      ),
      CharacterShortcutEvent(
        key: 'vim line end',
        character: r'$',
        handler: (editorState) => _handleLineEnd(mode, editorState),
      ),
      CharacterShortcutEvent(
        key: 'vim enter insert mode',
        character: 'i',
        handler: (editorState) => _handleEnterInsert(mode, editorState),
      ),
      CharacterShortcutEvent(
        key: 'vim delete line (dd)',
        character: 'd',
        handler: (editorState) => _handleDeleteLine(mode, editorState),
      ),
      CharacterShortcutEvent(
        key: 'vim doc start (gg)',
        character: 'g',
        handler: (editorState) => _handleDocStart(mode, editorState),
      ),

      // Catch-all: every printable character not already mapped above
      // (see [_unmappedPrintable]'s doc comment for why this is
      // necessary — normal mode was previously an allowlist, not an
      // actual block). Swallows the key while in normal mode; falls
      // through to normal typing in insert mode.
      for (final c in _unmappedPrintable)
        CharacterShortcutEvent(
          key: 'vim block unmapped key "$c" in normal mode',
          character: c,
          handler: (editorState) async => mode.isNormal,
        ),
    ];
  }

  /// Runs [action] and swallows the key if in normal mode; otherwise lets
  /// the character type normally (false = "I didn't handle this").
  static Future<bool> _navOrType(
    VimModeController mode,
    void Function() action,
  ) async {
    if (!mode.isNormal) return false;
    action();
    return true;
  }

  /// Same as [_navOrType], but for an [action] that's itself async (needed
  /// because [_moveToSiblingLine] awaits nothing today but is written as
  /// async for symmetry / future-proofing against APIs that do).
  static Future<bool> _navOrTypeAsync(
    VimModeController mode,
    Future<void> Function() action,
  ) async {
    if (!mode.isNormal) return false;
    await action();
    return true;
  }

  /// Moves the collapsed cursor to the same column on the next
  /// ([delta] = 1) or previous ([delta] = -1) sibling node, instead of
  /// going through `moveCursorForward`/`moveCursorBackward` with
  /// `SelectionMoveRange.line`. That API's up/down direction turned out
  /// to be inconsistent/unpredictable in practice; walking to the
  /// sibling path directly is unambiguous regardless of what that helper
  /// does internally.
  ///
  /// At the first/last line this is a no-op (still swallows the
  /// keystroke — nothing to fall through to in normal mode).
  static Future<void> _moveToSiblingLine(
    EditorState editorState, {
    required int delta,
  }) async {
    final selection = editorState.selection;
    if (selection == null) return;

    final path = selection.end.path;
    if (path.isEmpty) return;

    final targetPath = [...path.sublist(0, path.length - 1), path.last + delta];
    final targetNode = editorState.getNodeAtPath(targetPath);
    if (targetNode == null) return; // already at the first/last line

    final targetDelta = targetNode.delta;
    final maxOffset = targetDelta?.length ?? 0;
    final offset = selection.end.offset.clamp(0, maxOffset);

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: targetNode.path, offset: offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// Moves the collapsed cursor one character left ([delta] = -1) or
  /// right ([delta] = 1), stepping across node boundaries at the
  /// start/end of a line. Same rationale as [_moveToSiblingLine]:
  /// `moveCursorForward`/`moveCursorBackward` with
  /// `SelectionMoveRange.character` turned out to be as unreliable here
  /// as it was for line movement, so this steps the offset directly
  /// instead of trusting that helper's notion of forward/backward.
  static Future<void> _moveCharacter(
    EditorState editorState, {
    required int delta,
  }) async {
    final selection = editorState.selection;
    if (selection == null) return;

    final path = selection.end.path;
    if (path.isEmpty) return;

    final node = editorState.getNodeAtPath(path);
    final currentLength = node?.delta?.length ?? 0;
    final newOffset = selection.end.offset + delta;

    if (newOffset >= 0 && newOffset <= currentLength) {
      // Still within the current line — just shift the offset.
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: path, offset: newOffset)),
        reason: SelectionUpdateReason.uiEvent,
      );
      return;
    }

    // Crossed a line boundary: step to the adjacent node, landing at its
    // far edge (end of the previous line for delta<0, start of the next
    // line for delta>0) — matching how h/l wrap across lines in vim.
    final targetPath = [...path.sublist(0, path.length - 1), path.last + delta];
    final targetNode = editorState.getNodeAtPath(targetPath);
    if (targetNode == null) return; // already at document start/end

    final targetLength = targetNode.delta?.length ?? 0;
    final targetOffset = delta < 0 ? targetLength : 0;

    editorState.updateSelectionWithReason(
      Selection.collapsed(
        Position(path: targetNode.path, offset: targetOffset),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  static Future<bool> _handleLineStart(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal) return false;

    final selection = editorState.selection;
    if (selection == null) return false;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: selection.end.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }

  static Future<bool> _handleLineEnd(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal) return false;

    final selection = editorState.selection;
    if (selection == null) return false;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return false;

    final delta = node.delta;
    if (delta == null) return false;

    editorState.updateSelectionWithReason(
      Selection.collapsed(
        Position(path: selection.end.path, offset: delta.length),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }

  /// 'i' enters insert mode from normal mode and swallows the keystroke
  /// (no literal "i" typed). If already in insert mode, 'i' is just a
  /// letter — let it through.
  ///
  /// After flipping the mode we RE-ASSERT the collapsed caret. Entering insert
  /// via a swallowed 'i' does no text transaction, so AppFlowy never re-engages
  /// its cursor overlay / text input for the new mode — the first char typed
  /// then races the mode-change rebuild and the caret vanishes. Doing a real
  /// edit (the '/' menu) is what otherwise "fixes" it; re-asserting the
  /// selection reproduces that nudge without inserting anything. Deferred to a
  /// post-frame callback so it lands AFTER this key event's own rebuild rather
  /// than inside it (the collision the driver's caching comment describes).
  static Future<bool> _handleEnterInsert(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal) return false;
    mode.enterInsertMode();
    final sel = editorState.selection;
    if (sel != null && sel.isCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editorState.updateSelectionWithReason(
          Selection.collapsed(sel.start),
          reason: SelectionUpdateReason.uiEvent,
        );
      });
    }
    return true;
  }

  /// 'dd' — delete current line. First 'd' in normal mode is always
  /// swallowed (it's a pending operator, same as real vim); the second
  /// 'd' within the sequence window performs the delete.
  static Future<bool> _handleDeleteLine(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal) return false;
    if (!mode.matchSequence('d')) return true; // first 'd': just swallow it

    final selection = editorState.selection;
    if (selection == null) return true;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return true;

    final transaction = editorState.transaction;
    transaction.deleteNode(node);
    editorState.apply(transaction);
    return true;
  }

  /// 'gg' — move to document start. Same pending-sequence pattern as
  /// 'dd' above.
  static Future<bool> _handleDocStart(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal) return false;
    if (!mode.matchSequence('g')) return true; // first 'g': just swallow it

    final firstNode = editorState.document.first;
    if (firstNode == null) return true;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: firstNode.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }
}
