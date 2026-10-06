import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the caret-follow scroll decision.
///
/// The decision lives in [followScrollDelta] as a pure function precisely so
/// it can be checked here.
///
/// It measures the CARET, not the page. That is the whole point, and getting it
/// wrong was the bug this replaces:
///
///   * Measuring the PAGE cannot work when a page is taller than the viewport.
///     No offset satisfies "page fully visible", so it degenerates into either a
///     permanent no-op or a jump to `maxScrollExtent` — the list flying to the
///     end of the note.
///   * A caret is small enough to always bring into view, so the question is
///     always answerable.
///
/// The other half of the contract is that it does NOT scroll when it must not.
/// AppFlowy's own auto-scroll chased the caret unconditionally through the
/// nearest Scrollable — here the outer page list — which is what made the view
/// lurch to the previous page after a backspace-merge.
const _viewport = Rect.fromLTWH(0, 0, 800, 600);

/// A collapsed caret: ~2px wide, one line tall.
Rect _caret(double top, {double left = 40}) =>
    Rect.fromLTWH(left, top, 2, 24);

void main() {
  group('followScrollDelta', () {
    test('returns null when the caret sits comfortably inside the viewport', () {
      // Mid-viewport with room to spare on both sides: typing must not move it.
      expect(
        followScrollDelta(caretRect: _caret(300), viewportRect: _viewport),
        isNull,
      );
    });

    test('returns null at the exact centre of the margin band', () {
      // Band is viewport inset by 48 → caret must be within 48..552 to be a
      // no-op. 48 and 552 are both inside, inclusive.
      expect(
        followScrollDelta(caretRect: _caret(48), viewportRect: _viewport),
        isNull,
      );
      expect(
        followScrollDelta(caretRect: _caret(528), viewportRect: _viewport),
        isNull,
      );
    });

    test('scrolls down by exactly enough to raise the caret into the band', () {
      // Caret top at 700, bottom 724. Band bottom is 552. Shortfall is
      // 724 - 552 = 172 — a bounded move, not a jump to the end of the list.
      expect(
        followScrollDelta(caretRect: _caret(700), viewportRect: _viewport),
        172.0,
      );
    });

    test('scrolls up by exactly enough to drop the caret into the band', () {
      // Caret above the band top (48): 10 - 48 = -38.
      expect(
        followScrollDelta(caretRect: _caret(10), viewportRect: _viewport),
        -38.0,
      );
    });

    test('a caret far below scrolls only by its own shortfall', () {
      // THE REGRESSION. A page-anchored implementation computed this as
      // "align the page top with the viewport top" and clamped to
      // maxScrollExtent — the list flying to the end of the note. The caret
      // delta is small and bounded no matter how far down it is.
      expect(
        followScrollDelta(caretRect: _caret(4000), viewportRect: _viewport),
        4000.0 + 24.0 - 552.0,
      );
    });

    test('does nothing for a caret with no size (page not laid out)', () {
      expect(
        followScrollDelta(caretRect: Rect.zero, viewportRect: _viewport),
        isNull,
      );
      expect(
        followScrollDelta(
          caretRect: Rect.fromLTWH(40, 700, 0, 24),
          viewportRect: _viewport,
        ),
        isNull,
      );
    });

    test('sub-pixel jitter inside the tolerance does not re-trigger', () {
      // 552.5 is 0.5px past the band edge — within the 2px tolerance, so a
      // settled caret must not keep the list animating.
      expect(
        followScrollDelta(caretRect: _caret(528.5), viewportRect: _viewport),
        isNull,
      );
      // Just outside tolerance it must move.
      expect(
        followScrollDelta(caretRect: _caret(540), viewportRect: _viewport),
        isNotNull,
      );
    });

    test('clamps the margin on a viewport too short to hold it', () {
      // A 60px-tall viewport with a 24px caret has 36px of slack. A 48px band
      // cannot fit, so it clamps to 18: usable range 18..42. A caret at 20
      // (bottom 44) sits inside that, so it must NOT move — otherwise the
      // follow fires on every tick and walks the list to maxScrollExtent.
      const short = Rect.fromLTWH(0, 0, 400, 60);
      expect(
        followScrollDelta(caretRect: _caret(20), viewportRect: short),
        isNull,
      );
      // A caret genuinely below the clamped band still moves, by its shortfall
      // relative to 42 — bounded, not the whole list.
      expect(
        followScrollDelta(caretRect: _caret(300), viewportRect: short),
        324.0 - 42.0,
      );
    });

    test('an unresolvable target (page deleted) is rejected, not clamped', () {
      // A driver whose page was removed resolves to -1. That must mean "do
      // nothing" rather than being clamped to 0, which would scroll the list
      // to the top because of a page that no longer exists.
      expect(isFollowTargetValid(-1, 3), isFalse);
      expect(isFollowTargetValid(99, 3), isFalse);
      // The live cases must still pass, including the last page.
      expect(isFollowTargetValid(0, 3), isTrue);
      expect(isFollowTargetValid(2, 3), isTrue);
      // A note that has lost every page has no valid target at all.
      expect(isFollowTargetValid(0, 0), isFalse);
    });
  });
}