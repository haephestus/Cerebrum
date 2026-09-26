#!/usr/bin/env python3
"""Generates the Cerebrum theme token classes.

Hand-writing copyWith/lerp/== for ~140 color fields is how you end up with
`analysisBlock: analysisBlock ?? this.analysisMode`. This emits them instead.
"""

import os, textwrap

# (field, light, dark, doc)
# light/dark are 8-digit ARGB hex strings.
GROUPS = [
    ("BrandColors", "lib/ui/themes/tokens/base_colors.dart",
     "Brand identity: the purple/gold/ink core every other token is mixed from.",
     [
       ("primary",      "FF6C4FCE", "FF8B72E0", "Primary brand purple. Drives selection rings, active nav, key accents."),
       ("onPrimary",    "FFFFFFFF", "FF1A1526", "Legible content drawn on top of [primary]."),
       ("primaryDeep",  "FF4B3B7A", "FF6C4FCE", "Pressed / recessed variant of [primary]."),
       ("primaryWash",  "FF6C4FCE", "FF8B72E0", "Base hue for low-alpha primary washes. Callers apply their own alpha."),
       ("accent",       "FFC9A24B", "FFD9B871", "Gold accent. Bubble/analysis highlights, streak markers."),
       ("accentDeep",   "FF8A6A00", "FFC9A24B", "Legible gold for text on light surfaces."),
       ("ink",          "FF2F2940", "FFF2EFFA", "Deepest brand ink. Headline text on light surfaces."),
     ]),

    ("SurfaceColors", "lib/ui/themes/tokens/base_colors.dart",
     "Layered background planes. Roles, not appearances: `raised` is whatever\n/// sits above `canvas` in that brightness.",
     [
       ("canvas",         "FFF4F2F8", "FF14121C", "App background, furthest plane."),
       ("raised",         "FFFFFFFF", "FF1F1F23", "Cards and sheets sitting on [canvas]."),
       ("sunken",         "FFF4F1FA", "FF26262C", "Inset wells: metric chips, segmented control tracks."),
       ("overlay",        "FFE3DEF2", "FF322C48", "Small filled chips (tags, severity pills)."),
       ("outline",        "FFE3DEF2", "FF3A3450", "Default hairline border."),
       ("outlineStrong",  "FFD5CFE8", "FF4A4368", "Emphasised border: active inputs, selected cards."),
       ("scrim",          "FF000000", "FF000000", "Base black behind modal barriers. Callers apply alpha."),
       ("cardSurface",    "FF1F1F23", "FF2A2A30", "Note/bubble card. Dark card on a light page by design."),
       ("cardSurfaceRaised", "FF2A2A30", "FF34343C", "Menus and headers sitting on [cardSurface]."),
       ("cardSurfaceSelected", "FF26262C", "FF3A3450", "Selected note card."),
       ("chipOnCard",     "FF313133", "FF3A3450", "Translucent-white chip fill composited onto [cardSurface]."),
       ("hub",            "FFFFFFFF", "FF2A2A30", "Radial dial hub backing and readout pills."),
       ("pill",           "FFFFFFFF", "FF2A2A30", "Floating chip background (hex toggle, etc)."),
     ]),

    ("ShadowColors", "lib/ui/themes/tokens/base_colors.dart",
     "Elevation shadows. Alpha is baked in so callers never hand-roll\n/// `Colors.black.withValues(alpha: 0.06)`.",
     [
       ("soft",  "14000000", "4D000000", "Resting card shadow."),
       ("strong", "40000000", "8C000000", "Raised sheet / dialog shadow."),
       ("scrim", "73000000", "99000000", "Modal barrier."),
       ("ring",  "1A000000", "40000000", "Selected-state border wash."),
     ]),

    ("TextColors", "lib/ui/themes/tokens/base_colors.dart",
     "Foreground roles. The `onDark*` family is for content drawn on\n/// [SurfaceColors.cardSurface], which stays dark in both brightnesses.",
     [
       ("strong",      "FF2F2940", "FFF2EFFA", "Primary body and heading text."),
       ("body",        "FF5B5B66", "FFC9C4D6", "Secondary body text."),
       ("muted",       "FF706F73", "FF9A95AC", "Helper/caption text. Replaces Colors.black54 on light."),
       ("faint",       "FF86858A", "FF7C7791", "Tertiary text, timestamps. Replaces Colors.black45."),
       ("disabled",    "FF9E9E9E", "FF6B6779", "Non-interactive text. Replaces Colors.black38."),
       ("onAccent",    "FFFFFFFF", "FF1A1526", "Text on [BrandColors.accent] fills."),
       ("onBrand",      "FFFFFFFF", "FFFFFFFF", "Text/icon on a [BrandColors.primary] or other saturated fill. The brand purple is dark enough in both brightnesses to keep white."),
       ("onModeBadge", "FF2F2940", "FF1A1526", "Label on an [EditorColors] mode badge. The mode hues run light (yellow/green), so the badge needs ink, not white."),
       ("onDark",      "FFFFFFFF", "FFFFFFFF", "Primary text on a dark card."),
       ("onDarkMuted", "FFA5A5A5", "FFA5A5A5", "Secondary text on a dark card. Composited white 60%."),
       ("onDarkFaint", "FF989898", "FF989898", "Tertiary text on a dark card. Composited white 54%."),
       ("onDarkIcon",  "FFBCBCBC", "FFBCBCBC", "Icon on a dark card. Composited white 70%."),
     ]),

    ("StatusColors", "lib/ui/themes/tokens/base_colors.dart",
     "Semantic state ramp. Each state exposes three roles: `surface` for a\n/// filled background, `strong` for legible text/icon, and the base for accents.",
     [
       ("success",         "FF2E7D32", "FF66BB6A", "Success / complete / graded."),
       ("successStrong",   "FF388E3C", "FF66BB6A", "Success text and icons on [successSurface]."),
       ("successSurface",  "FFE8F5E9", "FF1B2E1D", "Success background fill."),
       ("successSoft",     "FF81C784", "FF81C784", "Decorative success accent."),
       ("warning",         "FFE8A33D", "FFF0B95C", "Warning / stale / queued."),
       ("warningStrong",   "FFFF8F00", "FFFFB74D", "Warning text and icons on [warningSurface]."),
       ("warningSurface",  "FFFFF8E1", "FF33280F", "Warning background fill."),
       ("warningSoft",    "FFE0A94D", "FF6B5A2E", "Decorative warning accent."),
       ("danger",          "FFB3261E", "FFF2B8B5", "Error / destructive accent."),
       ("dangerDeep",      "FF8C2F2F", "FFE06A66", "High-emphasis danger. Priority cards, overdue counts."),
       ("dangerStrong",    "FFD32F2F", "FFEF5350", "Danger text and icons on [dangerSurface]."),
       ("dangerSoft",      "FFEF9A9A", "FFEF9A9A", "Decorative danger accent."),
       ("dangerSurface",   "FFFFF5F5", "FF2E1616", "Danger background fill."),
       ("info",            "FF2B5BD7", "FF7FA5F5", "Informational / selected accent."),
       ("infoSurface",     "FFE3F2FD", "FF16233A", "Informational background fill."),
       ("neutral",         "FF757575", "FF9E9E9E", "Neutral / off / archived."),
       ("neutralStrong",   "FF424242", "FFBDBDBD", "Neutral text and icons on [neutralSurface]."),
       ("neutralSurface",  "FFF5F5F5", "FF26262C", "Neutral background fill."),
       ("neutralSoft",     "FFB9B4CC", "FF4A4368", "Decorative neutral: study-bubble state rings, neutral badges."),
     ]),

    ("CodeColors", "lib/ui/themes/tokens/base_colors.dart",
     "Code block chrome, pinned to the One Dark family. These are dark in\n/// both brightnesses because a syntax theme is a product decision, not a\n/// brightness mirror.",
     [
       ("background",   "FF282C34", "FF282C34", "Code block body."),
       ("header",       "FF21252B", "FF21252B", "Code block header / language picker."),
       ("headerBorder", "FF181A1F", "FF181A1F", "Divider under the code header."),
       ("onCode",       "FFE6EDF3", "FFE6EDF3", "Default code text."),
       ("onCodeMuted",  "FFBDBDBD", "FF9AA0A6", "Secondary code text and icons."),
       ("gutterText",   "FF8E8E93", "FF6E7681", "Line numbers and quickview chrome."),
       ("textDefault",  "FF44474D", "FFE6EDF3", "Editor body text when no explicit colour is set."),
       ("selection",    "FF2E7BF6", "FF2E7BF6", "Selection highlight inside the editor."),
     ]),

    ("EditorColors", "lib/ui/themes/tokens/feature_colors.dart",
     "Editor, vim modes, and page chrome.\n///\n/// The four mode tokens are deliberately separate even where the default\n/// theme gives them equal values, so a custom theme can diverge them.",
     [
       ("insertMode",        "FF66BB6A", "FF66BB6A", "Vim insert mode accent."),
       ("normalMode",        "FFFFD54F", "FFFFD54F", "Vim normal mode accent."),
       ("analysisMode",      "FF66BB6A", "FF66BB6A", "Vim analysis mode accent."),
       ("analysisBlock",     "FF3A3A3A", "FF2A2A30", "Block tint while in analysis mode."),
       ("modeBadgeInsert",   "FF66BB6A", "FF66BB6A", "Mode chip fill when in insert mode."),
       ("modeBadgeNormal",   "FFFFD54F", "FFFFD54F", "Mode chip fill when in normal mode."),
       ("modeBadgeAnalysis", "FF66BB6A", "FF66BB6A", "Mode chip fill when in analysis mode."),
       ("pageBorder",        "FF3A3A3A", "FF3A3450", "Page outline."),
       ("pageShadow",        "42000000", "80000000", "Drop shadow under a page."),
       ("pageShadowSoft",    "24000000", "4D000000", "Ambient shadow under a page."),
       ("staleTint",         "24FFA000", "2EFFA000", "Page wash when the analysis is stale."),
       ("analysisTint",      "2EFFC107", "33FFC107", "Page wash while analysis is in flight."),
       ("staleBadge",        "FFE65100", "FFFF8A65", "Stale-state icon and label."),
       ("analysisBadge",     "FFF9A825", "FFFDD835", "In-flight analysis icon and label."),
       ("savedBadge",        "FF2E7D32", "FF66BB6A", "Saved-state dot and label."),
       ("unsavedBadge",      "FFEF6C00", "FFFFB74D", "Unsaved-state dot and label."),
       ("neutralBadge",      "FF757575", "FF9E9E9E", "Neutral-state dot and label."),
       ("linkColor",         "FF2B5BD7", "FF7FA5F5", "Rendered link text."),
       ("selection",         "FF2E7BF6", "FF2E7BF6", "Text selection highlight."),
       ("blockquoteBar",     "FF6C4FCE", "FF8B72E0", "Accent bar down the left of a blockquote."),
       ("eraserFill",        "1F000000", "1F000000", "Filled body of the eraser cursor ring."),
       ("eraserStroke",      "73000000", "73000000", "Outline of the eraser cursor ring."),
       ("penDefault",        "FF000000", "FF000000", "Ink colour for the annotator's freehand pen."),
     ]),

    ("DialColors", "lib/ui/themes/tokens/feature_colors.dart",
     "Radial tool dial chrome. The wheel's own colour *palette* is user data\n/// (EditorSettingsStore), not theming — only the dial's furniture lives here.",
     [
       ("accent",        "FF2E7BF6", "FF2E7BF6", "Active arc, selected chip, size ring."),
       ("hubFill",       "FFFFFFFF", "FF2A2A30", "Hub disc backing."),
       ("hubStroke",     "FFE0E0E0", "FF4A4368", "Hairline around the hub."),
       ("selectedWash",  "2E2E7BF6", "3D2E7BF6", "Wash behind the selected tool chip."),
       ("chipIdle",      "FFF5F5F5", "FF34343C", "Unselected tool chip fill."),
       ("chipIdleIcon",  "FF757575", "FFA5A5A5", "Unselected tool chip glyph."),
       ("knobFill",      "FFFFFFFF", "FF2A2A30", "Size-ring knob fill."),
       ("centerStroke",  "FFBDBDBD", "FF6B6779", "Ring around the centre colour disc."),
       ("swatchOutline", "FFFFFFFF", "FFF2EFFA", "Outline marking the active swatch."),
       ("eraserCenter",  "FFE0E0E0", "FF4A4368", "Centre disc while the eraser is active."),
       ("previewFg",     "FF212121", "FFF2EFFA", "Stroke-preview text."),
       ("previewBg",     "FFFFFFFF", "FF2A2A30", "Stroke-preview backing."),
       ("labelMuted",    "FF757575", "FFA5A5A5", "Hex labels and the empty-wheel hint."),
       ("handleIdle",    "FFE0E0E0", "FF4A4368", "Readonly slider and toggle borders."),
     ]),

    ("GanttColors", "lib/ui/themes/tokens/feature_colors.dart",
     "Study-plan gantt: phase progression, week states, and task-type coding.",
     [
       ("current",        "FF3F51B5", "FF7986CB", "The phase currently being worked."),
       ("nextUp",         "FFE8A33D", "FFF0B95C", "The phase queued behind [current]."),
       ("upcoming",       "FF9E9E9E", "FF757575", "Every phase not yet started."),
       ("todayMarker",    "FFFF5252", "FFFF8A80", "The today line and its handle."),
       ("weekComplete",   "FF43A047", "FF66BB6A", "A completed week cell."),
       ("weekActive",     "FF3F51B5", "FF7986CB", "The in-flight week cell."),
       ("weekUpcoming",   "FF9E9E9E", "FF757575", "A future week cell."),
       ("taskStudy",      "FF3F51B5", "FF7986CB", "Task type: study."),
       ("taskPractice",   "FF00897B", "FF4DB6AC", "Task type: practice."),
       ("taskBuild",      "FFF57C00", "FFFFB74D", "Task type: build."),
       ("taskReview",     "FF7B1FA2", "FFBA68C8", "Task type: review."),
       ("taskMilestone",  "FFD32F2F", "FFEF5350", "Task type: milestone check."),
       ("checkpoint",     "FF673AB7", "FF9575CD", "Month-marker checkpoint tag."),
       ("topicTag",       "FF00897B", "FF4DB6AC", "Free-form topic tag."),
       ("onTask",         "FFFFFFFF", "FF1A1526", "Content drawn on a filled task bar."),
       ("tagWash",        "FF000000", "FF000000", "Base for a tag's 10% background wash."),
       ("tagBorder",      "FF000000", "FF000000", "Base for a tag's 35% border wash."),
       ("todayWash",      "FF3F51B5", "FF7986CB", "Base for the 'Today' chip wash."),
       ("archived",       "FF9E9E9E", "FF757575", "An archived plan."),
       ("completed",      "FF1976D2", "FF64B5F6", "A completed plan in the portfolio view."),
     ]),

    ("QuizColors", "lib/ui/themes/tokens/feature_colors.dart",
     "Engram completion UI: spaced-repetition grading and answer feedback.",
     [
       ("rateAgain",       "FFD32F2F", "FFEF5350", "Grade: again."),
       ("rateHard",        "FFF57C00", "FFFFB74D", "Grade: hard."),
       ("rateGood",        "FF1976D2", "FF64B5F6", "Grade: good."),
       ("rateEasy",        "FF388E3C", "FF66BB6A", "Grade: easy."),
       ("correctSurface",  "FFE8F5E9", "FF1B2E1D", "Correct-answer tile and result card."),
       ("correctStrong",   "FF388E3C", "FF66BB6A", "Correct-answer icon and label."),
       ("incorrectSurface","FFFFEBEE", "FF2E1616", "Wrong-answer tile and result card."),
       ("incorrectStrong", "FFD32F2F", "FFEF5350", "Wrong-answer icon and label."),
       ("selectedSurface", "FFE3F2FD", "FF16233A", "A selected but ungraded option."),
       ("pendingSurface",  "FFFFF8E1", "FF33280F", "Queued / awaiting-grade card."),
       ("pendingStrong",   "FFFF8F00", "FFFFB74D", "Queued icon and label."),
       ("flippedSurface",  "FFE8EAF6", "FF26263A", "Flashcard back face."),
       ("cardBorder",      "12000000", "1FFFFFFF", "Flashcard hairline."),
       ("gradedSurface",   "FFE8F5E9", "FF1B2E1D", "Card body once an attempt is graded."),
     ]),
]

HEADER = """// GENERATED by tool/gen_tokens.py -- do not edit by hand.
//
// Run `python3 tool/gen_tokens.py` after changing a token, or edit the spec
// there. Hand-maintained edits to the classes below WILL be overwritten.
"""


def dart_hex(h):
    return "0x%s" % h


def doc_comment(text, indent):
    pad = " " * indent
    return "\n".join(pad + "/// " + line for line in text.split("\n"))


def gen_group(name, path, doc, fields):
    out = [doc_comment(doc, 0)]
    out.append("@immutable")
    out.append("class %s {" % name)
    out.append("  const %s({" % name)
    for f, _l, _d, _doc in fields:
        out.append("    required this.%s," % f)
    out.append("  });\n")

    for f, _l, _d, fdoc in fields:
        out.append(doc_comment(fdoc, 2))
        out.append("  final Color %s;" % f)
    out.append("")

    # copyWith
    out.append("  %s copyWith({" % name)
    for f, _l, _d, _doc in fields:
        out.append("    Color? %s," % f)
    out.append("  }) => %s(" % name)
    for f, _l, _d, _doc in fields:
        out.append("    %s: %s ?? this.%s," % (f, f, f))
    out.append("  );\n")

    # lerp
    out.append("  static %s lerp(%s a, %s b, double t) => %s(" % (name, name, name, name))
    for f, _l, _d, _doc in fields:
        out.append("    %s: Color.lerp(a.%s, b.%s, t)!," % (f, f, f))
    out.append("  );\n")

    # equality -- every field named explicitly so adding one without wiring it
    # up here is a visible omission rather than a silent pass.
    out.append("  @override")
    out.append("  bool operator ==(Object other) {")
    out.append("    if (identical(this, other)) return true;")
    out.append("    return other is %s &&" % name)
    for f, _l, _d, _doc in fields:
        out.append("        %s == other.%s &&" % (f, f))
    # last field: swap trailing && for ;
    out[-1] = out[-1].replace("&&", ";")
    out.append("  }\n")

    out.append("  @override")
    out.append(
        "  int get hashCode => Object.hashAll([%s]);"
        % ", ".join(f for f, _l, _d, _doc in fields)
    )
    out.append("")
    out.append(doc_comment(
        "Every token in this group, by name.\n"
        "///\n"
        "/// Used by the theming tests to prove [copyWith] touches only the field\n"
        "/// it was given, and handy for dumping or diffing a palette.", 2))
    out.append("  Map<String, Color> get asMap => {")
    for f, _l, _d, _doc in fields:
        out.append("    '%s': %s," % (f, f))
    out.append("  };")
    out.append("}")
    return "\n".join(out) + "\n"


def group_field(gname):
    """`SurfaceColors` -> `surface`, matching the field on CerebrumColors."""
    stem = gname[: -len("Colors")] if gname.endswith("Colors") else gname
    return stem[0].lower() + stem[1:]


def main():
    by_file = {}
    for name, path, doc, fields in GROUPS:
        by_file.setdefault(path, []).append((name, doc, fields))

    for path, groups in by_file.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        chunks = [HEADER, "import 'package:flutter/material.dart';\n"]
        for name, doc, fields in groups:
            chunks.append(gen_group(name, path, doc, fields))
        with open(path, "w") as f:
            f.write("\n".join(chunks))
        total = sum(len(fl) for _n, _d, fl in groups)
        print("wrote %s: %d groups, %d tokens" % (path, len(groups), total))

    # The default family's token instances come from this same spec, so the
    # light/dark values can never drift from the declarations above, and there
    # is no hand-copied duplicate to keep in sync.
    out = [HEADER]
    out.append("import 'package:cerebrum/ui/themes/extensions.dart';")
    out.append("import 'package:cerebrum/ui/themes/tokens/base_colors.dart';")
    out.append("import 'package:cerebrum/ui/themes/tokens/feature_colors.dart';")
    out.append("import 'package:flutter/material.dart';\n")
    # (name, light, dark, doc) -> the hex for this variant is index 1 or 2.
    for variant, idx in (("Light", 1), ("Dark", 2)):
        out.append("/// Every token resolved for the default theme's %s brightness." % variant.lower())
        out.append("const cerebrum%sTokens = CerebrumColors(" % variant)
        for gname, _path, _doc, fields in GROUPS:
            out.append("  %s: %s(" % (group_field(gname), gname))
            for fname, light, dark, _doc in fields:
                out.append("    %s: Color(0x%s)," % (fname, light if idx == 1 else dark))
            out.append("  ),")
        out.append(");\n")
    with open("lib/ui/themes/tokens/default_palette.dart", "w") as f:
        f.write("\n".join(out))
    print("wrote lib/ui/themes/tokens/default_palette.dart")


if __name__ == "__main__":
    main()
