import 'dart:math' as math;

import 'package:cerebrum/ui/screens/readings/reader.dart';
import 'package:flutter/material.dart';

/// A draggable, resizable window that hosts [Reader] on top of the editor.
///
/// Must be a DIRECT child of a [Stack] (it returns a Positioned.fill).
///
/// SIZING: the window's size and position are stored as FRACTIONS of
/// `MediaQuery.sizeOf(context)`, so it scales with the app window / screen
/// instead of staying a fixed 520x680. A bigger window = a bigger, more
/// readable PDF (pdfrx fits pages to the viewer width).
///
/// State persistence: when [visible] is false the window stays in the tree
/// (Visibility.maintainState), and collapsing uses Offstage, so the Reader keeps
/// its page, zoom, search and annotation state. Changing [fileFingerprint]
/// swaps the Reader (keyed on the fingerprint).
///
/// Pointer behaviour: the area around the window paints nothing and has no hit
/// target, so taps outside the window rect fall through to the editor.
class FloatingReaderWindow extends StatefulWidget {
  final String fileFingerprint;
  final int? page;
  final bool visible;
  final VoidCallback onClose;
  final VoidCallback onChangeFile;

  /// Focus node of the Reader's vim keys. The host (editor scaffold) keeps it so
  /// `r` / Ctrl+w can move focus here; clicking in the window also takes it.
  final FocusNode? readerFocusNode;

  /// Esc in the idle Reader: the host should hand focus back to the editor.
  final VoidCallback? onReleaseFocus;

  const FloatingReaderWindow({
    super.key,
    required this.fileFingerprint,
    required this.visible,
    required this.onClose,
    required this.onChangeFile,
    this.page,
    this.readerFocusNode,
    this.onReleaseFocus,
  });

  @override
  State<FloatingReaderWindow> createState() => _FloatingReaderWindowState();
}

class _FloatingReaderWindowState extends State<FloatingReaderWindow> {
  static const _minSize = Size(360, 320);
  static const _titleBarHeight = 40.0;
  static const _edge = 8.0; // resize grab strip thickness
  static const _margin = 12.0;

  // Size as a fraction of the screen. Default: ~half the width, ~90% height.
  Size _frac = const Size(0.5, 0.9);
  // Top-left as a fraction of the screen; null = default (docked to the right).
  Offset? _posFrac;
  bool _maximized = false;
  bool _collapsed = false;

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

    final rawLeft =
        _posFrac == null
            ? bounds.width - w - _margin
            : _posFrac!.dx * screen.width;
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

  void _toggleMaximized() => setState(() => _maximized = !_maximized);

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
                    // Rebuilds when the Reader gains/loses keyboard focus so the
                    // window shows which pane the vim keys are going to.
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        if (widget.readerFocusNode != null)
                          widget.readerFocusNode!,
                      ]),
                      builder:
                          (context, _) => Material(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color:
                                    (widget.readerFocusNode?.hasFocus ?? false)
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
                                // Offstage (not `if`) so collapsing keeps the
                                // Reader's State alive: page, zoom, search, ink.
                                Expanded(
                                  child: Offstage(
                                    offstage: _collapsed,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: ClipRect(
                                            // A click anywhere in the window gives the
                                            // Reader keyboard focus (unless a field in
                                            // it, e.g. search, already has it).
                                            child: Listener(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onPointerDown: (_) {
                                                final n =
                                                    widget.readerFocusNode;
                                                if (n != null && !n.hasFocus) {
                                                  n.requestFocus();
                                                }
                                              },
                                              child: Reader(
                                                key: ValueKey(
                                                  widget.fileFingerprint,
                                                ),
                                                fileFingerprint:
                                                    widget.fileFingerprint,
                                                page: widget.page,
                                                focusNode:
                                                    widget.readerFocusNode,
                                                onReleaseFocus:
                                                    widget.onReleaseFocus,
                                              ),
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

  // Edge + corner grab areas inside the content region.
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
      Widget? grip,
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
            // Opaque so the handle claims the drag instead of the PDF viewer
            // underneath scrolling/panning with it.
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onDelta(d.delta),
            child: grip ?? const SizedBox.expand(),
          ),
        ),
      );
    }

    final gripColor = Theme.of(context).colorScheme.outline;
    Widget cornerGrip(IconData icon, Alignment a) => Align(
      alignment: a,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 16, color: gripColor),
      ),
    );

    return [
      // Left edge
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, left: d.dx),
      ),
      // Right edge
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, right: d.dx),
      ),
      // Bottom edge
      handle(
        cursor: SystemMouseCursors.resizeUpDown,
        left: _edge * 2,
        right: _edge * 2,
        bottom: 0,
        height: _edge,
        onDelta: (d) => _resize(rect, screen, bottom: d.dy),
      ),
      // Bottom-left corner
      handle(
        cursor: SystemMouseCursors.resizeDownLeft,
        left: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        grip: cornerGrip(Icons.south_west, Alignment.bottomLeft),
        onDelta: (d) => _resize(rect, screen, left: d.dx, bottom: d.dy),
      ),
      // Bottom-right corner
      handle(
        cursor: SystemMouseCursors.resizeDownRight,
        right: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        grip: cornerGrip(Icons.south_east, Alignment.bottomRight),
        onDelta: (d) => _resize(rect, screen, right: d.dx, bottom: d.dy),
      ),
    ];
  }

  Widget _titleBar(ColorScheme scheme, Rect rect, Size screen) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => _move(rect, screen, d.delta),
      onDoubleTap: _toggleMaximized,
      child: MouseRegion(
        cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.move,
        child: Container(
          height: _titleBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.menu_book, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reader',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Open a different document',
                icon: const Icon(Icons.swap_horiz, size: 18),
                onPressed: widget.onChangeFile,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _maximized ? 'Restore size' : 'Maximize',
                icon: Icon(
                  _maximized ? Icons.close_fullscreen : Icons.open_in_full,
                  size: 18,
                ),
                onPressed: _toggleMaximized,
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
                tooltip: 'Close (keeps your place)',
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
