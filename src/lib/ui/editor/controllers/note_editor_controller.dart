import 'package:flutter/foundation.dart';
import 'package:scribble/scribble.dart';
import 'package:cerebrum/ui/editor/controllers/text_editing_driver.dart';

/// Owns the note's editing state end to end: whichever [TextEditingDriver]
/// is currently active, the ink/drawing layer (which is driver-agnostic —
/// every engine gets the same drawing board), and the draw/text mode
/// toggle. Whether a note *opens* in drawing or text mode is set once via
/// [startInDrawingMode] at construction; after that it's just
/// [toggleDrawingMode] like always. [EditorScaffold] and [EditorSurface]
/// talk to this and nothing lower; they never import `appflowy_editor` or
/// `super_editor` directly.
class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required TextEditingDriver driver,
    List<Map<String, dynamic>>? initialInkJson,
    bool startInDrawingMode = false,
  }) : _driver = driver,
       _drawingEnabled = startInDrawingMode {
    _drawingNotifier = ScribbleNotifier();
    // Scribble defaults toward stylus/touch use; without this, drawing
    // with a mouse on desktop is a no-op. This is the actual fix for
    // "can't test it, I'm on PC."
    _drawingNotifier.setAllowedPointersMode(ScribblePointerMode.all);
    if (initialInkJson != null) _loadInk(initialInkJson);
    _driver.addListener(notifyListeners);
    _drawingNotifier.addListener(notifyListeners);
  }

  TextEditingDriver _driver;
  late final ScribbleNotifier _drawingNotifier;
  bool _drawingEnabled;

  /// Set when [_loadInk] fails to parse the ink payload it was handed.
  /// [EditorScaffold] can surface this (banner/snackbar) instead of the
  /// failure being invisible — a note silently opening with blank ink
  /// looks identical to "this note has no ink," which is exactly the
  /// case that burned us before this flag existed.
  bool _inkLoadFailed = false;
  bool get inkLoadFailed => _inkLoadFailed;

  TextEditingDriver get driver => _driver;
  ScribbleNotifier get drawingNotifier => _drawingNotifier;
  bool get drawingEnabled => _drawingEnabled;

  void toggleDrawingMode() {
    _drawingEnabled = !_drawingEnabled;
    notifyListeners();
  }

  Map<String, dynamic> get documentJson => _driver.documentJson;

  /// Kept as a single-element list (rather than switching to a bare Map)
  /// so `BubbleNotesApi.createNote`/`updateNote`'s `ink:` param and your
  /// backend's storage shape don't need to change. The one element is
  /// the full `Sketch.toJson()` payload.
  List<Map<String, dynamic>> get inkJson => [
    _drawingNotifier.currentSketch.toJson(),
  ];

  /// Swaps the text-editing engine at runtime — this is the "switch
  /// between AppFlowy/super_editor for testing" hook. Ink is untouched
  /// since it never belonged to the driver in the first place.
  ///
  /// NOTE: text content does not currently carry over between engines.
  /// Each driver starts from whatever `initialDocumentJson` you pass its
  /// constructor (or blank). See the caveat on `SuperEditorTextDriver`.
  void switchDriver(TextEditingDriver newDriver) {
    final old = _driver;
    _driver = newDriver;
    _driver.addListener(notifyListeners);
    old.removeListener(notifyListeners);
    old.dispose();
    notifyListeners();
  }

  void _loadInk(List<Map<String, dynamic>> jsonList) {
    if (jsonList.isEmpty) return;

    final raw = jsonList.first;
    try {
      // See note on `inkJson` — the single element is a full Sketch.
      final sketch = Sketch.fromJson(raw);
      // NOTE: verify `setSketch`'s exact parameter name against your
      // pinned `scribble` version — the changelog documents the method
      // but I'm inferring the signature, not quoting it verbatim.
      _drawingNotifier.setSketch(sketch: sketch, addToUndoHistory: false);
      _inkLoadFailed = false;
    } catch (e, st) {
      // Was previously `catch (_) {}` — silently swallowed, so a note
      // whose ink failed to parse looked identical to a note with no
      // ink at all. Two known ways to land here:
      //
      //  1. Pre-`scribble` ink: notes drawn back when this used
      //     `flutter_drawing_board` stored a flat list of stroke
      //     objects, not a `Sketch.toJson()` payload. `raw` in that
      //     case is a single stroke, not a sketch — `Sketch.fromJson`
      //     throws on the shape mismatch.
      //  2. Genuinely corrupt/truncated ink.json.
      //
      // Starting blank is still the right call — better than crashing
      // the editor open — but it now says so, instead of pretending
      // the note simply has no ink.
      _inkLoadFailed = true;
      debugPrint(
        '[NoteEditorController] Failed to load ink '
        '(keys: ${raw.keys.toList()}): $e\n$st',
      );

      // TODO: if (1) turns out to be the actual cause in your logs,
      // this is where a legacy-format adapter would go — converting
      // the old flutter_drawing_board stroke-list shape into a Sketch
      // before falling back to blank. Left as a TODO rather than
      // guessed at, since the old format's exact schema isn't
      // available here to convert against safely.
    }
  }

  @override
  void dispose() {
    _driver.dispose();
    _drawingNotifier.dispose();
    super.dispose();
  }
}
