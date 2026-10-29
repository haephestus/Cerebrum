import 'package:flutter/foundation.dart';

/// [analysis] is a read-only review mode (SCAFFOLD): like normal mode it eats
/// text input, but instead of editing it drives chunk-by-chunk review of the
/// note's analysis (see AnalysisModeController). Enter it from normal mode;
/// Escape returns to normal.
///
/// [visual] is vim's character-wise visual mode (`v`): motions extend a
/// selection instead of moving a caret, `d`/`x` delete the selection, and
/// Escape (or `v` again) returns to normal. The fixed selection boundary
/// (the anchor) lives in [VimModeController.visualAnchor], recorded when
/// the mode is entered; the moving boundary (the head) is just wherever
/// the selection's far side currently sits.
enum VimMode { normal, insert, analysis, visual }

/// The record [VimModeController] stores for the visual-mode anchor.
/// Deliberately a plain Dart record (path + offset), NOT an AppFlowy
/// Position/Selection type: this controller stays free of any
/// appflowy_editor dependency and everything above
/// [NoteEditorController] keeps importing it (see appflowy_text_driver's
/// layering note).
typedef VisualAnchor = ({List<int> path, int offset});

/// Tracks whether the editor is in vim-style normal (navigation) mode or
/// insert (typing) mode. Every hjkl-style handler checks this before
/// deciding whether to intercept a keystroke or let it fall through to
/// ordinary text input — that check is the entire difference between
/// "vim-like" and "can't type the letter j".

class VimModeController extends ValueNotifier<VimMode> {
  VimModeController([super.initial = VimMode.normal]);

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;

  // Two-key sequence tracking (dd, gg, ...). AppFlowyEditor's
  // CommandShortcutEvent only matches a single key label per command —
  // it has no concept of "press this key twice". So sequences like dd/gg
  // can't be expressed as a command string ('d d' is parsed as one
  // literal, invalid, key label and crashes the keybinding lookup on
  // every keystroke). Tracking the pending first press ourselves, from
  // a CharacterShortcutEvent, is the actual way to do this.
  String? _pendingSequenceKey;
  DateTime? _pendingSequenceAt;

  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;

    // Optional: always return to insert mode when disabling Vim
    if (!enabled) {
      value = VimMode.insert;
    }

    notifyListeners();
  }

  bool get isNormal => _isEnabled && value == VimMode.normal;
  bool get isInsert => !_isEnabled || value == VimMode.insert;

  /// Read-only analysis-review mode (SCAFFOLD). Neither [isNormal] nor
  /// [isInsert] is true here, so editing shortcuts AND text input both stay
  /// suppressed while reviewing chunks.
  bool get isAnalysis => _isEnabled && value == VimMode.analysis;

  /// Character-wise visual selection mode (`v`). Like [isAnalysis] neither
  /// [isNormal] nor [isInsert] holds here, so plain typing is suppressed —
  /// motions already have their own visual branches to extend the selection
  /// (see editor_commands.dart).
  bool get isVisual => _isEnabled && value == VimMode.visual;

  /// The fixed end of the visual selection (where `v` was pressed). Null
  /// unless we're in visual mode. The head (moving end) is derived from
  /// the live editor selection, so only this one boundary needs storing.
  VisualAnchor? _visualAnchor;
  VisualAnchor? get visualAnchor =>
      value == VimMode.visual ? _visualAnchor : null;

  void enterNormalMode() {
    if (!_isEnabled) return;

    // Seeing normal again means the visual selection (if any) is abandoned;
    // a stale anchor would silently resurrect itself if the user re-entered
    // visual mode at a different spot.
    _visualAnchor = null;
    value = VimMode.normal;
  }

  void enterInsertMode() {
    value = VimMode.insert;
  }

  /// Enter visual mode and pin the selection's fixed end at [anchor].
  /// Only meaningful while Vim is enabled. [force] re-pins an existing
  /// anchor — used by `o`/`O`, which in vim swap the cursor with the
  /// anchor instead of starting a fresh selection.
  void enterVisualMode({VisualAnchor? anchor, bool force = false}) {
    if (!_isEnabled) return;
    if (value != VimMode.visual || force) _visualAnchor = anchor;
    value = VimMode.visual;
  }

  /// Enter analysis-review mode (only meaningful while Vim is enabled).
  void enterAnalysisMode() {
    if (!_isEnabled) return;
    value = VimMode.analysis;
  }

  /// Call this every time [key] is pressed in normal mode. Returns true
  /// the *second* time the same [key] is seen within [timeout] of the
  /// first (completing a "dd"/"gg"-style sequence); returns false and
  /// records this press as the pending first key otherwise.
  ///
  /// Pressing a different key clears any pending sequence, same as vim
  /// (typing 'd' then 'k' doesn't trigger 'dd').
  bool matchSequence(
    String key, {
    Duration timeout = const Duration(milliseconds: 600),
  }) {
    final now = DateTime.now();
    if (_pendingSequenceKey == key &&
        _pendingSequenceAt != null &&
        now.difference(_pendingSequenceAt!) <= timeout) {
      _pendingSequenceKey = null;
      _pendingSequenceAt = null;
      return true;
    }
    _pendingSequenceKey = key;
    _pendingSequenceAt = now;
    return false;
  }
}
