import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// pagedSlashCommand replaces the stock [customSlashCommand]. The stock
/// [SelectionMenu] positions its overlay with the editor's DOCUMENT-space
/// render box (700 x ~990 under our fitted canonical page space) interpreted
/// as SCREEN pixels: every clamp/flip branch of
/// `SelectionMenu.calculateSelectionMenuOffset` mixes `editorBox.size`
/// (document units) with global caret rects (screen units), and its tap-away
/// barrier is a `SizedBox(width: editorWidth, height: editorHeight)` anchored
/// at the top-left of the screen instead of over the page. Inside
/// PageSurface's FittedBox that throws the menu off the page (or off-screen
/// entirely).
///
/// This service keeps the stock behavior but does all geometry in TRUE screen
/// pixels:
///   * the anchor is `editorState.service.selectionService.selectionRects`,
///     which editor_state already converts to global coordinates through the
///     FittedBox transform (`selectable.transformRectToGlobal`) — so the
///     caret anchor is zoom-correct for free;
///   * the page's on-screen bounds come from `editorState.renderBox` mapped
///     through `localToGlobal` on BOTH corners (sizes do not stay 1:1 under
///     the fitted zoom — same rule as page_surface.dart's overflow math).
///
/// Everything else — keyboard/scroll service suspension, the delete-slash /
/// delete-keyword post-conditions, and the item wiring — mirrors the stock
/// `SelectionMenu` closely, because `SelectionMenuWidget` drives this service
/// only through the [SelectionMenuService] interface (item handlers call
/// `menuService.dismiss()`; nothing else is probed).
Set<String> _defaultSupportSlashMenuNodeTypes() => {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  TodoListBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  QuoteBlockKeys.type,
};

/// '/' → open the page-aware slash menu (see [PagedSelectionMenu]).
CharacterShortcutEvent pagedSlashCommand(
  List<SelectionMenuItem> items, {
  bool shouldInsertSlash = true,
  bool deleteKeywordsByDefault = false,
  bool singleColumn = true,
  SelectionMenuStyle style = SelectionMenuStyle.light,
}) {
  return CharacterShortcutEvent(
    key: 'show the slash menu',
    character: '/',
    handler:
        (editorState) => _showSlashMenu(
          editorState,
          items,
          shouldInsertSlash: shouldInsertSlash,
          deleteKeywordsByDefault: deleteKeywordsByDefault,
          singleColumn: singleColumn,
          style: style,
        ),
  );
}

SelectionMenuService? _selectionMenuService;

/// Whether a paged slash menu overlay is currently open on ANY editor page.
/// The drivers' deferred focus re-request loop (requestEditorFocus) reads this
/// to avoid stealing primary focus back from the menu after it mounts — the
/// retry loop re-arms across several post-frame callbacks, and a retry
/// landing after the menu's own Focus request is what made Enter/direction
/// keys land on the (disabled) editor keyboard service instead of the menu.
bool _menuOpen = false;

bool get isPagedSlashMenuOpen => _menuOpen;

Future<bool> _showSlashMenu(
  EditorState editorState,
  List<SelectionMenuItem> items, {
  bool shouldInsertSlash = true,
  bool singleColumn = true,
  bool deleteKeywordsByDefault = false,
  SelectionMenuStyle style = SelectionMenuStyle.light,
}) async {
  // Desktop-only, same gate as the stock slash command (which uses the
  // package-private PlatformExtension — same semantics, public API here).
  if (Platform.isIOS || Platform.isAndroid) {
    return false;
  }

  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }

  // delete the selection
  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }

  final afterSelection = editorState.selection;
  if (afterSelection == null || !afterSelection.isCollapsed) {
    assert(false, 'the selection should be collapsed');
    return true;
  }

  final node = editorState.getNodeAtPath(selection.start.path);

  // only enable in white-listed node types
  if (node == null ||
      !_isSupportSlashMenuNode(node, _defaultSupportSlashMenuNodeTypes())) {
    return false;
  }

  // insert the slash character
  if (shouldInsertSlash) {
    keepEditorFocusNotifier.increase();
    await editorState.insertTextAtPosition('/', position: selection.start);
  }

  // show the slash menu
  final context = editorState.getNodeAtPath(selection.start.path)?.context;
  if (context != null && context.mounted) {
    _selectionMenuService = PagedSelectionMenu(
      context: context,
      editorState: editorState,
      selectionMenuItems: items,
      deleteSlashByDefault: shouldInsertSlash,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      singleColumn: singleColumn,
      style: style,
    );
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      _selectionMenuService?.show();
    } else {
      await _selectionMenuService?.show();
    }
  }

  if (shouldInsertSlash) {
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) => keepEditorFocusNotifier.decrease(),
    );
  }

  return true;
}

bool _isSupportSlashMenuNode(Node node, Set<String> whiteList) {
  // Check the current node type; walk up so a list item inside a bulleted
  // list child of a page still counts (same semantics as the stock check).
  if (!whiteList.contains(node.type)) {
    return false;
  }
  if (node.level > 1 && node.parent != null) {
    return _isSupportSlashMenuNode(node.parent!, whiteList);
  }
  return true;
}

class PagedSelectionMenu implements SelectionMenuService {
  PagedSelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = true,
    this.deleteKeywordsByDefault = false,
    this.style = SelectionMenuStyle.light,
    this.singleColumn = false,
    this.menuHeight = 300,
    this.menuWidth = 300,
    this.itemCountFilter = 0,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;

  /// Virtual clamp dimensions (screen px), stock SelectionMenu defaults.
  final double menuHeight;
  final double menuWidth;
  final int itemCountFilter;

  @override
  final SelectionMenuStyle style;

  OverlayEntry? _menuEntry;
  bool _selectionUpdateByInner = false;

  // Resolved once per show(), in screen px.
  Rect _caretRect = Rect.zero;
  Rect _editorScreenRect = Rect.zero;
  double? _left;
  double? _top;

  @override
  Offset get offset => Offset(_left ?? 0, _top ?? 0);

  @override
  Alignment get alignment => Alignment.topLeft;

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() => (
    _left,
    _top,
    null,
    null,
  );

  @override
  void dismiss() {
    FocusManager.instance.removeListener(_focusTraceHook);
    _menuOpen = false;
    if (_menuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _menuEntry?.remove();
    _menuEntry = null;

    // workaround: SelectionService may be released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      // focus to reload the selection after the menu dismissed.
      editorState.selection = editorState.selection;
      selectionService.currentSelection.removeListener(_onSelectionChange);
    }
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    dismiss();

    final selectionService = editorState.service.selectionService;
    // GLOBAL (screen) rects — editor_state converts them through the fitted
    // transform before we ever see them.
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }
    _caretRect = selectionRects.first;

    final editorBox = editorState.renderBox;
    if (editorBox == null) {
      return;
    }
    // Both corners: renderBox.size is DOCUMENT units and only becomes screen
    // units through the transform tree.
    _editorScreenRect = Rect.fromPoints(
      editorBox.localToGlobal(Offset.zero),
      editorBox.localToGlobal(editorBox.size.bottomRight(Offset.zero)),
    );

    // Default: below, menu's left edge at the caret's right edge (same
    // convention as the stock menu). Resolved once, in screen px.
    _resolvePosition();

    _menuEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              dismiss();
            },
            child: Stack(
              children: [
                Positioned(
                  left: _left,
                  top: _top,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectionMenuWidget(
                      selectionMenuStyle: style,
                      singleColumn: singleColumn,
                      items:
                          selectionMenuItems..forEach((element) {
                            element.deleteSlash = deleteSlashByDefault;
                            element.deleteKeywords = deleteKeywordsByDefault;
                            element.onSelected = () {
                              dismiss();
                            };
                          }),
                      maxItemInRow: 5,
                      editorState: editorState,
                      itemCountFilter: itemCountFilter,
                      menuService: this,
                      onExit: () {
                        dismiss();
                      },
                      onSelectionUpdate: () {
                        _selectionUpdateByInner = true;
                      },
                      deleteSlashByDefault: deleteSlashByDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);

    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
    selectionService.currentSelection.addListener(_onSelectionChange);

    // [slash-debug] TEMP — full focus-flip trace for the lifetime of the
    // menu: every primary-focus change prints (label). The decisive question:
    // after the menu's own Focus ('popup_list_widget') requests focus, does
    // anything steal it back? If a keystroke arrives while primary focus is
    // the editor focus node, the (disabled) keyboard service eats it.
    FocusManager.instance.addListener(_focusTraceHook);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_menuEntry == null) return;
        final pf = FocusManager.instance.primaryFocus;
        debugPrint(
          '[slash-debug] +2frames primary=(${fmLabel(pf)}) '
          'menuPos=(${_left?.toStringAsFixed(0)},${_top?.toStringAsFixed(0)})',
        );
      });
    });
  }

  // [slash-debug] TEMP
  static String fmLabel(FocusNode? n) {
    final chain = <String>[];
    FocusNode? cur = n;
    while (cur != null && chain.length < 6) {
      chain.add(cur.debugLabel ?? cur.runtimeType.toString());
      cur = cur.parent;
    }
    return chain.join(" <- ");
  }

  // [slash-debug] TEMP
  static void _focusTraceHook() {
    debugPrint(
      '[slash-debug] focus-> ${fmLabel(FocusManager.instance.primaryFocus)}',
    );
  }

  /// Positions the menu below the caret with a 10px gap, then flips to
  /// "above" when the menu would spill past the page's on-screen bottom, and
  /// keeps the menu within the page's horizontal span (caret-left flip first,
  /// clamp second) plus a final safety clamp against the screen bounds.
  void _resolvePosition() {
    const gap = 10.0;

    double left = _caretRect.right;
    double top = _caretRect.bottom + gap;

    // Flip above when the menu's bottom would pass the page's bottom edge:
    // positioned via the stored top-left to keep a single uniform branch.
    if (top + menuHeight >= _editorScreenRect.bottom) {
      top = math.max(0.0, _caretRect.top - gap - menuHeight);
    }

    // Keep the menu within the page's horizontal span: first flip to the
    // caret's left while that still stays inside the page, then clamp.
    final caretRoomOnLeft =
        _caretRect.left - gap - menuWidth >= _editorScreenRect.left;
    if (left + menuWidth > _editorScreenRect.right) {
      left =
          caretRoomOnLeft
              ? _caretRect.left - gap - menuWidth
              : math.max(
                _editorScreenRect.right - menuWidth,
                _editorScreenRect.left,
              );
    }

    // Screen-bounds safety clamp so the menu can never be positioned fully
    // off-screen (the stock menu's missing branch under zoom).
    left = left.clamp(0.0, math.max(0.0, mediaSize().width - menuWidth));
    top = top.clamp(0.0, math.max(0.0, mediaSize().height - menuHeight));

    _left = left;
    _top = top;
    _menuOpen = true;
  }

  Size mediaSize() {
    final view = View.of(context);
    return Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );
  }

  void _onSelectionChange() {
    // workaround: SelectionService may be released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      if (selectionService.currentSelection.value == null) {
        return;
      }
    }

    if (_selectionUpdateByInner) {
      _selectionUpdateByInner = false;
      return;
    }

    dismiss();
  }
}
