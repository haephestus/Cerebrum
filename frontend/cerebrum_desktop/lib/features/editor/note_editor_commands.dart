import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Custom keyboard shortcuts for the note editor
/// Includes vim-like navigation and commands
class EditorShortcuts {
  /// Get all custom shortcut events
  static List<CommandShortcutEvent> getCustomShortcuts() {
    return [
      // Vim-like navigation (when not in insert mode)
      _moveUpShortcut(),
      _moveDownShortcut(),
      _moveLeftShortcut(),
      _moveRightShortcut(),

      // Word navigation
      _moveWordForwardShortcut(),
      _moveWordBackwardShortcut(),

      // Line navigation
      _moveToLineStartShortcut(),
      _moveToLineEndShortcut(),

      // Document navigation
      _moveToDocStartShortcut(),
      _moveToDocEndShortcut(),

      // Custom commands
      _deleteLineShortcut(),
      _duplicateLineShortcut(),

      // Mode switching (for vim-like modal editing)
      _escapeToNormalModeShortcut(),
    ];
  }

  // Vim navigation: j = down
  static CommandShortcutEvent _moveDownShortcut() {
    return CommandShortcutEvent(
      key: 'Move cursor down (vim j)',
      getDescription: () => 'Move the cursor down one line',
      command: 'vim.move.down',
      handler: _moveDownHandler,
    );
  }

  static KeyEventResult _moveDownHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    // Get current node
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    // Move down logic here
    editorState.moveCursorForward(SelectionMoveRange.line);

    return KeyEventResult.handled;
  }

  // Vim navigation: k = up
  static CommandShortcutEvent _moveUpShortcut() {
    return CommandShortcutEvent(
      key: 'Move cursor up (vim k)',
      getDescription: () => 'Move the cursor up one line',
      command: 'vim.move.up',
      handler: _moveUpHandler,
    );
  }

  static KeyEventResult _moveUpHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    editorState.moveCursorBackward(SelectionMoveRange.line);

    return KeyEventResult.handled;
  }

  // Vim navigation: h = left
  static CommandShortcutEvent _moveLeftShortcut() {
    return CommandShortcutEvent(
      key: 'Move cursor left (vim h)',
      getDescription: () => 'Move the cursor left one character',
      command: 'vim.move.left',
      handler: _moveLeftHandler,
    );
  }

  static KeyEventResult _moveLeftHandler(EditorState editorState) {
    editorState.moveCursorBackward(SelectionMoveRange.character);
    return KeyEventResult.handled;
  }

  // Vim navigation: l = right
  static CommandShortcutEvent _moveRightShortcut() {
    return CommandShortcutEvent(
      key: 'Move cursor right (vim l)',
      getDescription: () => 'Move the cursor right one character',
      command: 'vim.move.right',
      handler: _moveRightHandler,
    );
  }

  static KeyEventResult _moveRightHandler(EditorState editorState) {
    editorState.moveCursorForward(SelectionMoveRange.character);
    return KeyEventResult.handled;
  }

  // w = word forward
  static CommandShortcutEvent _moveWordForwardShortcut() {
    return CommandShortcutEvent(
      key: 'Move word forward (vim w)',
      getDescription: () => 'Move the cursor forward one word',
      command: 'vim.move.word.forward',
      handler: _moveWordForwardHandler,
    );
  }

  static KeyEventResult _moveWordForwardHandler(EditorState editorState) {
    editorState.moveCursorForward(SelectionMoveRange.word);
    return KeyEventResult.handled;
  }

  // b = word backward
  static CommandShortcutEvent _moveWordBackwardShortcut() {
    return CommandShortcutEvent(
      key: 'Move word backward (vim b)',
      getDescription: () => 'Move the cursor backward one word',
      command: 'vim.move.word.backward',
      handler: _moveWordBackwardHandler,
    );
  }

  static KeyEventResult _moveWordBackwardHandler(EditorState editorState) {
    editorState.moveCursorBackward(SelectionMoveRange.word);
    return KeyEventResult.handled;
  }

  // 0 = line start
  static CommandShortcutEvent _moveToLineStartShortcut() {
    return CommandShortcutEvent(
      key: 'Move to line start (vim 0)',
      getDescription: () => 'Move the cursor to the start of the line',
      command: 'vim.move.line.start',
      handler: _moveToLineStartHandler,
    );
  }

  static KeyEventResult _moveToLineStartHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: selection.end.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );

    return KeyEventResult.handled;
  }

  // $ = line end
  static CommandShortcutEvent _moveToLineEndShortcut() {
    return CommandShortcutEvent(
      key: 'Move to line end (vim \$)',
      getDescription: () => 'Move the cursor to the end of the line',
      command: 'vim.move.line.end',
      handler: _moveToLineEndHandler,
    );
  }

  static KeyEventResult _moveToLineEndHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    final delta = node.delta;
    if (delta == null) return KeyEventResult.ignored;

    final length = delta.length;
    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: selection.end.path, offset: length)),
      reason: SelectionUpdateReason.uiEvent,
    );

    return KeyEventResult.handled;
  }

  // gg = document start
  static CommandShortcutEvent _moveToDocStartShortcut() {
    return CommandShortcutEvent(
      key: 'Move to document start (vim gg)',
      getDescription: () => 'Move the cursor to the start of the document',
      command: 'vim.move.doc.start',
      handler: _moveToDocStartHandler,
    );
  }

  static KeyEventResult _moveToDocStartHandler(EditorState editorState) {
    final firstNode = editorState.document.first;
    if (firstNode == null) return KeyEventResult.ignored;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: firstNode.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );

    return KeyEventResult.handled;
  }

  // G = document end
  static CommandShortcutEvent _moveToDocEndShortcut() {
    return CommandShortcutEvent(
      key: 'Move to document end (vim G)',
      getDescription: () => 'Move the cursor to the end of the document',
      command: 'vim.move.doc.end',
      handler: _moveToDocEndHandler,
    );
  }

  static KeyEventResult _moveToDocEndHandler(EditorState editorState) {
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

  // dd = delete line
  static CommandShortcutEvent _deleteLineShortcut() {
    return CommandShortcutEvent(
      key: 'Delete line (vim dd)',
      getDescription: () => 'Delete the current line',
      command: 'vim.delete.line',
      handler: _deleteLineHandler,
    );
  }

  static KeyEventResult _deleteLineHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    final transaction = editorState.transaction;
    transaction.deleteNode(node);
    editorState.apply(transaction);

    return KeyEventResult.handled;
  }

  // Ctrl+D = duplicate line
  static CommandShortcutEvent _duplicateLineShortcut() {
    return CommandShortcutEvent(
      key: 'Duplicate line',
      getDescription: () => 'Duplicate the current line',
      command: 'custom.duplicate.line',
      handler: _duplicateLineHandler,
    );
  }

  static KeyEventResult _duplicateLineHandler(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) return KeyEventResult.ignored;

    // Create a copy of the node
    final transaction = editorState.transaction;
    final newNode = node.copyWith();
    transaction.insertNode(selection.end.path, newNode);
    editorState.apply(transaction);

    return KeyEventResult.handled;
  }

  // ESC = exit to normal mode (for vim modal editing)
  static CommandShortcutEvent _escapeToNormalModeShortcut() {
    return CommandShortcutEvent(
      key: 'Escape to normal mode',
      getDescription: () => 'Exit insert mode',
      command: 'vim.mode.normal',
      handler: _escapeHandler,
    );
  }

  static KeyEventResult _escapeHandler(EditorState editorState) {
    // Clear selection or unfocus
    editorState.updateSelectionWithReason(
      null,
      reason: SelectionUpdateReason.uiEvent,
    );
    return KeyEventResult.handled;
  }
}

/// Character shortcut events for vim-like single key commands
class VimCharacterShortcuts {
  static Map<String, CharacterShortcutEvent> getCharacterShortcuts() {
    return {
      'h': CharacterShortcutEvent(
        key: 'vim left',
        character: 'h',
        handler: _handleVimLeft,
      ),
      'j': CharacterShortcutEvent(
        key: 'vim down',
        character: 'j',
        handler: _handleVimDown,
      ),
      'k': CharacterShortcutEvent(
        key: 'vim up',
        character: 'k',
        handler: _handleVimUp,
      ),
      'l': CharacterShortcutEvent(
        key: 'vim right',
        character: 'l',
        handler: _handleVimRight,
      ),
      'w': CharacterShortcutEvent(
        key: 'vim word forward',
        character: 'w',
        handler: _handleVimWordForward,
      ),
      'b': CharacterShortcutEvent(
        key: 'vim word backward',
        character: 'b',
        handler: _handleVimWordBackward,
      ),
      '0': CharacterShortcutEvent(
        key: 'vim line start',
        character: '0',
        handler: _handleVimLineStart,
      ),
      '\$': CharacterShortcutEvent(
        key: 'vim line end',
        character: r'$',
        handler: _handleVimLineEnd,
      ),
    };
  }

  static Future<bool> _handleVimLeft(EditorState editorState) async {
    editorState.moveCursorBackward(SelectionMoveRange.character);
    return true;
  }

  static Future<bool> _handleVimDown(EditorState editorState) async {
    editorState.moveCursorForward(SelectionMoveRange.line);
    return true;
  }

  static Future<bool> _handleVimUp(EditorState editorState) async {
    editorState.moveCursorBackward(SelectionMoveRange.line);
    return true;
  }

  static Future<bool> _handleVimRight(EditorState editorState) async {
    editorState.moveCursorForward(SelectionMoveRange.character);
    return true;
  }

  static Future<bool> _handleVimWordForward(EditorState editorState) async {
    editorState.moveCursorForward(SelectionMoveRange.word);
    return true;
  }

  static Future<bool> _handleVimWordBackward(EditorState editorState) async {
    editorState.moveCursorBackward(SelectionMoveRange.word);
    return true;
  }

  static Future<bool> _handleVimLineStart(EditorState editorState) async {
    final selection = editorState.selection;
    if (selection == null) return false;

    editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: selection.end.path, offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }

  static Future<bool> _handleVimLineEnd(EditorState editorState) async {
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
}
