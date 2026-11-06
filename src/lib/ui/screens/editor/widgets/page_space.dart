/// One note page's CANONICAL document space.
///
/// Every page is laid out ONCE at exactly [kDocSheetWidth] logical units wide,
/// in this file's aspect, regardless of window size, layout mode (vertical /
/// horizontal overview), or device pixel ratio. The on-screen size of a page
/// is a pure view transform (FittedBox in PageSurface) applied on top of that
/// stable layout — it changes how big a page LOOKS and nothing else:
///
///   * Text, ink, block chrome, popovers and measurements all run in document
///     units, so the SAME amount of text occupies the SAME fraction of every
///     page at every screen size — the page invariant that per-widget font
///     scaling could never actually guarantee (one unscaled metric broke it).
///   * Overflow detection, table row-splitting and analysis-popover geometry
///     are window-independent, so they can't produce phantom spills when the
///     window resizes or the mode flips.
///   * No consumer may introduce an environment-derived size (MediaQuery,
///     viewport, device pixel ratio) into the page's layout. Anything that
///     needs to look a fixed on-screen size belongs OUTSIDE the fitted page,
///     not inside it.
const double kDocSheetWidth = 700.0;

/// A4 portrait aspect (width / height). PageSurface derives the document
/// height from this so the transformed page fills its on-screen box EXACTLY —
/// the zoom is width/700 and the aspect matches, so there are no gaps.
const double kPageAspectRatio = 1 / 1.414;

/// Body text size, document units. Deep widgets render relative to the
/// document space, so this is a constant forever — do NOT multiply it by a
/// scale factor anywhere.
const double kBaseFontSize = 7.0;

/// Horizontal editor padding, document units (AppFlowy's desktop default is
/// 100). Same rule as [kBaseFontSize]: constant, never scaled by consumers.
const double kBaseHorizontalPadding = 40.0;

/// Vertical editor padding, document units. AppFlowy's desktop default is 8;
/// keep 20 (same ballpark as the horizontal 40) so text doesn't sit flush with
/// the paper's top edge and the box isn't cramped vertically. Constant, like
/// [kBaseFontSize] — never scaled by consumers.
const double kBaseVerticalPadding = 20.0;

/// Heading sizes as multiples of [kBaseFontSize], indexed by level - 1.
///
/// TUNING KNOB — this is the answer to "headings are huge": the stock
/// `HeadingBlockComponentBuilder` hardcodes ABSOLUTE sizes (32/28/24/18pt for
/// levels 1..6) that know nothing about the body — at an 8pt body an H1 is a
/// 4x billboard. Cerebrum instead registers the heading builder with a
/// body-relative override, so these multipliers ARE the heading size at any
/// body size: stock H1-vs-8pt was 4.00x; the defaults below start at 2.25x.
/// Dial the sweet spotted in live. Keep every value > 1.0 and the list ordered
/// descending; levels 4-6 sharing one multiplier is deliberate — they should
/// read as "slightly emphasized body", not as three competing sizes.
const List<double> kHeadingFontSizeScale = [
  2.25, // Heading 1
  1.95, // Heading 2
  1.65, // Heading 3
  1.35, // Heading 4
  1.15, // Heading 5
  1.0, // Heading 6
];

/// Body-relative heading font size for heading [level] (clamped to 1..6).
double kHeadingFontSizeFor(int level) {
  final idx = (level - 1).clamp(0, kHeadingFontSizeScale.length - 1);
  return kHeadingFontSizeScale[idx] * kBaseFontSize;
}

/// Editor line height as the single caret/row-slack knob, document-space.
///
/// TUNING KNOB — the caret height IS the line box: AppFlowy derives it from
/// `getFullHeightForCaret` with the leading split evenly above/below the
/// glyphs (TextLeadingDistribution.even), so at 1.5x an 8pt body the line
/// box is 12 while the visible glyphs are ~8 — the caret fills the whole box
/// and the leftover shows up as dead space under each row. Lower this and
/// three things happen together (all one knob, by design): the caret shrinks,
/// the under-row slack shrinks, and PAGES HOLD MORE LINES — so the backward
/// reflow will pull the next page's content up after the change. Stock
/// desktop default 1.5; sweet-spot range for 8pt body ~1.3-1.5.
const double kLineHeight = 1.0;

/// List icon column sizing in body ems (multiples of [kBaseFontSize]).
///
/// The stock list builders hardcode the bullet/number/checkbox column as fixed
/// dp — `BoxConstraints(minWidth: 26, minHeight: 22)` and a 22px checkbox SVG
/// — correct only at the stock 16pt body. kLineHeight lives on the rich text,
/// NOT the icon column, so at a smaller body the column alone is ~2x the row:
/// the "gap under list items that lineHeight didn't fix". These ratios are the
/// stock column expressed at its 16pt reference (26/16, 22/16), so the look is
/// identical at a 16pt body and scales WITH the body instead of ignoring it.
const double kListIconMinWidthEm = 26 / 16;
const double kListIconMinHeightEm = 22 / 16;
