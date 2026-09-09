import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/screens/editor/blocks/table/table_keys.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';

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
      // Must precede standardCommandShortcutEvents (it does — this whole
      // list is spliced before them), or the standard 'enter' handlers
      // (the table's enterInTableCell) mutate the doc in analysis mode.
      _swallowEnterInAnalysisShortcut(mode),
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
    if (!mode.isNormal && !mode.isAnalysis) return KeyEventResult.ignored;

    final lastNode = editorState.document.last;
    if (lastNode == null) return KeyEventResult.ignored;

    // Analysis review: move the whole-block highlight to the last block.
    if (mode.isAnalysis) {
      final selectable = lastNode.selectable;
      if (selectable != null) {
        editorState.updateSelectionWithReason(
          Selection(start: selectable.start(), end: selectable.end()),
          reason: SelectionUpdateReason.uiEvent,
        );
      }
      return KeyEventResult.handled;
    }

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

  // ENTER = new block / split node in every other mode. Analysis review is
  // READ-ONLY: the key must not create paragraphs here. This matters not just
  // for the obvious paragraph case (standard 'enter' splits a block) but for
  // the table too — with a whole-table block highlight, the standard
  // enterInTableCell handler sees the cells in range and inserts a fresh
  // paragraph AFTER the table. Returning `handled` in analysis mode consumes
  // the raw key before the standard command handlers run; `ignored` anywhere
  // else keeps normal/insert behavior untouched.
  //
  // NOTE: this only kills the COMMAND-level path. Enter also arrives as a
  // `'\n'` insertion through the IME when a delta node is selected, which is
  // routed by insertNewLine (standardCharacterShortcutEvents) and would split
  // the highlighted block — that path is blocked by the matching '\n'
  // character shortcut in VimCharacterShortcuts.getCharacterShortcuts, not here.
  static CommandShortcutEvent _swallowEnterInAnalysisShortcut(
    VimModeController mode,
  ) {
    return CommandShortcutEvent(
      key: 'Swallow Enter in analysis mode',
      getDescription: () =>
          'Prevent Enter from editing the document in analysis review mode',
      command: 'enter',
      handler: (editorState) {
        if (!mode.isAnalysis) return KeyEventResult.ignored;
        return KeyEventResult.handled;
      },
    );
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
    'n',
    'N',
    'o',
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
    VimModeController mode, {
    /// Analysis-review-mode chunk stepping wired by the driver: +1 = next
    /// chunk, -1 = previous. When non-null, 'n'/'N' step chunks while in
    /// analysis mode instead of doing anything else.
    void Function(int delta)? onStepAnalysisChunk,
    /// Wired by the scaffold so pressing 'n' in NORMAL mode lazy-loads the
    /// analysis before entering review mode. When null, 'n' just flips the vim
    /// mode to analysis with no chunks loaded.
    VoidCallback? onEnterAnalysisMode,
    /// Wired by the scaffold so pressing 'o' in ANALYSIS mode toggles the full
    /// analysis panel (the overview tab) without changing the vim mode.
    /// Distinct from [onEnterAnalysisMode] — that key switches modes, this one
    /// only shows/hides the panel.
    VoidCallback? onToggleAnalysisPanel,
  }) {
    return [
      CharacterShortcutEvent(
        key: 'vim left',
        character: 'h',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _navHorizontal(editorState, mode, delta: -1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim down',
        character: 'j',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _navVertical(editorState, mode, delta: 1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim up',
        character: 'k',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _navVertical(editorState, mode, delta: -1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim right',
        character: 'l',
        handler:
            (editorState) => _navOrTypeAsync(
              mode,
              () => _navHorizontal(editorState, mode, delta: 1),
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim word forward',
        character: 'w',
        handler: (editorState) async {
          // Analysis review is block-scope + highlight-only; word motion would
          // drop a typing caret. Swallow instead.
          if (mode.isAnalysis) return true;
          return _navOrType(
            mode,
            () => editorState.moveCursorForward(SelectionMoveRange.word),
          );
        },
      ),
      CharacterShortcutEvent(
        key: 'vim word backward',
        character: 'b',
        handler: (editorState) async {
          if (mode.isAnalysis) return true;
          return _navOrType(
            mode,
            () => editorState.moveCursorBackward(SelectionMoveRange.word),
          );
        },
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
        key: 'vim enter analysis mode / next chunk',
        character: 'n',
        handler:
            (editorState) => _handleAnalysisKey(
              mode,
              editorState,
              onStepAnalysisChunk,
              onEnterAnalysisMode,
              delta: 1,
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim previous analysis chunk',
        character: 'N',
        handler:
            (editorState) => _handleAnalysisKey(
              mode,
              editorState,
              onStepAnalysisChunk,
              onEnterAnalysisMode,
              delta: -1,
            ),
      ),
      CharacterShortcutEvent(
        key: 'vim toggle analysis panel',
        character: 'o',
        handler: (editorState) =>
            _handleToggleAnalysisPanel(mode, onToggleAnalysisPanel),
      ),
      // ENTER as an IME insertion (`'\n'`) must not edit while in analysis
      // mode. The raw-key swallow in EditorShortcuts can't cover this path:
      // character shortcuts are consulted by the text-input service AFTER the
      // key event is ignored by the command handlers, so insertNewLine would
      // still delete the highlighted block and split it here. Swallowing the
      // character (returning true) in analysis mode preempts that; any other
      // mode returns false and Enter keeps its standard behavior.
      CharacterShortcutEvent(
        key: 'vim swallow newline in analysis mode',
        character: '\n',
        handler: (editorState) async => mode.isAnalysis,
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
          handler: (editorState) async => mode.isNormal || mode.isAnalysis,
        ),
    ];
  }

  /// Runs [action] and swallows the key if in normal mode; otherwise lets
  /// the character type normally (false = "I didn't handle this").
  static Future<bool> _navOrType(
    VimModeController mode,
    void Function() action,
  ) async {
    if (!mode.isNormal && !mode.isAnalysis) return false;
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
    if (!mode.isNormal && !mode.isAnalysis) return false;
    await action();
    return true;
  }

  /// Raw-key (command-shortcut) fallbacks for the single-character vim keys
  /// whose handlers must keep working when AppFlowy's text-input service
  /// isn't attached.
  ///
  /// WHY: [CharacterShortcutEvent]s are only consulted by the text-input/IME
  /// service (`onInsert`), and that path only attaches when the current
  /// selection contains an editable (delta-bearing) node. A whole-TABLE
  /// selection contains no delta node — the table is a container, so
  /// `getNodesInSelection` yields just the table and the input service never
  /// opens. Every character shortcut then silently dies, which reads as "the
  /// table swallows navigation". CommandShortcutEvents run on raw key events
  /// via `KeyboardServiceWidget`'s `Focus.onKeyEvent` instead — no IME needed.
  ///
  /// These register j/k/l/h/n/N/o as command shortcuts. In normal/analysis
  /// mode the handler performs the same action as its character counterpart
  /// and returns `handled`, consuming the key before it can reach the IME —
  /// net effect identical to the character shortcut returning `true`. In
  /// insert mode it returns `ignored`, so the key still types normally.
  /// The character shortcuts are kept as-is: they resolve mode for the insert
  /// path and feed `_alreadyMapped`'s exclusion list.
  static List<CommandShortcutEvent> getRawKeyVimShortcuts(
    VimModeController mode, {
    void Function(int delta)? onStepAnalysisChunk,
    VoidCallback? onEnterAnalysisMode,
    VoidCallback? onToggleAnalysisPanel,
  }) {
    return [
      _rawNavShortcut('j', mode, delta: 1, horizontal: false),
      _rawNavShortcut('k', mode, delta: -1, horizontal: false),
      _rawNavShortcut('h', mode, delta: -1, horizontal: true),
      _rawNavShortcut('l', mode, delta: 1, horizontal: true),
      _rawAnalysisKeyShortcut(
        'n',
        mode,
        delta: 1,
        onStepAnalysisChunk: onStepAnalysisChunk,
        onEnterAnalysisMode: onEnterAnalysisMode,
      ),
      _rawAnalysisKeyShortcut(
        'shift+n',
        mode,
        delta: -1,
        onStepAnalysisChunk: onStepAnalysisChunk,
        onEnterAnalysisMode: onEnterAnalysisMode,
      ),
      _rawPanelToggleShortcut('o', mode, onToggleAnalysisPanel),
      // Arrow keys navigate BLOCKS in analysis mode. The table's own arrow
      // commands (tableCommands, in standardCommandShortcutEvents) return
      // `handled` at row/column edges even when they don't move — a collapsed
      // caret in a table cell can never leave the table with arrows. These
      // preempt that in review mode; normal/insert fall through untouched so
      // table editing keeps AppFlowy's native cell navigation.
      _rawArrowShortcut('arrow up', mode, delta: -1),
      _rawArrowShortcut('arrow down', mode, delta: 1),
      _rawArrowShortcut('arrow left', mode, delta: -1),
      _rawArrowShortcut('arrow right', mode, delta: 1),
    ];
  }

  static CommandShortcutEvent _rawNavShortcut(
    String command,
    VimModeController mode, {
    required int delta,
    required bool horizontal,
  }) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () =>
          '"$command" navigation that works without the IME attached',
      command: command,
      handler: (editorState) {
        if (!mode.isNormal && !mode.isAnalysis) {
          return KeyEventResult.ignored;
        }
        if (mode.isAnalysis) {
          _moveBlockInAnalysis(editorState, delta: delta);
        } else {
          _navInNormalMode(editorState, horizontal: horizontal, delta: delta);
        }
        return KeyEventResult.handled;
      },
    );
  }

  static CommandShortcutEvent _rawAnalysisKeyShortcut(
    String command,
    VimModeController mode, {
    required int delta,
    required void Function(int delta)? onStepAnalysisChunk,
    required VoidCallback? onEnterAnalysisMode,
  }) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () =>
          'Enter analysis mode / step chunk without the IME attached',
      command: command,
      handler: (editorState) {
        if (!mode.isNormal && !mode.isAnalysis) {
          return KeyEventResult.ignored;
        }
        if (mode.isAnalysis) {
          onStepAnalysisChunk?.call(delta);
          return KeyEventResult.handled;
        }
        if (delta > 0) {
          if (onEnterAnalysisMode != null) {
            onEnterAnalysisMode();
          } else {
            mode.enterAnalysisMode();
          }
        }
        return KeyEventResult.handled;
      },
    );
  }

  static CommandShortcutEvent _rawPanelToggleShortcut(
    String command,
    VimModeController mode,
    VoidCallback? onToggleAnalysisPanel,
  ) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () =>
          'Toggle the analysis panel without the IME attached',
      command: command,
      handler: (editorState) {
        if (!mode.isNormal && !mode.isAnalysis) {
          return KeyEventResult.ignored;
        }
        onToggleAnalysisPanel?.call();
        return KeyEventResult.handled;
      },
    );
  }

  static CommandShortcutEvent _rawArrowShortcut(
    String command,
    VimModeController mode, {
    required int delta,
  }) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () => '"$command" navigates blocks in analysis mode',
      command: command,
      handler: (editorState) {
        // Analysis mode only: arrows step between whole blocks so tables
        // can't pin the caret at a cell edge. Any other mode returns ignored
        // and AppFlowy's standard arrow/table commands handle the key.
        if (!mode.isAnalysis) return KeyEventResult.ignored;
        _moveBlockInAnalysis(editorState, delta: delta);
        return KeyEventResult.handled;
      },
    );
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

  /// ANALYSIS MODE: move the review cursor to the next/previous TOP-LEVEL block
  /// and select the entire block as a non-collapsed range — highlight, no
  /// typing caret. A table (or any nested structure) is ONE top-level block
  /// here, so navigation never descends into table cells and can't be swallowed
  /// by them.
  ///
  /// At the first/last block this is a no-op (still swallows the keystroke).
  static Future<void> _moveBlockInAnalysis(
    EditorState editorState, {
    required int delta,
  }) async {
    final selection = editorState.selection;
    if (selection == null) return;

    final path = selection.end.path;
    if (path.isEmpty) return;

    final children = editorState.document.root.children;
    if (children.isEmpty) return;

    final targetIndex = path.first + delta;
    if (targetIndex < 0 || targetIndex >= children.length) return;

    final target = children[targetIndex];
    final selectable = target.selectable;
    if (selectable == null) return;

    editorState.updateSelectionWithReason(
      Selection(start: selectable.start(), end: selectable.end()),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// h/l: character motion in normal mode, block-scope review motion in
  /// analysis mode (same direction: -1 = previous block, +1 = next).
  static Future<void> _navHorizontal(
    EditorState editorState,
    VimModeController mode, {
    required int delta,
  }) async {
    if (mode.isAnalysis) {
      await _moveBlockInAnalysis(editorState, delta: delta);
    } else {
      await _navInNormalMode(editorState, horizontal: true, delta: delta);
    }
  }

  /// j/k: sibling-line motion in normal mode, block-scope review motion in
  /// analysis mode.
  static Future<void> _navVertical(
    EditorState editorState,
    VimModeController mode, {
    required int delta,
  }) async {
    if (mode.isAnalysis) {
      await _moveBlockInAnalysis(editorState, delta: delta);
    } else {
      await _navInNormalMode(editorState, horizontal: false, delta: delta);
    }
  }

  /// Normal-mode j/k/h/l routing shared by the mapped (IME-attached) and
  /// raw-key (no IME) shortcut paths, so both behave identically.
  ///
  /// Inside a table cell the sibling-path math below is a dead end: the
  /// caret lives on the cell's nested paragraph, `path.last` only ever has
  /// that one sibling, and every key gets swallowed. Vim movement must
  /// become the same cell-to-cell movement the arrow keys produce — that
  /// is this app's stated intent for tables ("normal/insert fall through
  /// untouched so table editing keeps AppFlowy's native cell
  /// navigation"). The package's own arrow handlers can't be invoked
  /// here: they go through `selectionService`, which only exists while an
  /// editor widget is mounted, so [_moveInTableCell] reimplements their
  /// documented semantics on `updateSelectionWithReason` — the same API
  /// every other vim motion in this file uses — which keeps both the
  /// raw-key path and headless tests working.
  static Future<void> _navInNormalMode(
    EditorState editorState, {
    required bool horizontal,
    required int delta,
  }) async {
    if (_selectionIsInTableCell(editorState) &&
        _moveInTableCell(
          editorState,
          horizontal: horizontal,
          delta: delta,
        )) {
      return;
    }
    if (horizontal) {
      await _moveCharacter(editorState, delta: delta);
    } else {
      await _moveToSiblingLine(editorState, delta: delta);
    }
  }

  /// Native cell-to-cell movement inside a table, semantically identical
  /// to the package's table arrow commands (`tableCommands` in
  /// `table_commands.dart`) so j/k/h/l behave exactly like arrows here:
  ///
  ///   j/k -> move to the adjacent row's cell in the SAME column at the
  ///          same offset (clamped to the target cell's length);
  ///          swallowed at the first/last row, like vim's at-edge no-op.
  ///   h/l -> at a cell's start/end, move to the adjacent column's cell
  ///          in the SAME row, landing at its end/start; ANY other offset
  ///          returns false so the caller's character motion handles it.
  ///
  /// Table edges swallow the key (returns true) — the same "a collapsed
  /// caret in a table cell can never leave the table" guarantee the raw
  /// arrow shortcuts document for analysis mode. A non-collapsed or
  /// malformed selection defers to the caller.
  static bool _moveInTableCell(
    EditorState editorState, {
    required bool horizontal,
    required int delta,
  }) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;

    // Locate the owning cell. The caret normally sits on the paragraph
    // nested inside the cell; the cell node carries the row/col position.
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return false;
    final cell = node.type == CerebrumTableCellKeys.type
        ? node
        : (node.parent?.type == CerebrumTableCellKeys.type
              ? node.parent
              : null);
    if (cell == null) return false;

    final table = cell.parent;
    if (table == null) return false;

    final col = cell.attributes[CerebrumTableCellKeys.colPosition] as int?;
    final row = cell.attributes[CerebrumTableCellKeys.rowPosition] as int?;
    if (col == null || row == null) return false;

    // h/l only cross a cell boundary AT it — offset 0 for 'h', the cell's
    // end for 'l'. Mid-cell they defer to the caller's character motion,
    // exactly like the package's left/right-in-table-cell handlers.
    final sourceLength = node.delta?.length ?? 0;
    if (horizontal) {
      if (delta < 0 && selection.start.offset != 0) return false;
      if (delta > 0 && selection.start.offset != sourceLength) return false;
    }

    // Positions are 0-based, so the cell count is the last position + 1
    // (the package derives the same numbers from `table.children.last`).
    final numCols =
        (table.children.last.attributes[CerebrumTableCellKeys.colPosition]
                as int? ??
            0) +
        1;
    final numRows =
        (table.children.last.attributes[CerebrumTableCellKeys.rowPosition]
                as int? ??
            0) +
        1;

    final nextCol = horizontal ? col + delta : col;
    final nextRow = horizontal ? row : row + delta;
    if (nextCol < 0 ||
        nextCol >= numCols ||
        nextRow < 0 ||
        nextRow >= numRows) {
      return true; // table edge — swallow, exactly like the stock commands
    }

    // Same attribute lookup the fork's getCellNode uses.
    Node? target;
    for (final n in table.children) {
      if (n.attributes[CerebrumTableCellKeys.colPosition] == nextCol &&
          n.attributes[CerebrumTableCellKeys.rowPosition] == nextRow) {
        target = n;
        break;
      }
    }
    final targetChild = target?.children.firstOrNull;
    final targetDelta = targetChild?.delta;
    if (targetChild == null || targetDelta == null) return true;

    final offset = horizontal
        ? (delta < 0 ? targetDelta.length : 0)
        : (targetDelta.length > selection.start.offset
              ? selection.start.offset
              : targetDelta.length);

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: targetChild.path, offset: offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }

  /// True when the collapsed caret is inside a table cell. Mirrors the
  /// guard the package's `_hasSelectionAndTableCell` applies: a leaf text
  /// node whose parent is a 'table/cell' block (the fork's keys are kept
  /// byte-identical to the package's for document interchange).
  static bool _selectionIsInTableCell(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return false;
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return false;
    return node.type == CerebrumTableCellKeys.type ||
        node.parent?.type == CerebrumTableCellKeys.type;
  }

  static Future<bool> _handleLineStart(
    VimModeController mode,
    EditorState editorState,
  ) async {
    // Analysis review is highlight-only: line-start motion would collapse to a
    // typing caret. Swallow the key; the block cursor already covers the block.
    if (mode.isAnalysis) return true;
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
    // Analysis review is highlight-only (see [_handleLineStart]).
    if (mode.isAnalysis) return true;
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
    if (!mode.isNormal && !mode.isAnalysis) return false;
    mode.enterInsertMode();
    // Collapse to the selection START. Analysis navigation leaves WHOLE-BLOCK
    // selections behind; typing with one selected would replace the entire
    // block. In normal mode the selection is always collapsed already, so this
    // is a no-op there.
    final sel = editorState.selection;
    if (sel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editorState.updateSelectionWithReason(
          Selection.collapsed(sel.start),
          reason: SelectionUpdateReason.uiEvent,
        );
      });
    }
    return true;
  }

  /// 'n' in normal mode — enters analysis mode; 'n'/'N' in analysis mode —
  /// steps to the next/previous chunk (delta +1/-1) exactly like vim's
  /// search-result repeat. The first char typed into *any* vim mode is
  /// swallowed here, so the mode-change re-asserts the caret afterwards (see
  /// [_handleEnterInsert] for why).
  static Future<bool> _handleAnalysisKey(
    VimModeController mode,
    EditorState editorState,
    void Function(int delta)? onStepAnalysisChunk,
    VoidCallback? onEnterAnalysisMode, {
    required int delta,
  }) async {
    if (!mode.isNormal && !mode.isAnalysis) return false;

    // In analysis mode, 'n'/'N' step chunks — but only if chunk stepping is
    // wired (the analysis must be loaded). If not, swallow the key (nothing
    // to navigate to).
    if (mode.isAnalysis) {
      onStepAnalysisChunk?.call(delta);
      return true;
    }

    // Normal mode: 'n' enters analysis mode (only 'n', not 'N').
    if (delta > 0) {
      // Prefer the scaffold-wired hook so it can lazy-load the analysis before
      // flipping into review mode. Falls back to `mode.enterAnalysisMode()`
      // directly when not wired (e.g. standalone driver / no scaffold), which
      // still flips the mode but with nothing loaded to navigate.
      if (onEnterAnalysisMode != null) {
        onEnterAnalysisMode();
      } else {
        mode.enterAnalysisMode();
        final sel = editorState.selection;
        if (sel != null && sel.isCollapsed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            editorState.updateSelectionWithReason(
              Selection.collapsed(sel.start),
              reason: SelectionUpdateReason.uiEvent,
            );
          });
        }
      }
    }
    return true;
  }

  /// 'o' — toggle the full analysis panel (overview tab) while in ANALYSIS
  /// mode. This does NOT change the vim mode: 'n' still enters review mode,
  /// 'o' just opens/closes the panel. In normal mode the key is swallowed
  /// (it's a vim-mode key, not a typed character); in insert mode it types
  /// normally.
  static Future<bool> _handleToggleAnalysisPanel(
    VimModeController mode,
    VoidCallback? onToggleAnalysisPanel,
  ) async {
    if (mode.isAnalysis) {
      onToggleAnalysisPanel?.call();
    }
    // Swallow in normal AND analysis mode; fall through to typing in insert.
    return mode.isNormal || mode.isAnalysis;
  }

  /// 'dd' — delete current line. First 'd' in normal mode is always
  /// swallowed (it's a pending operator, same as real vim); the second
  /// 'd' within the sequence window performs the delete.
  static Future<bool> _handleDeleteLine(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (!mode.isNormal && !mode.isAnalysis) return false;
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
    if (!mode.isNormal && !mode.isAnalysis) return false;
    if (!mode.matchSequence('g')) return true; // first 'g': just swallow it

    final firstNode = editorState.document.first;
    if (firstNode == null) return true;

    // Analysis review: jump the whole-block highlight to the first block.
    if (mode.isAnalysis) {
      final selectable = firstNode.selectable;
      if (selectable != null) {
        editorState.updateSelectionWithReason(
          Selection(start: selectable.start(), end: selectable.end()),
          reason: SelectionUpdateReason.uiEvent,
        );
      }
      return true;
    }

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: firstNode.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }
}
