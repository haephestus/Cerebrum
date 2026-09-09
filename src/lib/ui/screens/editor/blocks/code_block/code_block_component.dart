import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:provider/provider.dart';

// Add to pubspec.yaml — neither of these constrains appflowy_editor's
// version at all, so they can't reintroduce the ^2.3.3 conflict:
//   flutter_highlight: ^0.7.0
//   highlight: ^0.7.0
//
// `provider` is ALREADY a transitive dependency (appflowy_editor itself
// depends on it and wraps its widget tree in a Provider<EditorState>),
// but add it directly too since this file imports it explicitly:
//   provider: ^6.0.5

/// Node type string for the code block, and the attribute key it stores
/// its selected language under. `blockComponentDelta` (the shared
/// attribute key every text block uses for its Delta) is imported from
/// appflowy_editor itself, same as your existing _codeBlockMenuItem uses.
const String kCodeBlockType = 'code_block';
const String kCodeBlockLanguageKey = 'language';

/// A handful of common languages for the switcher. `flutter_highlight`
/// ships many more (see package:highlight/languages/*.dart) — add any
/// you need to this list, the string must match highlight.dart's
/// registered language name.
const List<String> kCodeBlockLanguages = [
  'plaintext',
  'dart',
  'javascript',
  'typescript',
  'python',
  'rust',
  'go',
  'java',
  'kotlin',
  'swift',
  'c',
  'cpp',
  'csharp',
  'ruby',
  'php',
  'sql',
  'bash',
  'yaml',
  'json',
  'html',
  'css',
  'markdown',
];

/// Builds a code_block Node, mirroring the shape your existing
/// `_codeBlockMenuItem` constructs by hand — use this instead so the
/// `language` attribute is always present from creation.
Node codeBlockNode({Delta? delta, String language = 'plaintext'}) {
  return Node(
    type: kCodeBlockType,
    attributes: {
      blockComponentDelta: (delta ?? Delta()).toJson(),
      kCodeBlockLanguageKey: language,
    },
  );
}

/// Monospace text style shared by both the highlighted layer and the
/// (invisible) editable layer — MUST stay identical between the two or
/// the transparent caret layer will drift out of alignment with the
/// colored text underneath it.
const TextStyle _codeTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Courier', 'Consolas', 'Menlo'],
  fontSize: 14,
  height: 1.4,
);

const EdgeInsets _codePadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 12,
);

/// Register it the same way you already do:
///
/// ```dart
/// kCodeBlockType: CodeBlockComponentBuilder(),
/// ```
///
/// CONFIRMED against current package source (DividerBlockComponentBuilder /
/// ImageBlockComponentBuilder, from AppFlowy-IO/appflowy-editor main):
/// - `configuration` is forwarded via `super.configuration`, not
///   re-declared — the base class already owns that field.
/// - `validate` is a *getter* of type `BlockComponentValidate`
///   (`bool Function(Node)`), not an overridable method — assigning a
///   method with the same name conflicts with the base class's field.
/// - `build` must return `BlockComponentWidget`, matching the base
///   class's abstract signature — a plain `Widget` return type is an
///   invalid override.
class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
      // NOT `node.key` here — that would collide. `node.key` is a
      // GlobalKey tied to the Node itself, and the ParagraphBlockComponent
      // widget we delegate to below ALSO grabs `node.key` for its own
      // widget internally (it's hardcoded to do that, same as every
      // other builder — Divider/Quote/etc.). Since both widgets render
      // from the same underlying `node`, only one of them can hold that
      // key. The inner Paragraph widget is the one the selection/cursor
      // system actually needs to find via `node.key` (it's the real
      // editable text surface), so our own wrapper here gets a distinct
      // key instead.
      key: ValueKey(node),
      node: node,
      configuration: configuration,
      blockComponentContext: blockComponentContext,
    );
  }
}

/// CONFIRMED shape via ImageBlockComponentWidget (current source):
/// `BlockComponentStatefulWidget`'s own constructor exposes `key`,
/// `node`, `showActions`, `actionBuilder`, `actionTrailingBuilder`,
/// `configuration` as forwardable `super.` params. We only need `node`
/// and `configuration` here, plus one extra field of our own
/// (`blockComponentContext`) to delegate rendering to
/// ParagraphBlockComponentBuilder for the actual editable text.
class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    required this.blockComponentContext,
    super.configuration = const BlockComponentConfiguration(),
  });

  final BlockComponentContext blockComponentContext;

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget> {
  Node get node => widget.node;

  // CONFIRMED pattern: appflowy_editor depends on `provider` directly
  // and wraps its tree in `Provider<EditorState>` — every built-in
  // block widget reaches EditorState this way (e.g. the resize handler
  // in ImageBlockComponentWidget's state calls `editorState.transaction`
  // via exactly this kind of lookup).
  EditorState get editorState =>
      Provider.of<EditorState>(context, listen: false);

  void _setLanguage(String language) {
    final transaction =
        editorState.transaction..updateNode(node, {
          ...node.attributes,
          kCodeBlockLanguageKey: language,
        });
    editorState.apply(transaction);
  }

  void _copyAll() {
    final text = node.delta?.toPlainText() ?? '';
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    // Node extends ChangeNotifier and fires on every edit to its delta
    // or attributes (language switch included), so this re-renders the
    // highlighted layer live as the user types — no manual listener
    // wiring needed.
    return AnimatedBuilder(
      animation: node,
      builder: (context, _) {
        final language =
            node.attributes[kCodeBlockLanguageKey] as String? ?? 'plaintext';
        final code = node.delta?.toPlainText() ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF282C34), // matches atomOneDarkTheme bg
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CodeBlockHeader(
                language: language,
                onLanguageChanged: _setLanguage,
                onCopy: _copyAll,
              ),
              Stack(
                children: [
                  // Bottom layer: real syntax highlighting, non-interactive.
                  IgnorePointer(
                    child: Padding(
                      padding: _codePadding,
                      child: HighlightView(
                        // HighlightView chokes on a fully empty string in
                        // some versions — feed it a space when empty so
                        // the block still renders at the right height.
                        code.isEmpty ? ' ' : code,
                        language: language,
                        theme: atomOneDarkTheme,
                        padding: EdgeInsets.zero,
                        textStyle: _codeTextStyle,
                      ),
                    ),
                  ),
                  // Top layer: the actual editable rich text (cursor,
                  // selection, IME all still work normally), painted
                  // transparent so only the highlighted layer shows
                  // through. Reuses the SAME `blockComponentContext` the
                  // outer CodeBlockComponentBuilder was originally handed
                  // — it just describes which node to render, so it's
                  // safe to pass straight through to a different builder.
                  ParagraphBlockComponentBuilder(
                    configuration: BlockComponentConfiguration(
                      padding: (_) => _codePadding,
                      textStyle:
                          (_, {textSpan}) => _codeTextStyle.copyWith(
                            color: Colors.transparent,
                          ),
                    ),
                  ).build(widget.blockComponentContext),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CodeBlockHeader extends StatelessWidget {
  const _CodeBlockHeader({
    required this.language,
    required this.onLanguageChanged,
    required this.onCopy,
  });

  final String language;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF21252B),
        border: Border(bottom: BorderSide(color: Color(0xFF181A1F))),
      ),
      child: Row(
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value:
                  kCodeBlockLanguages.contains(language)
                      ? language
                      : 'plaintext',
              isDense: true,
              dropdownColor: const Color(0xFF21252B),
              icon: const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Colors.white54,
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              items: [
                for (final lang in kCodeBlockLanguages)
                  DropdownMenuItem(value: lang, child: Text(lang)),
              ],
              onChanged: (value) {
                if (value != null) onLanguageChanged(value);
              },
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy, size: 15, color: Colors.white54),
            tooltip: 'Copy code',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
