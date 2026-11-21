import 'package:flutter/widgets.dart';
import 'package:cerebrum/features/editor/helpers/vim_move_controller.dart';

/// The one thing every text-editing engine must be able to do: hold a
/// document, notify on change, and build its own editing widget.
///
/// This is the actual swap boundary. [NoteEditorController] and
/// [EditorSurface] only ever talk to this interface — neither knows or
/// cares whether the concrete driver is AppFlowy, super_editor, or
/// something else entirely. To test a new engine: implement this, hand
/// an instance to [NoteEditorController], done.
abstract class TextEditingDriver extends ChangeNotifier {
  /// Document content in the shape the backend expects under
  /// `content.document`. Each driver owns translating its own internal
  /// document model into that shape — see the caveat in
  /// [SuperEditorTextDriver] about this not being a solved problem for
  /// every engine yet.
  /// Document content in the shape the backend expects under
  /// `content.document`. Each driver owns translating its own internal
  /// document model into that shape — see the caveat in
  /// [SuperEditorTextDriver] about this not being a solved problem for
  /// every engine yet.
  Map<String, dynamic> get documentJson;

  /// Moves the cursor/selection to the block with the given stable ID.
  /// If the ID isn't found or the engine doesn't support this, it's a no-op.
  /// [offset] is the collapsed caret offset inside the block (clamped).
  void focusBlockById(String blockId, [int offset = 0]);

  /// Builds the actual editing widget for this engine (AppFlowyEditor,
  /// SuperEditor, whatever). [EditorSurface] just calls this.
  Widget buildEditor(BuildContext context);
}

/// Optional capability. Not every engine has vim-style modal editing, so
/// this stays separate from [TextEditingDriver] rather than forcing every
/// implementation to fake a mode it doesn't have. [EditorSurface] checks
/// `driver is VimModeAware` before rendering the mode badge.
abstract interface class VimModeAware {
  VimModeController get vimMode;
}
