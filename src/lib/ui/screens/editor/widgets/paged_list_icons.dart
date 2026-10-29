import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'page_space.dart';

/// Body-relative replacements for the stock list icons, installed via the
/// list builders' `iconBuilder` slots (see AppFlowyTextDriver's builder map).
///
/// WHY THIS EXISTS: the stock `_NumberedListIcon` / `_BulletedListIcon` /
/// `_TodoListIcon` all hardcode a fixed-dp icon column —
/// `BoxConstraints(minWidth: 26, minHeight: 22)`, a 22px checkbox SVG — which
/// is correct only at the stock 16pt body. The line-height knob lives on the
/// rich text and NEVER touches that column, so at a smaller body the column
/// alone is ~2x the row: an apparent "gap under every list item that
/// lineHeight didn't sync". These keep the stock glyphs and nesting behavior,
/// but every dimension is a [kBaseFontSize] em (ratios carried over from the
/// stock 16pt reference — see page_space.dart) so the icon column scales with
/// the body like everything else in the canonical page space.
class PagedListIcons {
  PagedListIcons._();

  /// Gutter after the icon, carried over unchanged from the stock icons
  /// (it scales visually through the fitted page transform, not the body).
  static const _gutter = EdgeInsets.only(right: 4.0);

  /// Column that can never be taller than an ordinary text row relative to
  /// the body — this is the pixel-look fix: the stock 22dp minimum was what
  /// padded empty list rows to ~2 lines.
  static BoxConstraints get _column => BoxConstraints(
        minWidth: kListIconMinWidthEm * kBaseFontSize,
        minHeight: kBaseFontSize,
      );

  /// The EXACT TextHeightBehavior editor rows lay out with. Icons must go
  /// through the same behavior or their glyph box is sized by different
  /// metrics than the row's first line — a Center() inside a hand-made slot
  /// then puts the number's baseline at the wrong height (the raised
  /// numbers on multi-line items). Read off the editor style so it can't
  /// drift.
  static TextHeightBehavior? _rowBehavior(BuildContext context) {
    final tsc =
        context.read<EditorState>().editorStyle.textStyleConfiguration;
    return TextHeightBehavior(
      applyHeightToFirstAscent: tsc.applyHeightToFirstAscent,
      applyHeightToLastDescent: tsc.applyHeightToLastDescent,
      leadingDistribution: tsc.leadingDistribution,
    );
  }

  /// Same body-text style the stock icons inherit (document-space body
  /// size + theme color) — read off the editor style so it can't drift.
  static TextStyle _bodyText(BuildContext context) =>
      context.read<EditorState>().editorStyle.textStyleConfiguration.text;

  /// Numbered list: "1." / latin / roman cycling by nesting depth, straight
  /// port of the stock `_NumberedListIcon` numbering (that logic is
  /// library-private, so it's replicated here; numerus is stock's import but
  /// not a direct dependency of this app, so the roman conversion is local).
  static Widget numbered(BuildContext context, Node node, TextDirection dir) {
    final depth = _nestLevel(node, 'numbered_list');
    final indexInLevel = _indexAmongSiblings(node);
    final text = switch (depth % 3) {
      1 => _latin(indexInLevel),
      2 => _roman(indexInLevel),
      _ => '$indexInLevel',
    };
    return Container(
      constraints: _column,
      padding: _gutter,
      child: Align(
        alignment: Alignment.topCenter,
        child: Text.rich(
          TextSpan(text: '$text.', style: _bodyText(context)),
          textDirection: dir,
          // Same layout behavior as the row's rich text — without this the
          // number's glyph box is computed from different metrics and the
          // baseline lands higher than the body text.
          textHeightBehavior: _rowBehavior(context),
        ),
      ),
    );
  }

  /// Bulleted list: '●' / '◯' / '□' by nesting depth at half glyph scale,
  /// mirroring the stock icon.
  static Widget bulleted(BuildContext context, Node node) {
    final depth = _nestLevel(node, 'bulleted_list');
    const glyphs = ['●', '◯', '□'];
    return Container(
      constraints: _column,
      padding: _gutter,
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          glyphs[depth % glyphs.length],
          style: _bodyText(context),
          textScaler: const TextScaler.linear(0.5),
          textHeightBehavior: _rowBehavior(context),
        ),
      ),
    );
  }

  /// Todo list: the stock check/uncheck SVG at a body-relative box, keeping
  /// the click-to-toggle behavior via the builder-provided callback.
  static Widget todo(BuildContext context, Node node, VoidCallback onCheck) {
    final checked = node.attributes[TodoListBlockKeys.checked] as bool? ?? false;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCheck,
        child: Container(
          constraints: _column,
          padding: _gutter,
          child: Align(
            alignment: Alignment.topLeft,
            child: EditorSvg(
              width: kBaseFontSize,
              height: kBaseFontSize,
              name: checked ? 'check' : 'uncheck',
            ),
          ),
        ),
      ),
    );
  }

  // ---- stock numbering port (library-private upstream) -------------------

  /// Nesting depth within a list chain: how many ancestors (or self-chain)
  /// share this block type. Mirrors the stock `indexInRootLevel`.
  static int _nestLevel(Node node, String type) {
    var level = 0;
    Node? parent = node.parent;
    while (parent != null) {
      if (parent.type == type) {
        level++;
      }
      parent = parent.parent;
    }
    return level;
  }

  /// Ordinal among consecutive numbered-list siblings, starting at the
  /// recorded start number when the chain carried one. Straight port of the
  /// stock `indexInSameLevel` walk (numbered lists only).
  static int _indexAmongSiblings(Node node) {
    var level = 1;
    Node? previous = node.previous;
    if (previous == null || previous.type != NumberedListBlockKeys.type) {
      return node.attributes[NumberedListBlockKeys.number] as int? ?? level;
    }
    int? startNumber;
    while (previous != null && previous.type == NumberedListBlockKeys.type) {
      startNumber = previous.attributes[NumberedListBlockKeys.number] as int?;
      level++;
      previous = previous.previous;
    }
    if (startNumber != null) return startNumber + level - 1;
    return level;
  }

  static String _latin(int n) {
    // Stocks lowercase 26-letter cycle: 1 -> 'a', 27 -> 'aa'.
    var number = n;
    var result = '';
    while (number > 0) {
      final remainder = (number - 1) % 26;
      result = String.fromCharCode(remainder + 65) + result;
      number = (number - 1) ~/ 26;
    }
    return result.toLowerCase();
  }

  static String _roman(int n) {
    const table = [
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var number = n;
    var result = '';
    for (final (value, symbol) in table) {
      while (number >= value) {
        result += symbol;
        number -= value;
      }
    }
    return result;
  }
}
