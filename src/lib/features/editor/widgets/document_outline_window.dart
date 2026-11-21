import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating, section-aware document outline (headings) hosted in
/// [EditorScaffold]'s stack, modelled on `FloatingReaderWindow`'s chrome.
///
/// Read-only for now: lists headings, indents by `level`, jumps on tap,
/// and filters by the search field. Move/insert/delete of nodes is out
/// of scope for this phase — the window only reads `document.root.children`.
class FloatingOutlineWindow extends StatefulWidget {
  final bool visible;
  final VoidCallback onClose;
  final FocusNode? outlineFocusNode;
  final VoidCallback? onReleaseFocus;

  /// Current headings, rebuilt by the host on every transaction.
  /// Each entry is (nodeId, level 1..6, title, index).
  final List<OutlineHeading> headings;
  final void Function(String nodeId) onJump;
  final void Function(String nodeId, int matchOffset)? onJumpWithOffset;

  /// All top-level blocks for note search. When empty the search falls
  /// back to headings-only; otherwise `/` searches every block's text.
  final List<OutlineBlock> allBlocks;

  /// Host-owned focus node for the search field (so the scaffold can
  /// put us into `/`-search mode from the editor).
  final FocusNode? searchFocusNode;

  /// Bump to request that the search field take focus (outline `/`).
  final ValueNotifier<int>? searchFocusTick;

  const FloatingOutlineWindow({
    super.key,
    required this.visible,
    required this.onClose,
    required this.headings,
    required this.onJump,
    this.onJumpWithOffset,
    this.allBlocks = const [],
    this.searchFocusNode,
    this.searchFocusTick,
    this.outlineFocusNode,
    this.onReleaseFocus,
  });

  @override
  State<FloatingOutlineWindow> createState() => _FloatingOutlineWindowState();
}

class OutlineHeading {
  final String nodeId;
  final int index;
  final int level;
  final String title;
  const OutlineHeading({
    required this.nodeId,
    required this.index,
    required this.level,
    required this.title,
  });
}

/// One top-level block for note search: plain text + where a query hit.
class OutlineBlock {
  final String nodeId;
  final int index;
  final String type;
  final String text;
  const OutlineBlock({
    required this.nodeId,
    required this.index,
    required this.type,
    required this.text,
  });
}

/// One row in the outline list: headings (indent = level-1) or, while
/// searching, any block with a text hit (indent = 0, type shown).
typedef _OutlineRow =
    ({String nodeId, int matchOffset, bool isHeading, int level});

class _OutlineHeadingRow {
  final String nodeId;
  final int level;
  final String title;
  final int matchOffset;
  const _OutlineHeadingRow({
    required this.nodeId,
    required this.level,
    required this.title,
    required this.matchOffset,
  });
}

class _FloatingOutlineWindowState extends State<FloatingOutlineWindow> {
  static const _minSize = Size(280, 320);
  static const _titleBarHeight = 40.0;
  static const _edge = 8.0;
  static const _margin = 12.0;

  Size _frac = const Size(0.28, 0.75);
  Offset? _posFrac;
  bool _maximized = false;
  bool _collapsed = false;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  int _sel = 0;
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text));
    widget.searchFocusTick?.addListener(_onSearchFocusTick);
  }

  void _onSearchFocusTick() {
    final tick = widget.searchFocusTick?.value ?? 0;
    if (tick == _lastTick) return;
    _lastTick = tick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.searchFocusNode?.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant FloatingOutlineWindow old) {
    super.didUpdateWidget(old);
    if (widget.searchFocusTick != old.searchFocusTick) {
      old.searchFocusTick?.removeListener(_onSearchFocusTick);
      _lastTick = widget.searchFocusTick?.value ?? 0;
      widget.searchFocusTick?.addListener(_onSearchFocusTick);
    }
    if (widget.headings != old.headings || widget.allBlocks != old.allBlocks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final len = _rows.length;
        if (_sel >= len) setState(() => _sel = len == 0 ? 0 : len - 1);
      });
    }
  }

  @override
  void dispose() {
    widget.searchFocusTick?.removeListener(_onSearchFocusTick);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_OutlineHeadingRow> get _filtered => _headingRows(widget.headings);

  List<_OutlineHeadingRow> _headingRows(List<OutlineHeading> headings) {
    final q = _query.trim().toLowerCase();
    return headings
        .where((h) => q.isEmpty || h.title.toLowerCase().contains(q))
        .map(
          (h) => _OutlineHeadingRow(
            nodeId: h.nodeId,
            level: h.level,
            title: h.title,
            matchOffset: 0,
          ),
        )
        .toList();
  }

  /// Search scope: without a query → headings; with a query → every
  /// block in the note whose text contains it (note search, `/`).
  List<_OutlineRow> get _rows {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.headings
          .map(
            (h) => (
              nodeId: h.nodeId,
              matchOffset: 0,
              isHeading: true,
              level: h.level,
            ),
          )
          .toList();
    }
    final blocks =
        widget.allBlocks.isEmpty
            ? null
            : widget.allBlocks
                .where((b) => b.text.toLowerCase().contains(q))
                .map<_OutlineRow>(
                  (b) => (
                    nodeId: b.nodeId,
                    matchOffset: b.text.toLowerCase().indexOf(q),
                    isHeading: b.type == HeadingBlockKeys.type,
                    level: 1,
                  ),
                )
                .toList();
    if (blocks != null) return blocks;
    return _filtered
        .map<_OutlineRow>(
          (r) => (
            nodeId: r.nodeId,
            matchOffset: 0,
            isHeading: true,
            level: r.level,
          ),
        )
        .toList();
  }

  void _moveSel(int delta) {
    final len = _rows.length;
    if (len == 0) return;
    setState(() => _sel = (_sel + delta).clamp(0, len - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        (_sel * 40.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _activate() {
    final rows = _rows;
    if (rows.isEmpty || _sel < 0 || _sel >= rows.length) return;
    if (widget.onJumpWithOffset != null) {
      widget.onJumpWithOffset!(rows[_sel].nodeId, rows[_sel].matchOffset);
    } else {
      widget.onJump(rows[_sel].nodeId);
    }
  }

  KeyEventResult _onOutlineKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    if (hk.isAltPressed || hk.isMetaPressed) return KeyEventResult.ignored;
    final shift = hk.isShiftPressed;
    final key = event.logicalKey;
    const handled = KeyEventResult.handled;
    // '/' focuses the search field (vim buffer search).
    if (key == LogicalKeyboardKey.slash && !shift) {
      widget.searchFocusNode?.requestFocus();
      return handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (FocusManager.instance.primaryFocus?.context?.widget is EditableText ||
          FocusManager.instance.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<EditableText>() !=
              null) {
        // In the search field: return to the list, don't leave the sheet.
        widget.outlineFocusNode?.requestFocus();
        return handled;
      }
      widget.onReleaseFocus?.call();
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        (!shift && key == LogicalKeyboardKey.keyJ)) {
      _moveSel(1);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        (!shift && key == LogicalKeyboardKey.keyK)) {
      _moveSel(-1);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        (!shift && key == LogicalKeyboardKey.keyL)) {
      // No indented children to spill into — swallow. (Kept so h/l don't
      // leak to the editor behind the outline.)
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        (!shift && key == LogicalKeyboardKey.keyH)) {
      return handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _activate();
      return handled;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.keyG) {
      if (key == LogicalKeyboardKey.home || shift) {
        _sel = 0;
        setState(() {});
      }
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      final len = _rows.length;
      if (len > 0) setState(() => _sel = len - 1);
      return handled;
    }
    // Anything else (s = toggle in scaffold, typing in search) falls
    // through to the focused field / scaffold global handler.
    return KeyEventResult.ignored;
  }

  Rect _resolveRect(Size screen, Size bounds) {
    if (_maximized) {
      return Rect.fromLTWH(
        _margin,
        _margin,
        math.max(_minSize.width, bounds.width - _margin * 2),
        math.max(_minSize.height, bounds.height - _margin * 2),
      );
    }
    final maxW = math.max(_minSize.width, bounds.width);
    final maxH = math.max(_minSize.height, bounds.height);
    final w =
        (screen.width * _frac.width).clamp(_minSize.width, maxW).toDouble();
    final h =
        (screen.height * _frac.height).clamp(_minSize.height, maxH).toDouble();
    final rawLeft = _posFrac == null ? _margin : _posFrac!.dx * screen.width;
    final rawTop = _posFrac == null ? _margin : _posFrac!.dy * screen.height;
    final left = rawLeft.clamp(0.0, math.max(0.0, bounds.width - w)).toDouble();
    final top =
        rawTop
            .clamp(0.0, math.max(0.0, bounds.height - _titleBarHeight))
            .toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  void _commit(Rect r, Size screen) {
    setState(() {
      _frac = Size(r.width / screen.width, r.height / screen.height);
      _posFrac = Offset(r.left / screen.width, r.top / screen.height);
    });
  }

  void _move(Rect r, Size screen, Offset d) {
    if (_maximized) return;
    _commit(r.shift(d), screen);
  }

  void _resize(
    Rect r,
    Size screen, {
    double left = 0,
    double right = 0,
    double bottom = 0,
  }) {
    if (_maximized) return;
    var l = r.left, w = r.width, h = r.height;
    if (left != 0) {
      final nw = w - left;
      if (nw >= _minSize.width) {
        l += left;
        w = nw;
      }
    }
    if (right != 0) w = math.max(_minSize.width, w + right);
    if (bottom != 0) h = math.max(_minSize.height, h + bottom);
    _commit(Rect.fromLTWH(l, r.top, w, h), screen);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Visibility(
        visible: widget.visible,
        maintainState: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rect = _resolveRect(screen, constraints.biggest);
            final height = _collapsed ? _titleBarHeight : rect.height;
            return Stack(
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: height,
                  child: RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        if (widget.outlineFocusNode != null)
                          widget.outlineFocusNode!,
                      ]),
                      builder:
                          (context, _) => Material(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color:
                                    (widget.outlineFocusNode?.hasFocus ?? false)
                                        ? scheme.primary
                                        : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            color: scheme.surface,
                            child: Column(
                              children: [
                                _titleBar(scheme, rect, screen),
                                Expanded(
                                  child: Offstage(
                                    offstage: _collapsed,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Focus(
                                            focusNode: widget.outlineFocusNode,
                                            onKeyEvent: _onOutlineKey,
                                            child: Listener(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onPointerDown: (_) {
                                                final n =
                                                    widget.outlineFocusNode;
                                                if (n != null && !n.hasFocus)
                                                  n.requestFocus();
                                              },
                                              child: _body(),
                                            ),
                                          ),
                                        ),
                                        if (!_maximized)
                                          ..._resizeHandles(rect, screen),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body() {
    final rows = _rows;
    final searching = _query.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _search,
            focusNode: widget.searchFocusNode,
            onChanged:
                (v) => setState(() {
                  _query = v;
                  _sel = 0;
                }),
            onSubmitted: (_) => _activate(),
            decoration: const InputDecoration(
              hintText: 'Search headings / all blocks… ( / )',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child:
              rows.isEmpty
                  ? Center(
                    child: Text(
                      widget.headings.isEmpty && widget.allBlocks.isEmpty
                          ? 'No headings yet.\nAdd H1 / H2 blocks with /heading.'
                          : 'No matches for "$_query".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                  : ListView.builder(
                    controller: _scroll,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final isSel = i == _sel;
                      final heading =
                          widget.headings
                              .where((h) => h.nodeId == r.nodeId)
                              .firstOrNull;
                      final block =
                          widget.allBlocks
                              .where((b) => b.nodeId == r.nodeId)
                              .firstOrNull;
                      final title = heading?.title ?? block?.text ?? r.nodeId;
                      final indent =
                          searching ? 0.0 : (r.level - 1).clamp(0, 5) * 16.0;
                      final leading =
                          searching
                              ? (r.isHeading
                                  ? Text(
                                    'H${heading?.level ?? r.level}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  )
                                  : Text(
                                    block?.type ?? r.isHeading.toString(),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                    ),
                                  ))
                              : Text(
                                'H${heading?.level ?? r.level}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              );
                      return ListTile(
                        key: ValueKey('outline-${r.nodeId}-$i'),
                        dense: true,
                        selected: isSel,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.18),
                        contentPadding: EdgeInsets.only(
                          left: 12 + indent,
                          right: 12,
                        ),
                        leading: leading,
                        title: Text(
                          title.isEmpty ? 'Untitled' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          setState(() => _sel = i);
                          if (widget.onJumpWithOffset != null) {
                            widget.onJumpWithOffset!(r.nodeId, r.matchOffset);
                          } else {
                            widget.onJump(r.nodeId);
                          }
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }

  List<Widget> _resizeHandles(Rect rect, Size screen) {
    Widget handle({
      required MouseCursor cursor,
      required void Function(Offset d) onDelta,
      double? left,
      double? right,
      double? top,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onDelta(d.delta),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    return [
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, left: d.dx),
      ),
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, right: d.dx),
      ),
      handle(
        cursor: SystemMouseCursors.resizeUpDown,
        left: _edge * 2,
        right: _edge * 2,
        bottom: 0,
        height: _edge,
        onDelta: (d) => _resize(rect, screen, bottom: d.dy),
      ),
      handle(
        cursor: SystemMouseCursors.resizeDownLeft,
        left: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        onDelta: (d) => _resize(rect, screen, left: d.dx, bottom: d.dy),
      ),
      handle(
        cursor: SystemMouseCursors.resizeDownRight,
        right: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        onDelta: (d) => _resize(rect, screen, right: d.dx, bottom: d.dy),
      ),
    ];
  }

  Widget _titleBar(ColorScheme scheme, Rect rect, Size screen) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => _move(rect, screen, d.delta),
      onDoubleTap: () => setState(() => _maximized = !_maximized),
      child: MouseRegion(
        cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.move,
        child: Container(
          height: _titleBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.list_alt, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Document outline',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _maximized ? 'Restore size' : 'Maximize',
                icon: Icon(
                  _maximized ? Icons.close_fullscreen : Icons.open_in_full,
                  size: 18,
                ),
                onPressed: () => setState(() => _maximized = !_maximized),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _collapsed ? 'Expand' : 'Collapse',
                icon: Icon(
                  _collapsed ? Icons.unfold_more : Icons.unfold_less,
                  size: 18,
                ),
                onPressed: () => setState(() => _collapsed = !_collapsed),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Close (Esc)',
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Extract section-aware headings from an AppFlowy document root.
/// Pure helper so it can be headless-tested without widgets.
List<OutlineHeading> headingsFromRoot(Node root) {
  final out = <OutlineHeading>[];
  for (var i = 0; i < root.children.length; i++) {
    final node = root.children[i];
    if (node.type != HeadingBlockKeys.type) continue;
    final level =
        (node.attributes[HeadingBlockKeys.level] as num?)?.toInt() ?? 1;
    final title = node.delta?.toPlainText().trim() ?? '';
    out.add(
      OutlineHeading(
        nodeId: node.id,
        index: i,
        level: level.clamp(1, 6),
        title: title,
      ),
    );
  }
  return out;
}

/// All top-level blocks for note search, same pure-helper style.
List<OutlineBlock> allBlocksFromRoot(Node root) {
  final out = <OutlineBlock>[];
  for (var i = 0; i < root.children.length; i++) {
    final node = root.children[i];
    final text = node.delta?.toPlainText().trim() ?? '';
    out.add(
      OutlineBlock(nodeId: node.id, index: i, type: node.type, text: text),
    );
  }
  return out;
}
