import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';

/// Faint "H1"/"H2"/… gutter tag prepended to every non-empty heading block.
///
/// The tag is pure chrome — it is NOT part of the node's delta and is never
/// persisted, selected, or copied. Empty headings are left alone so the
/// stock "Heading N" placeholder isn't shadowed by a redundant tag.
///
/// Shared by Strategy A (via the driver's `blockWrapper`) and Strategy B
/// (in the page block component) — same widget, same placement, same look.
class HeadingLevelTag extends StatelessWidget {
  const HeadingLevelTag({required this.level, required this.child, super.key});

  final int level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // 2px down so the tag lands on the heading's first baseline;
          // 6px right so it never kisses the heading's first glyph.
          padding: const EdgeInsets.only(top: 4, right: 3),
          child: Opacity(
            opacity: 0.8,
            child: Text(
              'H$level',
              style: TextStyle(
                fontSize: kBaseFontSize * 0.6,
                height: kLineHeight,
                fontWeight: FontWeight.w700,
                color: context.cerebrum.brand.accent,
              ),
            ),
          ),
        ),
        // Expanded, not Flexible: headings are full-width (their own
        // textAlign decides where the glyphs sit), so the child needs the
        // remaining space, not a shrink-wrap fit.
        Expanded(child: child),
      ],
    );
  }
}
