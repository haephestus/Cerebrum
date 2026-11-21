import 'package:flutter/widgets.dart';

/// Intents for vim-style keyboard navigation on browse/list surfaces.
///
/// These are **not** editor or reader commands. The editor owns modal
/// editing/navigation via `VimModeController` + `editor_commands.dart`; the
/// reader owns its own paging/search handler. This layer is for shell and
/// content browsing surfaces (sidebars, grids, lists, carousels/regions)
/// composed in with `Shortcuts`/`Actions` + focus scopes.
class NavUpIntent extends Intent {
  const NavUpIntent();
}

class NavDownIntent extends Intent {
  const NavDownIntent();
}

class NavLeftIntent extends Intent {
  const NavLeftIntent();
}

class NavRightIntent extends Intent {
  const NavRightIntent();
}

class NavActivateIntent extends Intent {
  const NavActivateIntent();
}

/// Context-defined: clear selection / blur a field / leave a region / close
/// an in-surface overlay. Never a global "quit".
class NavBackIntent extends Intent {
  const NavBackIntent();
}

/// Request focus for the surface's primary search/filter field, if any.
class NavSearchIntent extends Intent {
  const NavSearchIntent();
}

/// Jump to first item (`gg` sequence, resolved by the scope).
class NavTopIntent extends Intent {
  const NavTopIntent();
}

/// Jump to last item (`G`).
class NavBottomIntent extends Intent {
  const NavBottomIntent();
}
