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

// ---- VISUAL MODE (`v`) ----
//
// Model: the FIXED end (anchor) is stored on the VimModeController when
// visual mode is entered; the MOVING end (head) is just whichever side of
// the current selection the cursor sits on. AppFlowy Selections may point
// start>end (its own docs model `isBackward`), and `deleteSelection`
// normalizes before deleting, so we keep the raw anchor/head ordering and
// let the package normalize where it cares.

/// Head-derivation shared by [_visualHead], [_exitVisualMode] and
/// [_handleVisualSwapEnds] — see [_visualHead] for why this compares
/// against the anchor instead of [Selection.isBackward].
///
/// Path equality MUST go through the appflowy extension (`Path.equals`),
/// NOT `==`: `Path` is a `List<int>` typedef and `==` on Dart lists is
/// identity, so two identical-content paths compare unequal almost every
/// time here (the anchor came through the controller, the selection
/// through the document).
VisualAnchor _headOfSelection(VisualAnchor? anchor, Selection selection) {
  final start = (path: selection.start.path, offset: selection.start.offset);
  final end = (path: selection.end.path, offset: selection.end.offset);
  if (anchor != null &&
      start.path.equals(anchor.path) &&
      start.offset == anchor.offset) {
    return end;
  }
  if (anchor != null &&
      end.path.equals(anchor.path) &&
      end.offset == anchor.offset) {
    return start;
  }
  // No/displaced anchor: prefer the later boundary (the reading-order end
  // is where a forward caret would sit).
  return end;
}

/// The head (moving end) of the current visual selection — the point the
/// next motion steps FROM and TO. Null when visual mode isn't actually
/// engaged (no anchor) or the editor has no selection.
///
/// Identified by comparing against the stored anchor rather than
/// [Selection.isBackward]: that flag's name is about the reading-order
/// direction INSIDE the selection, not about which boundary the cursor
/// sits on, and trusting it here would flip the head on every keystroke.
/// The head is simply the end that ISN'T the anchor; when both ends have
/// collapsed onto it the answer is the end either way.
VisualAnchor? _visualHead(VimModeController mode, EditorState editorState) {
  final anchor = mode.visualAnchor;
  if (anchor == null) return null;

  final selection = editorState.selection;
  if (selection == null) return null;

  return _headOfSelection(anchor, selection);
}

/// Rebuilds the visual selection with its head relocated to [head].
/// No-op when [head] is null (boundary reached — same at-edge no-op the
/// collapsed motions use) — the key was still swallowed by the caller.
///
/// Written in reading order (start before end) so AppFlowy renders the
/// highlight sanely; [_visualHead] identifies the head by anchor
/// comparison, not by which start/end slot it landed in.
void _extendVisual(
  VimModeController mode,
  EditorState editorState,
  VisualAnchor? head,
) {
  final anchor = mode.visualAnchor;
  if (anchor == null || head == null) return;

  // True when the anchor is not AFTER the head in reading order — i.e.
  // the head extends forward past the anchor (or sits on it, collapsed).
  // Path equality via .equals — `==` on the List<_> typedef is identity
  // (see _headOfSelection).
  final anchorFirst =
      anchor.path < head.path ||
      (anchor.path.equals(head.path) && anchor.offset <= head.offset);

  final a = Position(path: anchor.path, offset: anchor.offset);
  final h = Position(path: head.path, offset: head.offset);
  editorState.updateSelectionWithReason(
    Selection(start: anchorFirst ? a : h, end: anchorFirst ? h : a),
    reason: SelectionUpdateReason.uiEvent,
  );
}

/// Leaves visual mode, collapsing the selection to the head (vim: the
/// cursor survives as a normal caret; the highlight dies). Shared by `v`
/// again, `d`/`x`, and any other exit.
void _exitVisualMode(VimModeController mode, EditorState editorState) {
  final selection = editorState.selection;

  // Capture the head BEFORE flipping: enterNormalMode clears the anchor,
  // which is an input to the head derivation. Flip first, then collapse so
  // the caret lands on the surviving head, not wherever the anchor was.
  final head =
      selection == null ? null : _headOfSelection(mode.visualAnchor, selection);
  mode.enterNormalMode();

  if (head == null) return;
  editorState.updateSelectionWithReason(
    Selection.collapsed(Position(path: head.path, offset: head.offset)),
    reason: SelectionUpdateReason.uiEvent,
  );
}

/// `v` — enter visual mode (anchor pinned at the caret), leave it again
/// (collapsed to the head) if already in visual mode, swallowed no-op in
/// analysis mode, and typed normally in insert mode.
Future<bool> _handleVisualToggle(
  VimModeController mode,
  EditorState editorState,
) async {
  if (mode.isVisual) {
    _exitVisualMode(mode, editorState);
    return true;
  }
  if (mode.isNormal) {
    final selection = editorState.selection;
    if (selection != null) {
      // Normal-mode selections are always collapsed, so anchor = caret.
      mode.enterVisualMode(
        anchor: (path: selection.start.path, offset: selection.start.offset),
      );
    }
    return true;
  }
  if (mode.isAnalysis) return true; // read-only: swallow, no selection
  return false; // insert mode: 'v' is just a letter
}

/// `d` / `x` in visual mode — vim's delete-selection: delete everything
/// the visual selection covers, then drop back to normal mode (like
/// vim, the mode exits after the operator runs). Swallow-only when the
/// selection is somehow collapsed (defensive; can't happen while the
/// anchor is set and nothing has modified the document).
///
/// Cross-block deletion goes through [EditorState.deleteSelection], which
/// normalizes the (possibly backward) selection and merges the surviving
/// edge nodes itself.
Future<bool> _handleVisualDelete(
  VimModeController mode,
  EditorState editorState,
) async {
  final selection = editorState.selection;

  // Capture BEFORE the delete: after it the selected paths are stale and
  // the caret reference must survive (same trap the 'dd' handler
  // documents — deleteSelection/deleteNode leave the selection null).
  final anchorPath = selection?.start.path;
  final deletedIndex =
      anchorPath != null && anchorPath.isNotEmpty ? anchorPath.first : 0;

  if (mode.visualAnchor != null &&
      selection != null &&
      !selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }

  // Same caret-restoration contract as 'dd': AppFlowy doesn't reposition
  // after deletes, and a null caret makes every vim motion dead until a
  // click. Rest on the block that shifted into the deleted range's place
  // (same index, clamped), and keep the document non-empty when the
  // selection covered everything (vim leaves one empty line behind).
  final children = editorState.document.root.children;
  if (children.isEmpty) {
    final tx = editorState.transaction;
    tx.insertNode([0], paragraphNode(text: ''));
    editorState.apply(tx);
  }
  if (editorState.selection == null) {
    final i = deletedIndex.clamp(
      0,
      editorState.document.root.children.length - 1,
    );
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: [i], offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  _exitVisualMode(mode, editorState);
  return true;
}

/// `o`/`O` in visual mode — vim's endpoint swap: the cursor jumps to the
/// other end of the selection (O does the same for the character-wise
/// mode; line-wise subtleties aren't modeled here). The selection itself
/// is unchanged — only the controller's anchor moves under it.
Future<bool> _handleVisualSwapEnds(
  VimModeController mode,
  EditorState editorState,
) async {
  final selection = editorState.selection;
  if (selection != null) {
    final head = _headOfSelection(mode.visualAnchor, selection);
    mode.enterVisualMode(
      anchor: (path: head.path, offset: head.offset),
      force: true, // re-pin the anchor of the in-flight selection
    );
  }
  return true;
}

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
    // Visual mode: G extends the selection to the end of the document
    // (vim: selection reaches the last line's end).
    if (mode.isVisual) {
      final lastNode = editorState.document.last;
      if (lastNode == null) return KeyEventResult.handled;
      _extendVisual(mode, editorState, (
        path: lastNode.path,
        offset: lastNode.delta?.length ?? 0,
      ));
      return KeyEventResult.handled;
    }

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
      handler: (editorState) => _escapeHandler(mode, editorState),
    );
  }

  static KeyEventResult _escapeHandler(
    VimModeController mode,
    EditorState editorState,
  ) {
    // Visual mode: Escape leaves the selection AND collapses to the head —
    // a live non-collapsed selection left in normal mode would make the
    // next insertion replace it wholesale.
    if (mode.isVisual) {
      _exitVisualMode(mode, editorState);
    } else {
      mode.enterNormalMode();
    }
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
      getDescription:
          () =>
              'Prevent Enter from editing the document in analysis/visual mode',
      command: 'enter',
      handler: (editorState) {
        // Visual mode included: Enter with a live selection would delete
        // it and split the block (standard enter semantics). Swallow until
        // a visual-Enter behavior is wanted, mirroring the '\n' char event.
        if (!mode.isAnalysis && !mode.isVisual) return KeyEventResult.ignored;
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
    'O',
    'q',
    'v',
    'x',
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
          // Visual mode: extend to the next word start. The caret is
          // explicitly collapsed onto the head FIRST — AppFlowy's
          // moveCursor collapses a non-collapsed selection instead of
          // stepping it, so feeding it the visual range would just snap the
          // caret to the selection's start without moving.
          if (mode.isVisual) {
            return _extendByWord(mode, editorState, forward: true);
          }
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
          // Visual mode: same collapse-then-step dance, backwards (see the
          // 'w' branch and moveCursorForward's package implementation).
          if (mode.isVisual) {
            return _extendByWord(mode, editorState, forward: false);
          }
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
      // 'v' — character-wise visual select. Anchor pins at the caret; every
      // motion then extends (see the VISUAL MODE block below), 'd'/'x'
      // delete the selection, and 'v'/Escape return to normal mode.
      CharacterShortcutEvent(
        key: 'vim visual mode (v)',
        character: 'v',
        handler: (editorState) => _handleVisualToggle(mode, editorState),
      ),
      // 'x' — vim's delete-selection inside visual mode. Outside visual
      // mode this keeps the legacy catch-all behavior (swallowed no-op in
      // normal/analysis; vim's normal-mode delete-char is NOT implemented
      // — that's a separate gap from the visual one).
      CharacterShortcutEvent(
        key: 'vim visual delete (x)',
        character: 'x',
        handler: (editorState) async {
          if (mode.isVisual) {
            return _handleVisualDelete(mode, editorState);
          }
          return mode.isNormal || mode.isAnalysis;
        },
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
        key: 'vim open line below (o)',
        character: 'o',
        handler:
            (editorState) => _handleOpenLine(mode, editorState, above: false),
      ),
      // shift+o / 'O' — open a line ABOVE (vim's O).
      CharacterShortcutEvent(
        key: 'vim open line above (O)',
        character: 'O',
        handler:
            (editorState) => _handleOpenLine(mode, editorState, above: true),
      ),
      // Panel toggle lives on 'q' in NORMAL mode as well as ANALYSIS mode.
      // It previously lived on 'o', which conflicts with vim's open-line
      // command; 'q' is otherwise unmapped (vim's macro-recording key,
      // which this editor does not implement).
      CharacterShortcutEvent(
        key: 'vim toggle analysis panel (q)',
        character: 'q',
        handler:
            (editorState) =>
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
        // Analysis mode: review is read-only. Visual mode: a live selection
        // means Enter would delete the selection and split the block —
        // swallow here too until a visual Enter behavior is wanted.
        handler: (editorState) async => mode.isAnalysis || mode.isVisual,
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
          handler:
              (editorState) async =>
                  mode.isNormal || mode.isAnalysis || mode.isVisual,
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
  ///
  /// Unlike [_navOrType], the visual guard is INCLUDED here: this is the
  /// h/j/k/l router and visual mode must reach [_navHorizontal]/
  /// [_navVertical] to extend the selection. [_navOrType] keeps visual
  /// EXCLUDED on purpose — only motions with an explicit visual branch
  /// handle visual mode there, and a future motion that forgets its
  /// branch should stay broken-loud (falls through to typing) instead of
  /// silently doing a normal-mode caret move mid-selection.
  static Future<bool> _navOrTypeAsync(
    VimModeController mode,
    Future<void> Function() action,
  ) async {
    if (!mode.isNormal && !mode.isAnalysis && !mode.isVisual) return false;
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
      _rawPanelToggleShortcut('q', mode, onToggleAnalysisPanel),
      _rawOpenLineShortcut('o', mode, above: false),
      _rawOpenLineShortcut('shift+o', mode, above: true),
      // Arrow keys navigate BLOCKS in analysis mode. The table's own arrow
      // commands (tableCommands, in standardCommandShortcutEvents) return
      // `handled` at row/column edges even when they don't move — a collapsed
      // caret in a table cell can never leave the table with arrows. These
      // preempt that in review mode; normal/insert fall through untouched so
      // table editing keeps AppFlowy's native cell navigation.
      _rawArrowShortcut('arrow up', mode, delta: -1, horizontal: false),
      _rawArrowShortcut('arrow down', mode, delta: 1, horizontal: false),
      _rawArrowShortcut('arrow left', mode, delta: -1, horizontal: true),
      _rawArrowShortcut('arrow right', mode, delta: 1, horizontal: true),
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
      getDescription:
          () => '"$command" navigation that works without the IME attached',
      command: command,
      handler: (editorState) {
        if (!mode.isNormal && !mode.isAnalysis && !mode.isVisual) {
          return KeyEventResult.ignored;
        }
        // Reuse the char-path routers verbatim — they now own the analysis
        // (block hop), visual (selection extension) and normal (caret move)
        // branches, so the raw key can never drift from the mapped key.
        if (horizontal) {
          _navHorizontal(editorState, mode, delta: delta);
        } else {
          _navVertical(editorState, mode, delta: delta);
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
      getDescription:
          () => 'Enter analysis mode / step chunk without the IME attached',
      command: command,
      handler: (editorState) {
        if (mode.isVisual) {
          // 'n'/'N' aren't motions in visual mode; swallow (same rationale
          // as the char path — typing through a selection would replace it).
          return KeyEventResult.handled;
        }
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
      getDescription:
          () => 'Toggle the analysis panel without the IME attached',
      command: command,
      handler: (editorState) {
        // Visual mode: swallow, don't toggle (no hook in visual).
        if (mode.isVisual) return KeyEventResult.handled;
        if (!mode.isNormal && !mode.isAnalysis) {
          return KeyEventResult.ignored;
        }
        onToggleAnalysisPanel?.call();
        return KeyEventResult.handled;
      },
    );
  }

  /// Raw-key open-line pair ('o' below, 'shift+o' above): the same open
  /// line (and insert-mode flip + caret re-assert) as the character
  /// shortcuts, but reachable when the IME isn't attached — e.g. a
  /// whole-TABLE selection, where the caret node is a container and every
  /// character shortcut silently dies (see the getRawKeyVimShortcuts
  /// header). The mode flip/caret work runs through the same explicit
  /// selection updates, so it needs no IME either.
  ///
  /// 'o'/'O'/'shift+o' follow the raw-key labeling convention already in
  /// this list: modifier+named-key combos ('shift+n', 'shift+g') resolve
  /// against AppFlowyEditor's `keyToCodeMapping` — a bare 'O' would work
  /// as a key label too, but shift+o is the chord real keyboards send and
  /// the convention this codebase already uses for case-shifted commands.
  static CommandShortcutEvent _rawOpenLineShortcut(
    String command,
    VimModeController mode, {
    required bool above,
  }) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () => '"$command" opens a line below without the IME',
      command: command,
      handler: (editorState) {
        if (mode.isVisual) {
          // 'o'/'shift+o' in visual mode: endpoint swap (vim semantics),
          // not open-line — same branch the char path takes.
          _handleVisualSwapEnds(mode, editorState);
          return KeyEventResult.handled;
        }
        if (!mode.isNormal && !mode.isAnalysis) {
          return KeyEventResult.ignored;
        }
        if (mode.isNormal) {
          _openLine(editorState, mode, above: above);
        }
        return KeyEventResult.handled;
      },
    );
  }

  static CommandShortcutEvent _rawArrowShortcut(
    String command,
    VimModeController mode, {
    required int delta,
    required bool horizontal,
  }) {
    return CommandShortcutEvent(
      key: 'vim raw-key "$command"',
      getDescription: () => '"$command" navigates in analysis/visual mode',
      command: command,
      handler: (editorState) {
        // Analysis mode only: arrows step between whole blocks so tables
        // can't pin the caret at a cell edge. Visual mode routes through
        // [_navHorizontal]/[_navVertical] too (extension); normal/insert
        // keep the standard arrow/table navigation untouched.
        if (!mode.isAnalysis && !mode.isVisual) return KeyEventResult.ignored;
        if (horizontal) {
          _navHorizontal(editorState, mode, delta: delta);
        } else {
          _navVertical(editorState, mode, delta: delta);
        }
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
  ///
  /// The actual position math lives in [_siblingTarget] so the visual-mode
  /// extension branch can reuse it against a base OTHER than
  /// `selection.end` — in a backward (reversed) visual selection the head
  /// is `selection.start`, and motions must step from the head, not the
  /// selection's forward end.
  static Future<void> _moveToSiblingLine(
    EditorState editorState, {
    required int delta,
  }) async {
    final selection = editorState.selection;
    if (selection == null) return;

    final target = _siblingTarget(
      editorState,
      fromPath: selection.end.path,
      fromOffset: selection.end.offset,
      delta: delta,
    );
    if (target == null) return; // already at the first/last line

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: target.path, offset: target.offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// Pure position math for j/k: where same-column movement by [delta]
  /// step(s) on the adjacent sibling lands, starting at [fromOffset] on
  /// line [fromPath]. Null = at the first/last line (no sibling there).
  /// No selection mutation — callers decide whether the result moves a
  /// collapsed caret (normal mode) or extends a selection (visual mode).
  static ({List<int> path, int offset})? _siblingTarget(
    EditorState editorState, {
    required List<int> fromPath,
    required int fromOffset,
    required int delta,
  }) {
    if (fromPath.isEmpty) return null;

    final targetPath = [
      ...fromPath.sublist(0, fromPath.length - 1),
      fromPath.last + delta,
    ];
    final targetNode = editorState.getNodeAtPath(targetPath);
    if (targetNode == null) return null; // already at the first/last line

    final targetDelta = targetNode.delta;
    final maxOffset = targetDelta?.length ?? 0;
    return (path: targetNode.path, offset: fromOffset.clamp(0, maxOffset));
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

    final target = _characterTarget(
      editorState,
      fromPath: selection.end.path,
      fromOffset: selection.end.offset,
      delta: delta,
    );
    if (target == null) return; // already at document start/end

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: target.path, offset: target.offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  /// Pure position math for h/l: where one-character movement by [delta]
  /// lands from [fromOffset] on text line [fromPath], wrapping across
  /// node boundaries exactly like the collapsed version
  /// ([_moveCharacter]). Null = already at document start/end.
  ///
  /// Split out of [_moveCharacter] for visual mode — same reasoning as
  /// [_siblingTarget]: in a backward visual selection the head is
  /// `selection.start` and motions must step from the head.
  static ({List<int> path, int offset})? _characterTarget(
    EditorState editorState, {
    required List<int> fromPath,
    required int fromOffset,
    required int delta,
  }) {
    if (fromPath.isEmpty) return null;

    final node = editorState.getNodeAtPath(fromPath);
    final currentLength = node?.delta?.length ?? 0;
    final newOffset = fromOffset + delta;

    if (newOffset >= 0 && newOffset <= currentLength) {
      // Still within the current line — just shift the offset.
      return (path: fromPath, offset: newOffset);
    }

    // Crossed a line boundary: step to the adjacent node, landing at its
    // far edge (end of the previous line for delta<0, start of the next
    // line for delta>0) — matching how h/l wrap across lines in vim.
    final targetPath = [
      ...fromPath.sublist(0, fromPath.length - 1),
      fromPath.last + delta,
    ];
    final targetNode = editorState.getNodeAtPath(targetPath);
    if (targetNode == null) return null; // already at document start/end

    final targetLength = targetNode.delta?.length ?? 0;
    final targetOffset = delta < 0 ? targetLength : 0;
    return (path: targetNode.path, offset: targetOffset);
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
  /// analysis mode (same direction: -1 = previous block, +1 = next), and
  /// selection-extension in visual mode (the HEAD moves, the anchor —
  /// pinned at `v` time — stays; crossing the anchor reverses the
  /// selection exactly like vim).
  static Future<void> _navHorizontal(
    EditorState editorState,
    VimModeController mode, {
    required int delta,
  }) async {
    if (mode.isAnalysis) {
      await _moveBlockInAnalysis(editorState, delta: delta);
    } else if (mode.isVisual) {
      await _extendByMotion(editorState, mode, horizontal: true, delta: delta);
    } else {
      await _navInNormalMode(editorState, horizontal: true, delta: delta);
    }
  }

  /// j/k: sibling-line motion in normal mode, block-scope review motion in
  /// analysis mode, selection-extension in visual mode.
  static Future<void> _navVertical(
    EditorState editorState,
    VimModeController mode, {
    required int delta,
  }) async {
    if (mode.isAnalysis) {
      await _moveBlockInAnalysis(editorState, delta: delta);
    } else if (mode.isVisual) {
      await _extendByMotion(editorState, mode, horizontal: false, delta: delta);
    } else {
      await _navInNormalMode(editorState, horizontal: false, delta: delta);
    }
  }

  /// Shared visual-mode motion: compute the head's next landing spot with
  /// the normal-mode position math and extend the selection to it.
  ///
  /// Table cells are the one carve-out: head/anchor across cell boundaries
  /// has no vim precedent worth emulating and the cell router below only
  /// understands collapsed carets, so a visual selection whose head is in a
  /// cell first collapses to the head and lets [_navInNormalMode] move it
  /// like normal — the selection shrinks to the cursor instead of counting
  /// column math. (Same table contract the rest of this file documents:
  /// tables keep AppFlowy-native behavior; vim innovations stop at the
  /// cell edge.)
  static Future<void> _extendByMotion(
    EditorState editorState,
    VimModeController mode, {
    required bool horizontal,
    required int delta,
  }) async {
    final head = _visualHead(mode, editorState);
    if (head == null) return; // swallowed by the caller; nothing to extend

    // Recompute containment against a COLLAPSED head selection — when the
    // head is inside a cell the anchor is usually outside it, so testing the
    // live (non-collapsed) selection's end path isn't reliable either way.
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: head.path, offset: head.offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
    if (_selectionIsInTableCell(editorState)) {
      await _navInNormalMode(editorState, horizontal: horizontal, delta: delta);
      return;
    }

    final target =
        horizontal
            ? _characterTarget(
              editorState,
              fromPath: head.path,
              fromOffset: head.offset,
              delta: delta,
            )
            : _siblingTarget(
              editorState,
              fromPath: head.path,
              fromOffset: head.offset,
              delta: delta,
            );
    _extendVisual(mode, editorState, target);
  }

  /// `w`/`b` in visual mode: extend to the next/previous word boundary.
  ///
  /// The caret is collapsed onto the head FIRST, then stepped with the
  /// package's `moveCursorForward`/`moveCursorBackward` (the same helpers
  /// normal mode uses — after an explicit collapse they take the real
  /// stepping path instead of the collapse-instead-of-move shortcut their
  /// source documents), and the selection is rebuilt around wherever the
  /// caret landed.
  ///
  /// Headless-testable only to the extent of "doesn't crash and keeps the
  /// mode": stepping itself requires `node.selectable` (widget-backed, text
  /// layout), so like normal-mode 'w'/'b' the actual word boundaries are
  /// exercised in live runs, not headless tests.
  static Future<bool> _extendByWord(
    VimModeController mode,
    EditorState editorState, {
    required bool forward,
  }) async {
    final head = _visualHead(mode, editorState);
    if (head == null) return true;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: head.path, offset: head.offset)),
      reason: SelectionUpdateReason.uiEvent,
    );
    // NOTE: moveCursorForward/Backward are `void` in this AppFlowy version —
    // no await. The subsequent selection read is synchronous state anyway.
    if (forward) {
      editorState.moveCursorForward(SelectionMoveRange.word);
    } else {
      editorState.moveCursorBackward(SelectionMoveRange.word);
    }

    final landed = editorState.selection;
    if (landed != null && landed.isCollapsed) {
      _extendVisual(mode, editorState, (
        path: landed.start.path,
        offset: landed.start.offset,
      ));
    }
    return true;
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
        _moveInTableCell(editorState, horizontal: horizontal, delta: delta)) {
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
    final cell =
        node.type == CerebrumTableCellKeys.type
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

    final offset =
        horizontal
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
    // Visual mode: extend the selection to column 0 of the HEAD's line
    // (vim's visual 0 — the anchor is untouched).
    if (mode.isVisual) {
      final head = _visualHead(mode, editorState);
      if (head == null) return true;
      _extendVisual(mode, editorState, (path: head.path, offset: 0));
      return true;
    }
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
    // Visual mode: extend to the end of the head's line. If the head's node
    // isn't a text node (e.g. an image block), `0`/`$` have no meaning there —
    // swallow, same as analysis.
    if (mode.isVisual) {
      final head = _visualHead(mode, editorState);
      if (head == null) return true;
      final node = editorState.getNodeAtPath(head.path);
      if (node == null) return true;
      _extendVisual(mode, editorState, (
        path: head.path,
        offset: node.delta?.length ?? 0,
      ));
      return true;
    }
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
    // Visual mode: vim's `i` abandons the selection and starts typing AT
    // ITS START (the earlier boundary). Collapse there first — typing with
    // a live visual selection would replace everything selected.
    if (mode.isVisual) {
      final selection = editorState.selection;
      if (selection != null) {
        final start = selection.normalized.start;
        editorState.updateSelectionWithReason(
          Selection.collapsed(start),
          reason: SelectionUpdateReason.uiEvent,
        );
        // Reuse the post-frame re-assert so the caret survives the
        // visual→insert rebuild (same first-keystroke race as normal mode).
        _enterInsertWithCaretReassert(
          editorState,
          mode,
          start.path,
          start.offset,
        );
        return true;
      }
      mode.enterInsertMode();
      return true;
    }

    if (!mode.isNormal && !mode.isAnalysis) return false;

    // Capture the collapse target BEFORE flipping. Analysis navigation leaves
    // WHOLE-BLOCK selections behind; typing with one selected would replace the
    // entire block. In normal mode the selection is always collapsed already, so
    // this is a no-op there.
    final start = editorState.selection?.start;
    if (start == null) {
      mode.enterInsertMode();
      return true;
    }
    _enterInsertWithCaretReassert(editorState, mode, start.path, start.offset);
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
    // Visual mode: 'n'/'N' are analysis-mode keys, not motions — swallow so
    // the selection can't be replaced by a typed 'n'. (Real vim has search
    // semantics on n; here it only drives analysis review.)
    if (mode.isVisual) return true;
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

  /// 'o'/'O' — vim's open-line pair: insert an empty paragraph directly
  /// BELOW ('o') or ABOVE ('O') the cursor's line and enter insert mode on
  /// it. The split happens at the LINE boundary regardless of cursor
  /// column, exactly like vim — the current line's text is never divided,
  /// even when the caret sits mid-line.
  ///
  // Implementation notes shared by both entrances:
  //
  // The open-line pair. Both share [_openLine]; only the insertion side
  // and the key label differ.
  //
  // ANALYSIS mode: review is read-only, so both keys are swallowed with no
  // action (the old analysis-panel toggle that lived on 'o' moved to 'q').
  // INSERT mode: both fall through and type normally ('o'/'O' are letters).
  // VISUAL mode: both swap the cursor with the anchor (vim's endpoint swap)
  // — opening a line while a selection exists would replace it.
  //
  // Selection handling mirrors [_handleEnterInsert]: the caret is placed
  // on the new node immediately (used by the raw-key path too, where the
  // mode flip must land on the new line), insert mode is entered, and a
  // post-frame callback re-asserts the collapsed caret so the mode-change
  // rebuild can't drop it (same first-keystroke race documented there).
  static Future<bool> _handleOpenLine(
    VimModeController mode,
    EditorState editorState, {
    required bool above,
  }) async {
    // Visual mode: 'o'/'O' do NOT open a line — vim moves the cursor to the
    // other end of the visual selection and re-pins the anchor there.
    if (mode.isVisual) return _handleVisualSwapEnds(mode, editorState);
    if (mode.isAnalysis) return true;
    if (!mode.isNormal) return false; // insert mode: 'o'/'O' is just a letter

    _openLine(editorState, mode, above: above);
    return true;
  }

  /// Shared open-line implementation for the character shortcuts and the
  /// raw-key fallbacks ([_rawOpenLineShortcut]). [mode] must already be
  /// normal mode.
  static void _openLine(
    EditorState editorState,
    VimModeController mode, {
    required bool above,
  }) {
    final selection = editorState.selection;
    if (selection == null) return;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return;

    // Above: insert at the caret node's OWN index — insertNode shifts the
    // existing node (and everything after it) down one slot, which IS the
    // open-above placement, and needs no special case on the first line
    // (index 0 shifts the current first child to [1] the same way).
    // Below: path.next = the sibling slot after the caret's line.
    final newPath = above ? selection.end.path : selection.end.path.next;
    final transaction = editorState.transaction;
    transaction.insertNode(newPath, paragraphNode(text: ''));
    editorState.apply(transaction);

    // Rest the caret at the start of the new line. (Unlike insertText,
    // insertNode does not reposition the selection — same gap the 'dd'
    // handler documents for deleteNode.)
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: newPath, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );

    _enterInsertWithCaretReassert(editorState, mode, newPath, 0);
  }

  /// Flips to insert mode and re-asserts the collapsed caret on a post-frame
  /// callback — the shared caret-loss guard from [_handleEnterInsert]. An
  /// edit-less mode flip does no text transaction, so AppFlowy never
  /// re-engages its cursor overlay / text input for the new mode and the
  /// first typed keystroke races the mode-change rebuild. Deferred to a
  /// post-frame callback so it lands AFTER this key event's own rebuild.
  ///
  /// The caret position is explicit ([path]/[offset]) rather than derived
  /// from the current selection, because callers like [_openLineBelow] have
  /// already moved the caret to a node the current selection still needs to
  /// survive across the rebuild.
  static void _enterInsertWithCaretReassert(
    EditorState editorState,
    VimModeController mode,
    List<int> path,
    int offset,
  ) {
    mode.enterInsertMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: path, offset: offset)),
        reason: SelectionUpdateReason.uiEvent,
      );
    });
  }

  /// 'q' — toggle the full analysis panel (overview tab) while in ANALYSIS
  /// mode, or open it from NORMAL mode. This does NOT change the vim mode:
  /// 'n' still enters review mode, 'q' just shows/hides the panel. In
  /// normal mode the key is swallowed (it's a vim-mode key, not a typed
  /// character); in insert mode it types normally.
  ///
  /// Rebound from 'o' (which is vim's open-line command — see
  /// [_handleOpenLineBelow]).
  static Future<bool> _handleToggleAnalysisPanel(
    VimModeController mode,
    VoidCallback? onToggleAnalysisPanel,
  ) async {
    if (mode.isVisual) {
      // Visual mode: 'q' has no selection-compatible meaning — swallow.
      return true;
    }
    if (mode.isNormal || mode.isAnalysis) {
      // Optimistic hook — the analysis must already be loaded for chunks
      // to exist (the panel itself lazy-loads, see EditorScaffold).
      onToggleAnalysisPanel?.call();
    }
    // Swallow in normal AND analysis AND visual mode; fall through to
    // typing in insert.
    return mode.isNormal || mode.isAnalysis || mode.isVisual;
  }

  /// 'dd' — delete current line. First 'd' in normal mode is always
  /// swallowed (it's a pending operator, same as real vim); the second
  /// 'd' within the sequence window performs the delete.
  ///
  /// In visual mode a single 'd' deletes the whole visual selection and
  /// exits to normal mode — vim operators apply to the selection directly,
  /// there is no pending state to enter.
  static Future<bool> _handleDeleteLine(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (mode.isVisual) return _handleVisualDelete(mode, editorState);
    if (!mode.isNormal && !mode.isAnalysis) return false;
    if (!mode.matchSequence('d')) return true; // first 'd': just swallow it

    final selection = editorState.selection;
    if (selection == null) return true;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return true;

    // Capture the index of the block being deleted BEFORE the delete: after
    // it, `node.path` is stale and AppFlowy's deleteNode leaves the selection
    // NULL (verified headlessly in tmp_dd_focus_test.dart), so no surviving
    // reference is trustworthy for re-selecting.
    final deletedIndex =
        selection.end.path.isNotEmpty ? selection.end.path.first : 0;

    final transaction = editorState.transaction;
    transaction.deleteNode(node);
    editorState.apply(transaction);

    // AppFlowy 6.0 does NOT reposition the caret after deleteNode — the
    // selection is left null. Every vim motion guards on selection == null,
    // so with no caret to render the page feels "unfocused" and j/k are dead
    // until a click. vim semantics: rest the caret on the block that shifts
    // into the deleted block's place (same index, clamped to the last
    // survivor), collapsed at its start.
    final children = editorState.document.root.children;
    if (children.isEmpty && editorState.selection == null) {
      // Deleting the very last block empties the document (AppFlowy's
      // deleteNode does not preserve an empty paragraph). vim `dd` on the
      // final line leaves an empty line behind — recreate the paragraph
      // instead of leaving the note with no root children at all.
      final tx = editorState.transaction;
      tx.insertNode([0], paragraphNode(text: ''));
      editorState.apply(tx);
    }
    if (editorState.selection == null &&
        editorState.document.root.children.isNotEmpty) {
      final i = deletedIndex.clamp(
        0,
        editorState.document.root.children.length - 1,
      );
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: [i], offset: 0)),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
    return true;
  }

  /// 'gg' — move to document start. Same pending-sequence pattern as
  /// 'dd' above. In visual mode the second 'g' EXTENDS the selection to
  /// the document start instead of moving the caret.
  static Future<bool> _handleDocStart(
    VimModeController mode,
    EditorState editorState,
  ) async {
    if (mode.isVisual) {
      if (!mode.matchSequence('g')) return true; // first 'g': swallow
      final firstNode = editorState.document.first;
      if (firstNode == null) return true;
      _extendVisual(mode, editorState, (path: firstNode.path, offset: 0));
      return true;
    }
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
