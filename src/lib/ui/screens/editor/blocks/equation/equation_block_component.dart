import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';

// Dependency added to pubspec.yaml:
//   flutter_math_fork: ^0.7.2
// (pinned in pub-cache as 0.7.4; pulls only deps already resolved —
// provider, collection, tuple, flutter_svg.)

/// Node type string for the TeX equation block, and the attribute key it
/// stores its raw LaTeX source under. Unlike text blocks this node has
/// NO delta attribute — the entire block is one rendered formula, like
/// AppFlowy's divider/image blocks (non-selectable containers).
const String kEquationBlockType = 'equation_block';
const String kEquationBlockLatexKey = 'latex';

/// Default source shown when the dialog opens without prior content.
const String kEquationDefaultSource = r'\frac{a}{b} + c^2';

/// Builds an equation_block Node. Kept as a named constructor (like
/// `codeBlockNode`) so every creation site carries the attribute shape
/// — a bare `Node(type: kEquationBlockType)` missing `latex` would render
/// the empty-formula fallback.
Node equationBlockNode({String latex = kEquationDefaultSource}) {
  return Node(
    type: kEquationBlockType,
    attributes: {kEquationBlockLatexKey: latex},
  );
}

/// Throws the parse error visibly instead of swallowing it: a malformed
/// formula should show the raw source plus the reason, not blank space
/// the user then mistakes for "the app ate my equation".
Widget _equationErrorFallback(FlutterMathException error) {
  return Text.rich(
    TextSpan(
      children: [
        const WidgetSpan(child: Icon(Icons.warning_amber_rounded, size: 14)),
        const TextSpan(text: ' invalid LaTeX: '),
        TextSpan(
          text: error.message,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

// NOTE: not const-constructible — BlockComponentBuilder has mutable
// fields (validate defaults to (_) => true; leave that for this block,
// it has no delta to validate).
class EquationBlockComponentBuilder extends BlockComponentBuilder {
  EquationBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return EquationBlockComponentWidget(
      // node.key (GlobalKey) is fine here — unlike the code block, this
      // widget renders no inner ParagraphBlock, so nothing is contending
      // for that key. Same non-text-block pattern as Divider/Image.
      key: node.key,
      node: node,
      configuration: configuration,
      blockComponentContext: blockComponentContext,
    );
  }
}

class EquationBlockComponentWidget extends BlockComponentStatefulWidget {
  const EquationBlockComponentWidget({
    super.key,
    required super.node,
    required this.blockComponentContext,
    super.configuration = const BlockComponentConfiguration(),
  });

  /// Passed through for parity with the other block widgets (the context
  /// carries the builder that owns this node); not read directly today,
  /// but every non-text block in AppFlowy forwards it and a future
  /// extension of this block may want it.
  final BlockComponentContext blockComponentContext;

  @override
  State<EquationBlockComponentWidget> createState() =>
      _EquationBlockComponentWidgetState();
}

class _EquationBlockComponentWidgetState
    extends State<EquationBlockComponentWidget> {
  Node get node => widget.node;

  EditorState get editorState =>
      Provider.of<EditorState>(context, listen: false);

  String get latex => node.attributes[kEquationBlockLatexKey] as String? ?? '';

  void _updateLatex(String latex) {
    final transaction =
        editorState.transaction..updateNode(node, {
          ...node.attributes,
          kEquationBlockLatexKey: latex,
        });
    editorState.apply(transaction);
  }

  /// Edit: reopen the same dialog used at creation (the driver's slash-menu
  /// handler owns the dialog builder, but the block itself needs to be able
  /// to amend its source later — so the dialog lives in this file and the
  /// slash menu item calls into it, keeping a single implementation).
  Future<void> _edit() async {
    final next = await showEquationDialog(context, initial: latex);
    if (next != null && next.isNotEmpty && next != latex && mounted) {
      _updateLatex(next);
    }
  }

  void _delete() {
    // Capture the caret-restoration index BEFORE the delete: after
    // deleteNode the removed node's path is stale and AppFlowy leaves the
    // selection null (the same trap the 'dd' handler documents in
    // editor_commands.dart).
    final path = node.path;
    final deletedIndex = path.isNotEmpty ? path.first : path.last;

    final transaction = editorState.transaction..deleteNode(node);
    editorState.apply(transaction);

    if (editorState.selection == null &&
        editorState.document.root.children.isNotEmpty) {
      final i = deletedIndex.clamp(
        0,
        editorState.document.root.children.length - 1,
      );
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: [i], offset: 0)),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  void _copySource() {
    Clipboard.setData(ClipboardData(text: latex));
  }

  @override
  Widget build(BuildContext context) {
    // Node fires on attribute changes (latex edits), re-rendering live.
    return AnimatedBuilder(
      animation: node,
      builder: (context, _) {
        final source = latex;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.cerebrum.surface.sunken,
            border: Border.all(color: context.cerebrum.surface.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EquationHeader(
                onEdit: _edit,
                onCopy: _copySource,
                onDelete: _delete,
              ),
              // Empty-ish source still renders (Math.tex of '' produces a
              // blank line of the right height) — no special case needed.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child:
                    source.isEmpty
                        ? const Text(
                          'Equation is blank — edit?',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        )
                        : Center(
                          child: Math.tex(
                            source,
                            mathStyle: MathStyle.display,
                            textStyle:
                                Theme.of(
                                  context,
                                ).textTheme.bodyMedium, // inherits app fonts
                            onErrorFallback: _equationErrorFallback,
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EquationHeader extends StatelessWidget {
  const _EquationHeader({
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final iconColor = context.cerebrum.text.onDarkIcon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.cerebrum.surface.outline),
        ),
      ),
      child: Row(
        children: [
          Text(
            'LaTeX',
            style: TextStyle(fontSize: 11, color: iconColor.withAlpha(140)),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 15, color: iconColor),
            tooltip: 'Edit formula',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.copy, size: 15, color: iconColor),
            tooltip: 'Copy LaTeX source',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 15,
              color: context.cerebrum.text.muted,
            ),
            tooltip: 'Delete equation',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// The LaTeX-entry dialog. Exposed as a top-level function because both
/// entry points need it: the driver's "/equation" slash-menu item (spawn a
/// NEW block) and the block header's edit button (amend an existing one).
/// Returns the submitted source, or null when the user dismissed.
Future<String?> showEquationDialog(
  BuildContext context, {
  String initial = kEquationDefaultSource,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('LaTeX formula'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: r'\frac{a}{b} + c^2',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => Navigator.of(context).pop(v),
                ),
                const SizedBox(height: 12),
                // Live preview. A bare Math.tex here would render ONCE against
                // the initial text and never again — the dialog must listen to
                // the controller. Dumped formulas render the package's own
                // onErrorFallback (visible warning + reason).
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder:
                      (context, value, _) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Math.tex(
                            value.text,
                            mathStyle: MathStyle.text,
                            textStyle: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Insert'),
            ),
          ],
        ),
  );
}
