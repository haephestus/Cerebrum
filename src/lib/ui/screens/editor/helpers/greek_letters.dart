import 'package:appflowy_editor/appflowy_editor.dart';

/// Inline Greek-letter insertion: type a LaTeX-style name (`\alpha`) and
/// press SPACE to substitute the glyph (α). The terminating space in the
/// typed text is preserved, so `\alpha` keeps reading as prose (`α `).
///
/// WHY a space terminator, not instant conversion on the final letter:
/// ----------------
/// Instant conversion would fire the moment any name completes, which races
/// typed words that *begin* with a command name (`\alphabet` → `αbet`), and
/// gives no way to keep editing the command. The terminator is the same
/// commit gesture LaTeX-equation editors use; until the space lands, the
/// raw `\name` text is still plainly visible and backspace-editable.
///
/// WHY ONE event on ' ', not one event per completing letter (a, n, u, i,
/// o): a single space event has no character overlap with the vim
/// motions/daw-catch-all in [VimCharacterShortcuts] at all — those letter
/// events return `true` in normal/analysis mode (swallowing before this
/// event ever runs) and `false` in insert mode (falling through so this
/// event runs next); the space event never has to win a race it could lose
/// to a future vim remap of 'a'/'n'/'u'/'i'/'o'.
///
/// Position in the driver's list matters: AFTER the vim shortcuts, BEFORE
/// `customSlashCommand` and `standardCharacterShortcutEvents`. The
/// standard list carries markdown conversions that also fire on space
/// (bullet/heading/quote autocompletion); those match a plain ' ' anywhere,
/// so a Greek conversion that matches returns `true` here and preempts them
/// only when the text directly before the caret is `\<greekname>`. Any
/// other case returns `false` and those conversions run untouched.
///
/// Case sensitivity is deliberate: the map keys are the exact command
/// names, mirroring LaTeX where `\Delta` and `\delta` are different
/// glyphs (Δ vs δ). `<name>` matching is word-conservative — a prefix
/// that doesn't exactly name a glyph (`\alpha1`, `\alphabet`) just types
/// the space normally.
///
/// Glyph choices where LaTeX's conventions differ from common typed usage:
/// `epsilon` → ε (the Humanwide glyph people actually use in notes; LaTeX
/// `\epsilon` renders ϵ and names the alternative `\varepsilon`). Same
/// reasoning for `phi` → φ, `theta` → θ. Variant spellings (`varepsilon`,
/// `varphi`, ...) are intentionally NOT included until something needs
/// them — YAGNI on glyphs nobody has asked for.
class GreekLetterShortcuts {
  GreekLetterShortcuts._();

  /// command name → glyph. Lowercase = lowercase glyphs; PascalCase =
  /// uppercase glyphs (only the capitals with a distinct Greek form are
  /// present — Γ, Δ, Θ, Λ, Ξ, Π, Σ, Υ, Φ, Ψ, Ω; LaTeX deliberately has no
  /// `\Alpha`/`\Beta` because those capitals are identical to A/B).
  static const Map<String, String> letters = {
    // Lowercase
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'zeta': 'ζ',
    'eta': 'η',
    'theta': 'θ',
    'iota': 'ι',
    'kappa': 'κ',
    'lambda': 'λ',
    'mu': 'μ',
    'nu': 'ν',
    'xi': 'ξ',
    'omicron': 'ο',
    'pi': 'π',
    'rho': 'ρ',
    'sigma': 'σ',
    'tau': 'τ',
    'upsilon': 'υ',
    'phi': 'φ',
    'chi': 'χ',
    'psi': 'ψ',
    'omega': 'ω',
    // Uppercase (distinct Greek capitals only)
    'Gamma': 'Γ',
    'Delta': 'Δ',
    'Theta': 'Θ',
    'Lambda': 'Λ',
    'Xi': 'Ξ',
    'Pi': 'Π',
    'Sigma': 'Σ',
    'Upsilon': 'Υ',
    'Phi': 'Φ',
    'Psi': 'Ψ',
    'Omega': 'Ω',
  };

  /// The glyph for an exact command name, or null. Exposed so tests (and
  /// any future autocomplete UI) share this exact table instead of
  /// re-encoding it.
  static String? glyphFor(String name) => letters[name];

  /// The `\name` prefix matcher: a backslash immediately before the caret
  /// followed by latin letters to the very end of the text before the
  /// caret. Anchored at `$` so it only saw the span the terminator is
  /// committing — anything before the backslash is ignored.
  static final RegExp _commandPrefix = RegExp(r'\\([A-Za-z]+)$');

  /// Substitutes `\name` → glyph when SPACE is typed directly after it.
  /// Returns `false` in every other case so the space falls through to the
  /// standard markdown conversions and plain typing.
  static final CharacterShortcutEvent substituteOnSpace =
      CharacterShortcutEvent(
        key: 'greek letter substitution on space',
        character: ' ',
        handler: _substitute,
      );

  /// Kept as a list so the driver spreads ONE stable value for the whole
  /// greek feature — the same identity-stability rule the driver applies
  /// to its own shortcut lists (lists handed to AppFlowyEditor must not be
  /// rebuilt per keystroke, or the internal keyboard service reinitializes
  /// and drops the caret). `substituteOnSpace` is a static final, so this
  /// list is built once and its identity never changes.
  static List<CharacterShortcutEvent> get events => [substituteOnSpace];

  /// Space-terminator handler.
  ///
  /// Swallows the space press (returns `true`) and replaces the
  /// `\name` span with the glyph + the space, because a swallowed
  /// insertion is never typed — without re-inserting the terminator,
  /// `\alpha ` would collapse to `α` and words would jam together (`αand`).
  static Future<bool> _substitute(EditorState editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) return false;

    final offset = selection.start.offset;
    final text = delta.toPlainText();
    if (offset < 0 || offset > text.length) return false;

    final match = _commandPrefix.firstMatch(text.substring(0, offset));
    if (match == null) return false;

    final glyph = glyphFor(match.group(1)!);
    if (glyph == null) return false;

    final transaction =
        editorState.transaction
          ..replaceText(node, match.start, match.end - match.start, '$glyph ');
    await editorState.apply(transaction);

    return true;
  }
}
