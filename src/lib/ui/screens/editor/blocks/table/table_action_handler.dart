import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'table_action_menu.dart';
import 'table_block_component.dart';
import 'table_page_bounds.dart';

class TableActionHandler extends StatefulWidget {
  const TableActionHandler({
    super.key,
    this.visible = false,
    this.height,
    required this.node,
    required this.editorState,
    required this.position,
    required this.alignment,
    required this.transform,
    required this.dir,
    this.menuBuilder,
    this.tableAnchorKey,
  });

  final bool visible;
  final Node node;
  final EditorState editorState;
  final int position;
  final Alignment alignment;
  final Matrix4 transform;
  final double? height;
  final TableDirection dir;
  final GlobalKey? tableAnchorKey;

  final CerebrumTableBlockComponentMenuBuilder? menuBuilder;

  @override
  State<TableActionHandler> createState() => _TableActionHandlerState();
}

class _TableActionHandlerState extends State<TableActionHandler> {
  bool _visible = false;
  bool _menuShown = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: widget.alignment,
      transform: widget.transform,
      height: widget.height,
      child: Visibility(
        visible: (widget.visible || _visible || _menuShown) &&
            widget.editorState.editable,
        child: MouseRegion(
          onEnter: (_) => setState(() => _visible = true),
          onExit: (_) => setState(() => _visible = false),
          child: widget.menuBuilder != null
              ? widget.menuBuilder!(
                  widget.node,
                  widget.editorState,
                  widget.position,
                  widget.dir,
                  () => _menuShown = true,
                  () => setState(() => _menuShown = false),
                )
              : defaultMenuBuilder(
                  context,
                  widget.node,
                  widget.editorState,
                  widget.position,
                  widget.dir,
                  tableAnchorKey: widget.tableAnchorKey,
                ),
        ),
      ),
    );
  }
}

Widget defaultMenuBuilder(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir, {
  GlobalKey? tableAnchorKey,
}) {
  return Card(
    elevation: 3.0,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // Snapshot the page geometry while still inside the page tree —
          // the overlay's context is outside it and can't see PagedTableBounds.
          final pageBounds = snapshotTablePageBounds(
            context,
            tableAnchorKey: tableAnchorKey,
          );
          showActionMenu(
            context,
            node,
            editorState,
            position,
            dir,
            pageBounds: pageBounds,
          );
        },
        child: dir == TableDirection.col
            ? Transform.rotate(
                angle: math.pi / 2,
                child: CerebrumTableDefaults.handlerIcon,
              )
            : CerebrumTableDefaults.handlerIcon,
      ),
    ),
  );
}