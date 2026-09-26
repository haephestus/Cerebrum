import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/themes/tokens/base_colors.dart';
import 'package:cerebrum/ui/themes/tokens/feature_colors.dart';
import 'package:flutter/material.dart';

/// Every colour Cerebrum draws, grouped by the surface that owns it.
///
/// This is the single source of truth for theming. Widgets read
/// `context.cerebrum.<group>.<token>`; nothing outside `lib/ui/themes/`
/// should name a raw `Color(0x...)` or a `Colors.*` constant.
///
/// Adding a token:
///   1. Add it to the spec in `tool/gen_tokens.py` and re-run that script.
///      Do not hand-edit `tokens/` -- it is generated, and a hand-added field
///      with no `copyWith`/`lerp` entry is exactly the bug that shipped in the
///      first version of this class (`analysisBlock` fell back to
///      `analysisMode`).
///   2. Give it a value in BOTH brightnesses of the default family
///      (`lib/ui/themes/default.dart`). Every token is non-nullable on
///      purpose: a custom theme should be forced to make a decision for each
///      role rather than silently inheriting a hardcoded fallback.
///
/// Grouping is by owning surface, not by hue, so a theme author can reason
/// about "the editor" or "the gantt" as a unit.
@immutable
class CerebrumColors extends ThemeExtension<CerebrumColors> {
  const CerebrumColors({
    required this.brand,
    required this.surface,
    required this.shadow,
    required this.text,
    required this.status,
    required this.code,
    required this.editor,
    required this.dial,
    required this.gantt,
    required this.quiz,
  });

  /// Purple / gold / ink core.
  final BrandColors brand;

  /// Layered background planes.
  final SurfaceColors surface;

  /// Elevation shadows, alpha pre-baked.
  final ShadowColors shadow;

  /// Foreground roles, including the on-dark-card family.
  final TextColors text;

  /// Semantic state ramp: success / warning / danger / info / neutral.
  final StatusColors status;

  /// Code block chrome (One Dark family, dark in both brightnesses).
  final CodeColors code;

  /// Editor, vim modes, page chrome.
  final EditorColors editor;

  /// Radial tool dial furniture.
  final DialColors dial;

  /// Study-plan gantt.
  final GanttColors gantt;

  /// Engram completion / spaced repetition.
  final QuizColors quiz;

  @override
  CerebrumColors copyWith({
    BrandColors? brand,
    SurfaceColors? surface,
    ShadowColors? shadow,
    TextColors? text,
    StatusColors? status,
    CodeColors? code,
    EditorColors? editor,
    DialColors? dial,
    GanttColors? gantt,
    QuizColors? quiz,
  }) {
    return CerebrumColors(
      brand: brand ?? this.brand,
      surface: surface ?? this.surface,
      shadow: shadow ?? this.shadow,
      text: text ?? this.text,
      status: status ?? this.status,
      code: code ?? this.code,
      editor: editor ?? this.editor,
      dial: dial ?? this.dial,
      gantt: gantt ?? this.gantt,
      quiz: quiz ?? this.quiz,
    );
  }

  @override
  CerebrumColors lerp(ThemeExtension<CerebrumColors>? other, double t) {
    if (other is! CerebrumColors) return this;
    return CerebrumColors(
      brand: BrandColors.lerp(brand, other.brand, t),
      surface: SurfaceColors.lerp(surface, other.surface, t),
      shadow: ShadowColors.lerp(shadow, other.shadow, t),
      text: TextColors.lerp(text, other.text, t),
      status: StatusColors.lerp(status, other.status, t),
      code: CodeColors.lerp(code, other.code, t),
      editor: EditorColors.lerp(editor, other.editor, t),
      dial: DialColors.lerp(dial, other.dial, t),
      gantt: GanttColors.lerp(gantt, other.gantt, t),
      quiz: QuizColors.lerp(quiz, other.quiz, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CerebrumColors &&
        brand == other.brand &&
        surface == other.surface &&
        shadow == other.shadow &&
        text == other.text &&
        status == other.status &&
        code == other.code &&
        editor == other.editor &&
        dial == other.dial &&
        gantt == other.gantt &&
        quiz == other.quiz;
  }

  @override
  int get hashCode => Object.hashAll([
    brand,
    surface,
    shadow,
    text,
    status,
    code,
    editor,
    dial,
    gantt,
    quiz,
  ]);
}
