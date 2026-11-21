import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'nav_intents.dart';

typedef NavIntentCallback = void Function();

/// Default vim-style key bindings for browse/navigation surfaces.
///
/// Primary bindings follow the standard set (`hjkl`, `gg`/`G`, `/`, `Enter`,
/// `Esc`). Arrow keys are NOT included by default to avoid conflicts on
/// surfaces that already give arrows specific meaning (e.g. carousels,
/// reader/editor-owned regions); opt in per-surface by merging your own
/// shortcuts ahead of these.
Map<ShortcutActivator, Intent> defaultVimNavShortcuts({
  bool includeArrows = false,
}) {
  final map = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyH): const NavLeftIntent(),
    const SingleActivator(LogicalKeyboardKey.keyJ): const NavDownIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK): const NavUpIntent(),
    const SingleActivator(LogicalKeyboardKey.keyL): const NavRightIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const NavActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const NavBackIntent(),
    const SingleActivator(LogicalKeyboardKey.slash): const NavSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.keyG, shift: true):
        const NavBottomIntent(),
  };
  if (includeArrows) {
    map[const SingleActivator(LogicalKeyboardKey.arrowLeft)] =
        const NavLeftIntent();
    map[const SingleActivator(LogicalKeyboardKey.arrowDown)] =
        const NavDownIntent();
    map[const SingleActivator(LogicalKeyboardKey.arrowUp)] =
        const NavUpIntent();
    map[const SingleActivator(LogicalKeyboardKey.arrowRight)] =
        const NavRightIntent();
  }
  return map;
}

/// Installs vim-style navigation [Shortcuts]/[Actions] for a browse surface.
///
/// Responsibilities:
/// - maps keys -> nav intents -> caller callbacks (composition; no base class),
/// - resolves the `gg` sequence (top) with a timeout, since [Shortcuts] is
///   single-stroke,
/// - refuses to consume keys when an editable text field owns focus, so typing
///   `j`, `/`, etc. in search inputs works normally,
/// - can be nested/disabled; when disabled or not handling, events fall
///   through to outer scopes or normal focus traversal.
///
/// This scope must NOT wrap the editor or reader surfaces — they own their own
/// vim/key handling.
class KeyboardNavScope extends StatefulWidget {
  const KeyboardNavScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.shortcuts,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onActivate,
    this.onBack,
    this.onSearch,
    this.onTop,
    this.onBottom,
  });

  final Widget child;

  /// Master enable. When false, no keys are handled here.
  final bool enabled;

  /// Request focus for this nav region on first build.
  final bool autofocus;

  /// Focus node for this region. Provide one to control/observe region focus
  /// from the page (e.g. shell rail vs page content).
  final FocusNode? focusNode;

  /// Override/extend the default shortcuts. When null, [defaultVimNavShortcuts]
  /// is used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  final NavIntentCallback? onUp;
  final NavIntentCallback? onDown;
  final NavIntentCallback? onLeft;
  final NavIntentCallback? onRight;
  final NavIntentCallback? onActivate;
  final NavIntentCallback? onBack;
  final NavIntentCallback? onSearch;
  final NavIntentCallback? onTop;
  final NavIntentCallback? onBottom;

  @override
  State<KeyboardNavScope> createState() => _KeyboardNavScopeState();
}

class _KeyboardNavScopeState extends State<KeyboardNavScope> {
  DateTime? _pendingGAt;

  static const _sequenceTimeout = Duration(milliseconds: 600);

  bool get _hasEditablePrimaryFocus {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    // EditableText is the focusable core of TextField/CupertinoTextField and
    // the editor's own text inputs. If it (or a descendant context owned by
    // one) has focus, navigation keys must type, not move selection.
    if (ctx.widget is EditableText) return true;
    var editable = false;
    ctx.visitAncestorElements((el) {
      if (el.widget is EditableText) {
        editable = true;
        return false;
      }
      return true;
    });
    return editable;
  }

  /// Whether this scope may handle a nav intent right now.
  bool get _canHandle =>
      widget.enabled &&
      !_hasEditablePrimaryFocus &&
      (widget.focusNode?.hasFocus ?? true);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || _hasEditablePrimaryFocus) {
      _pendingGAt = null;
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final now = DateTime.now();

    // `gg` -> top. Tracked here (not in Shortcuts) because Shortcuts has no
    // multi-stroke sequence concept.
    if (key == LogicalKeyboardKey.keyG &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (_pendingGAt != null &&
          now.difference(_pendingGAt!) <= _sequenceTimeout) {
        _pendingGAt = null;
        if (widget.onTop != null) {
          widget.onTop!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      _pendingGAt = now;
      // Swallow the first `g` so it doesn't type anywhere unexpected in a
      // nav context; the sequence either completes or times out harmlessly.
      return KeyEventResult.handled;
    }

    // Any other key breaks a pending `g`.
    _pendingGAt = null;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = widget.shortcuts ?? defaultVimNavShortcuts();

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          NavUpIntent: CallbackAction<NavUpIntent>(
            onInvoke: (_) => _canHandle ? widget.onUp?.call() : null,
          ),
          NavDownIntent: CallbackAction<NavDownIntent>(
            onInvoke: (_) => _canHandle ? widget.onDown?.call() : null,
          ),
          NavLeftIntent: CallbackAction<NavLeftIntent>(
            onInvoke: (_) => _canHandle ? widget.onLeft?.call() : null,
          ),
          NavRightIntent: CallbackAction<NavRightIntent>(
            onInvoke: (_) => _canHandle ? widget.onRight?.call() : null,
          ),
          NavActivateIntent: CallbackAction<NavActivateIntent>(
            onInvoke: (_) => _canHandle ? widget.onActivate?.call() : null,
          ),
          NavBackIntent: CallbackAction<NavBackIntent>(
            onInvoke: (_) => _canHandle ? widget.onBack?.call() : null,
          ),
          NavSearchIntent: CallbackAction<NavSearchIntent>(
            onInvoke: (_) => _canHandle ? widget.onSearch?.call() : null,
          ),
          NavTopIntent: CallbackAction<NavTopIntent>(
            onInvoke: (_) => _canHandle ? widget.onTop?.call() : null,
          ),
          NavBottomIntent: CallbackAction<NavBottomIntent>(
            onInvoke: (_) => _canHandle ? widget.onBottom?.call() : null,
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: widget.enabled,
          skipTraversal: !widget.enabled,
          onKeyEvent: _handleKey,
          child: widget.child,
        ),
      ),
    );
  }
}
