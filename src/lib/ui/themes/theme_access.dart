import 'package:cerebrum/ui/themes/extensions.dart';
import 'package:cerebrum/ui/themes/tokens/default_palette.dart';
import 'package:flutter/material.dart';

/// Token access.
///
/// `context.cerebrum` is the intended way to read a Cerebrum colour from a
/// widget. It resolves through [Theme.of], so it works anywhere below the
/// [MaterialApp] and rebuilds when the theme changes.
///
/// For a [CustomPainter] there is no [BuildContext] inside [CustomPainter.paint],
/// so the token object must be captured at construction and handed to the
/// painter as a field. Do that at the `CustomPaint` site, where a context is in
/// scope:
///
/// ```dart
/// CustomPaint(
///   painter: MyPainter(colors: context.cerebrum, ...),
/// )
/// ```
///
/// Pass the whole [CerebrumColors] rather than the handful of tokens the
/// painter happens to need today; it keeps the painter themeable without a
/// signature change when a new token is required.
extension CerebrumThemeAccess on BuildContext {
  /// The active theme's colour tokens.
  ///
  /// Falls back to the default family's light tokens if no [CerebrumColors]
  /// extension is registered, so a bare `ThemeData` in a test or a one-off
  /// dialog still resolves rather than throwing.
  CerebrumColors get cerebrum =>
      Theme.of(this).extension<CerebrumColors>() ?? defaultCerebrumColors;
}

/// Token access from a bare [ThemeData], for the painter case where a
/// [BuildContext] is not available.
extension CerebrumThemeDataAccess on ThemeData {
  /// The active theme's colour tokens, or the default light set if absent.
  CerebrumColors get cerebrum =>
      extension<CerebrumColors>() ?? defaultCerebrumColors;
}

/// Last-resort tokens so a `ThemeData` without the extension still renders.
///
/// Deliberately the default family's *light* set: it is a safety net for tests
/// and previews, not a supported runtime state. Every real theme family
/// registers a full [CerebrumColors].
const defaultCerebrumColors = cerebrumLightTokens;
