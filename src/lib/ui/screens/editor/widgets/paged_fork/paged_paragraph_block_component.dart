// [paged fork] of appflowy_editor 6.0.0
// lib/src/editor/block_component/paragraph_block_component/paragraph_block_component.dart
//
// Differences vs stock: PagedRichText instead of AppFlowyRichText; no local
// ParagraphBlockKeys / AppFlowyRichTextAttributes duplicates (barrel exports
// them and duplicates collide). Everything else is stock. See
// paged_rich_text.dart for the caret-impostor root cause.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_fork/paged_rich_text.dart';

// [paged fork] NOTE: ParagraphBlockKeys is intentionally NOT redeclared here
// (the stock barrel already exports it; a duplicate would collide in every
// file importing both package and fork). This fork changes ONLY the span
// building path, not the block keys.

Node paragraphNode({
  String? text,
  Delta? delta,
  String? textDirection,
  Attributes? attributes,
  Iterable<Node> children = const [],
}) {
  return Node(
    type: ParagraphBlockKeys.type,
    attributes: {
      ParagraphBlockKeys.delta:
          (delta ?? (Delta()..insert(text ?? ''))).toJson(),
      if (attributes != null) ...attributes,
      if (textDirection != null)
        ParagraphBlockKeys.textDirection: textDirection,
    },
    children: children,
  );
}

typedef ShowPlaceholder = bool Function(EditorState editorState, Node node);

class PagedParagraphBlockComponentBuilder extends BlockComponentBuilder {
  PagedParagraphBlockComponentBuilder({
    super.configuration,
    this.showPlaceholder,
  });

  final ShowPlaceholder? showPlaceholder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return PagedParagraphBlockComponentWidget(
      node: node,
      key: node.key,
      configuration: configuration,
      showActions: showActions(node),
      showPlaceholder: showPlaceholder,
      actionBuilder:
          (context, state) => actionBuilder(blockComponentContext, state),
      actionTrailingBuilder:
          (context, state) =>
              actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class PagedParagraphBlockComponentWidget extends BlockComponentStatefulWidget {
  const PagedParagraphBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.showPlaceholder,
  });

  final ShowPlaceholder? showPlaceholder;

  @override
  State<PagedParagraphBlockComponentWidget> createState() =>
      _PagedParagraphBlockComponentWidgetState();
}

class _PagedParagraphBlockComponentWidgetState
    extends State<PagedParagraphBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: ParagraphBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool _showPlaceholder = false;

  @override
  void initState() {
    super.initState();
    editorState.selectionNotifier.addListener(_onSelectionChange);
    _onSelectionChange();
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_onSelectionChange);
    super.dispose();
  }

  void _onSelectionChange() {
    final selection = editorState.selection;

    if (widget.showPlaceholder != null) {
      setState(() {
        _showPlaceholder = widget.showPlaceholder!(editorState, node);
      });
    } else {
      final showPlaceholder =
          selection != null &&
          (selection.isSingle && selection.start.path.equals(node.path));
      if (showPlaceholder != _showPlaceholder) {
        setState(() => _showPlaceholder = showPlaceholder);
      }
    }
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        textDirection: textDirection,
        children: [
          PagedRichText(
            key: forwardKey,
            delegate: this,
            node: widget.node,
            editorState: editorState,
            textAlign: alignment?.toTextAlign ?? textAlign,
            placeholderText: _showPlaceholder ? placeholderText : ' ',
            textSpanDecorator:
                (textSpan) => textSpan.updateTextStyle(
                  textStyleWithTextSpan(textSpan: textSpan),
                ),
            placeholderTextSpanDecorator:
                (textSpan) => textSpan.updateTextStyle(
                  placeholderTextStyleWithTextSpan(textSpan: textSpan),
                ),
            textDirection: textDirection,
            cursorColor: editorState.editorStyle.cursorColor,
            selectionColor: editorState.editorStyle.selectionColor,
            cursorWidth: editorState.editorStyle.cursorWidth,
          ),
        ],
      ),
    );

    child = Container(
      color: withBackgroundColor ? backgroundColor : null,
      child: Padding(key: blockComponentKey, padding: padding, child: child),
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }
}
