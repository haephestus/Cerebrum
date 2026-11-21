import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/features/home/d_homescreen_page.dart';
import 'package:cerebrum/features/file_library/file_library.dart';
import 'package:cerebrum/features/learning_center/d_learning_center_page.dart';
import 'package:cerebrum/features/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/common/widgets/shell/sidebar_button.dart';
import 'package:cerebrum/common/keyboard_nav/keyboard_nav.dart';
import 'package:cerebrum/features/study_bubble/d_study_bubble_page.dart';
import 'package:cerebrum/features/study_bubble/d_study_bubble_home.dart';
import 'package:cerebrum/services/user_session.dart';

class DesktopUI extends StatefulWidget {
  const DesktopUI({super.key});

  @override
  State<DesktopUI> createState() => _DesktopUIState();
}

class _DesktopUIState extends State<DesktopUI> {
  int selectedPage = 0;
  Map<String, dynamic>? payload;
  String? _userId;

  /// When true, the sidebar stays fully expanded regardless of hover.
  bool _pinned = false;

  /// Whether the mouse is currently hovering the sidebar area.
  bool _hovering = false;

  /// The sidebar is expanded if it's pinned OR the user is hovering.
  bool get _sidebarOpen => _pinned || _hovering;

  /// Keyboard focus for the shell rail (vim-style browse nav, step 2 of the
  /// shared keyboard-nav layer). Indices map to rail destinations in visual
  /// order: 0 Home, 1 Study Bubbles, 2 Learning Center, 3 File Library,
  /// 4 Settings.
  final LinearNavController _railNav = LinearNavController(itemCount: 5);
  final FocusNode _railFocusNode = FocusNode(debugLabel: 'desktop-rail-nav');

  /// Entry focus nodes for content pages (rail `l` focuses the active page).
  final FocusNode _homeFocus = FocusNode(debugLabel: 'page-home-nav');
  final FocusNode _bubblesFocus = FocusNode(debugLabel: 'page-bubbles-nav');
  final FocusNode _bubbleDetailFocus = FocusNode(
    debugLabel: 'page-bubble-detail-nav',
  );
  final FocusNode _learningFocus = FocusNode(debugLabel: 'page-learning-nav');

  @override
  void initState() {
    super.initState();
    UserSession.getUserId().then((id) {
      if (mounted) setState(() => _userId = id);
    });
  }

  @override
  void dispose() {
    _railNav.dispose();
    _railFocusNode.dispose();
    _homeFocus.dispose();
    _bubblesFocus.dispose();
    _bubbleDetailFocus.dispose();
    _learningFocus.dispose();
    super.dispose();
  }

  /// The page that stays mounted (inert) UNDERNEATH the floating File
  /// Library window. Remembered when the library is summoned, restored
  /// when the window closes -- that's what makes the window "float over
  /// the page you were on" instead of over an empty background. Never 5
  /// (guarded in [changePage]).
  int _underPage = 0;

  void changePage(int page) {
    setState(() {
      // Summoning the library: remember what's beneath the window so the
      // close restores it. Already-open is a no-op on _underPage.
      if (page == 5 && selectedPage != 5) {
        _underPage = selectedPage;
      }
      selectedPage = page;
      _syncRailToPage(page);
    });
  }

  /// Barrier tap / floating-window X: close the library and go back to the
  /// page that was open when it was summoned.
  void closeLibrary() {
    setState(() {
      selectedPage = _underPage;
      _syncRailToPage(_underPage);
    });
  }

  void _syncRailToPage(int page) {
    switch (page) {
      case 0:
        _railNav.setIndex(0);
      case 1:
      case 4:
        _railNav.setIndex(1);
      case 2:
        _railNav.setIndex(2);
      case 5:
        _railNav.setIndex(3);
      default:
        break;
    }
  }

  void _focusRail() => _railFocusNode.requestFocus();

  void _focusContentPage() {
    switch (selectedPage) {
      case 0:
        _homeFocus.requestFocus();
      case 1:
        _bubblesFocus.requestFocus();
      case 2:
        _learningFocus.requestFocus();
      case 4:
        _bubbleDetailFocus.requestFocus();
      case 5:
        // File library overlay owns its own focus; nothing to hand off to.
        break;
      default:
        break;
    }
  }

  void _activateRailIndex(int index) {
    switch (index) {
      case 0:
        changePage(0);
      case 1:
        changePage(1);
      case 2:
        changePage(2);
      case 3:
        changePage(5);
      case 4:
        showDialog(
          context: context,
          barrierDismissible: true,
          barrierColor: context.cerebrum.text.muted.withAlpha(100),
          builder: (_) => const SettingPage(),
        );
    }
  }

  Widget _buildPage() {
    if (_userId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _pageFor(selectedPage);
  }

  Widget _pageFor(int page) {
    if (page == 0) {
      return DHomescreen(
        navFocusNode: _homeFocus,
        onFocusRail: _focusRail,
        onOpenBubble: (bubble) {
          setState(() {
            selectedPage = 4;
            payload = bubble;
          });
        },
        onOpenStudyBubbles: () => changePage(1),
      );
    } else if (page == 1) {
      return DStudyBubbleHome(
        navFocusNode: _bubblesFocus,
        onFocusRail: _focusRail,
        onOpenBubble: (bubble) {
          setState(() {
            selectedPage = 4;
            payload = bubble;
          });
        },
      );
    } else if (page == 2) {
      return DLearningCenterPage(
        userId: _userId!,
        navFocusNode: _learningFocus,
        onFocusRail: _focusRail,
      );
    } else if (page == 3) {
      return SettingPage();
    } else if (page == 4) {
      return DStudyBubblePage(
        bubble: payload,
        navFocusNode: _bubbleDetailFocus,
        onFocusRail: _focusRail,
        onBack: () {
          setState(() {
            selectedPage = 1;
            payload = null;
          });
        },
      );
    } else if (page == 5) {
      return _pageFor(_underPage);
    }
    return const Center(child: Text('Unknown Page'));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double expandedWidth = 70;
    const double collapsedWidth = 24; // icon-only width
    const double railInset = 6;
    const double topInset = 24;

    final double railWidth = _sidebarOpen ? expandedWidth : collapsedWidth;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Main content — padding tracks the rail's current width so
          // content never overlaps it, but the rail itself never moves
          // or disappears, so icons stay fixed vertically.
          AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: EdgeInsets.only(left: railWidth + railInset + 6),
            child: _buildPage(),
          ),

          // Persistent icon rail. Only its width and background pill
          // animate; the icons themselves never slide off-screen.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: railInset,
                  top: topInset,
                  bottom: topInset,
                ),
                child: KeyboardNavScope(
                  focusNode: _railFocusNode,
                  onUp: () => setState(() => _railNav.move(-1)),
                  onDown: () => setState(() => _railNav.move(1)),
                  onTop: () => setState(_railNav.first),
                  onBottom: () => setState(_railNav.last),
                  onActivate: () => _activateRailIndex(_railNav.index),
                  onRight: _focusContentPage,
                  onBack: selectedPage == 5 ? closeLibrary : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: railWidth,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withAlpha(0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 24),
                                    Visibility(
                                      visible: _sidebarOpen,
                                      maintainSize: true,
                                      maintainAnimation: true,
                                      maintainState: true,
                                      child: SidebarButton(
                                        icon:
                                            _pinned
                                                ? Icons.menu_open
                                                : Icons.menu,
                                        label: _pinned ? 'Unpin' : 'Pin',
                                        selected: _pinned,
                                        collapsed: !_sidebarOpen,
                                        onPressed: () {
                                          setState(() => _pinned = !_pinned);
                                        },
                                      ),
                                    ),
                                    SidebarButton(
                                      icon: Icons.home,
                                      label: 'Home',
                                      selected: selectedPage == 0,
                                      focused:
                                          _railFocusNode.hasFocus &&
                                          _railNav.index == 0,
                                      collapsed: !_sidebarOpen,
                                      onPressed: () => changePage(0),
                                    ),
                                    SidebarButton(
                                      icon: Icons.bubble_chart,
                                      label: 'Study Bubble',
                                      selected:
                                          selectedPage == 1 ||
                                          selectedPage == 4,
                                      focused:
                                          _railFocusNode.hasFocus &&
                                          _railNav.index == 1,
                                      collapsed: !_sidebarOpen,
                                      onPressed: () => changePage(1),
                                    ),
                                    SidebarButton(
                                      icon: Icons.book,
                                      label: 'Learning Center',
                                      selected: selectedPage == 2,
                                      focused:
                                          _railFocusNode.hasFocus &&
                                          _railNav.index == 2,
                                      collapsed: !_sidebarOpen,
                                      onPressed: () => changePage(2),
                                    ),
                                    SidebarButton(
                                      icon: Icons.library_books,
                                      label: 'File Library',
                                      selected: selectedPage == 5,
                                      focused:
                                          _railFocusNode.hasFocus &&
                                          _railNav.index == 3,
                                      collapsed: !_sidebarOpen,
                                      onPressed: () => changePage(5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SidebarButton(
                          icon: Icons.settings,
                          label: 'Settings',
                          focused:
                              _railFocusNode.hasFocus && _railNav.index == 4,
                          collapsed: !_sidebarOpen,
                          onPressed: () => _activateRailIndex(4),
                        ),
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (selectedPage == 5) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: closeLibrary,
                child: ColoredBox(
                  color: context.cerebrum.text.muted.withAlpha(100),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            FileLibrary(onClose: closeLibrary),
          ],
        ],
      ),
    );
  }
}
