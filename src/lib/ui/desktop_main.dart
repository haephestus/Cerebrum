import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/screens/home/d_homescreen_page.dart';
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

  void changePage(int page) {
    setState(() {
      selectedPage = page;
    });
  }

  Widget _buildPage() {
    if (_userId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (selectedPage == 0) {
      return DHomescreen(
        onOpenBubble: (bubble) {
          setState(() {
            selectedPage = 4;
            payload = bubble;
          });
        },
        onOpenStudyBubbles: () => changePage(1),
      );
    } else if (selectedPage == 1) {
      return DStudyBubbleHome(
        onOpenBubble: (bubble) {
          setState(() {
            selectedPage = 4;
            payload = bubble;
          });
        },
      );
    } else if (selectedPage == 2) {
      return DLearningCenterPage(userId: _userId!);
    } else if (selectedPage == 3) {
      return SettingPage();
    } else if (selectedPage == 4) {
      return DStudyBubblePage(
        bubble: payload,
        onBack: () {
          setState(() {
            selectedPage = 1;
            payload = null;
          });
        },
      );
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(height: 24),
                      // Pin/unpin toggle — reserves its height even when
                      // hidden so Home/Study Bubble/Learning Center below
                      // it never shift position.
                      Visibility(
                        visible: _sidebarOpen,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: SidebarButton(
                          icon: _pinned ? Icons.menu_open : Icons.menu,
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
                      const Spacer(),
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
        ],
      ),
    );
  }
}
