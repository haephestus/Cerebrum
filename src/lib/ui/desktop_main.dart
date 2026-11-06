import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/screens/home/d_homescreen_page.dart';
import 'package:cerebrum/ui/screens/file_library/file_library.dart';
import 'package:cerebrum/ui/screens/learning_center/d_learning_center_page.dart';
import 'package:cerebrum/ui/screens/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/widgets/shell/sidebar_button.dart';
import 'package:cerebrum/ui/screens/study_bubble/d_study_bubble_page.dart';
import 'package:cerebrum/ui/screens/study_bubble/d_study_bubble_home.dart';
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

  @override
  void initState() {
    super.initState();
    UserSession.getUserId().then((id) {
      if (mounted) setState(() => _userId = id);
    });
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
    });
  }

  /// Barrier tap / floating-window X: close the library and go back to the
  /// page that was open when it was summoned.
  void closeLibrary() {
    setState(() => selectedPage = _underPage);
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
        onOpenBubble: (bubble) {
          setState(() {
            selectedPage = 4;
            payload = bubble;
          });
        },
      );
    } else if (page == 2) {
      return DLearningCenterPage(userId: _userId!);
    } else if (page == 3) {
      return SettingPage();
    } else if (page == 4) {
      return DStudyBubblePage(
        bubble: payload,
        onBack: () {
          setState(() {
            selectedPage = 1;
            payload = null;
          });
        },
      );
    } else if (page == 5) {
      // File Library as its own sidebar page. The window itself is NOT
      // built here: it is overlaid at the SHELL level (see the end of
      // build()) so its dim barrier covers the whole viewport including
      // the icon rail. The content area shows the page that was open when
      // the library was summoned (_underPage remembers it, closeLibrary
      // restores it), rendered inert under the barrier -- the floating
      // window layered OVER real content, like the Settings dialog.
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: railWidth,
                  decoration: BoxDecoration(
                    color:
                        _sidebarOpen
                            ? colorScheme.onSurface.withAlpha(0)
                            : colorScheme.onSurface.withAlpha(0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Column split into a scrollable top group and a pinned
                  // bottom group. The old single-column-with-Spacer layout
                  // overflowed by 117px whenever the window's usable height
                  // dropped below ~760px (the six buttons plus spacers can't
                  // fit in less). Expanded + SingleChildScrollView lets the
                  // top group compress and scroll on short windows; Settings
                  // stays pinned to the bottom regardless. Removed the
                  // Spacer entirely — Spacer inside a scrollable forces an
                  // unbounded-height error, and Expanded now consumes the
                  // slack Spacer used to.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ScrollConfiguration(
                          // Collapsed rail is 24px wide; the desktop default
                          // scrollbar (~14–16px) would occlude half the
                          // icons. Hide it — content is short, scrolling is
                          // an edge case for tiny windows.
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            // Force the scroll view's content to match the
                            // rail's width. Without this,
                            // SingleChildScrollView defaults to
                            // Alignment.topLeft and the inner Column sizes
                            // itself to its widest child (SidebarButton is
                            // wider than the 24px collapsed rail), pushing
                            // icons 18px to the right — right on top of the
                            // content panel. With width: double.infinity
                            // the inner Column is forced to 24px wide, and
                            // CrossAxisAlignment.center centers the wide
                            // buttons inside it exactly like the original
                            // non-scrollable layout did.
                            child: SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 24),
                                  // Pin/unpin toggle — reserves its height
                                  // even when hidden so Home/Study Bubble/
                                  // Learning Center below it never shift
                                  // position.
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
                                    collapsed: !_sidebarOpen,
                                    onPressed: () => changePage(0),
                                  ),
                                  SidebarButton(
                                    icon: Icons.bubble_chart,
                                    label: 'Study Bubble',
                                    selected: selectedPage == 1,
                                    collapsed: !_sidebarOpen,
                                    onPressed: () => changePage(1),
                                  ),
                                  SidebarButton(
                                    icon: Icons.book,
                                    label: 'Learning Center',
                                    selected: selectedPage == 2,
                                    collapsed: !_sidebarOpen,
                                    onPressed: () => changePage(2),
                                  ),
                                  SidebarButton(
                                    icon: Icons.library_books,
                                    label: 'File Library',
                                    selected: selectedPage == 5,
                                    collapsed: !_sidebarOpen,
                                    onPressed: () => changePage(5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Settings pinned to the bottom, always reachable
                      // even when the top group is scrolled or overflowing.
                      SidebarButton(
                        icon: Icons.settings,
                        label: 'Settings',
                        collapsed: !_sidebarOpen,
                        onPressed: () {
                          showDialog(
                            context: context,
                            barrierDismissible: true,
                            barrierColor: context.cerebrum.text.muted.withAlpha(
                              100,
                            ),
                            builder: (_) => const SettingPage(),
                          );
                        },
                      ),
                      SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Floating File Library overlay -- LAST children of this Stack so
          // the dim barrier covers the ENTIRE window, content AND icon rail
          // alike, exactly like a showDialog route (the in-content-area
          // version floated only over the page body and left the rail
          // undimmed/clickable). Overhead exists only while page 5 is open:
          // with the barrier on top, the underlying page and the rail are
          // visible-but-inert, and the only way out is the barrier tap or
          // the window's X, both of which call [closeLibrary].
          if (selectedPage == 5) ...[
            // Modal barrier: dims everything beneath and swallows all
            // pointer events. Shade matches the Settings dialog barrier.
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
            // The floating window itself. FloatingModal centers itself via
            // its internal Center + ConstrainedBox; as an unpositioned
            // Stack child it fills the shell and centers within it.
            FileLibrary(onClose: closeLibrary),
          ],
        ],
      ),
    );
  }
}
