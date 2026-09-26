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

  @override
  void initState() {
    super.initState();
    // AppEntryPoint already confirmed we're logged in before mounting
    // DesktopUI at all, so this should always resolve to a real id --
    // but we still load it async rather than assuming a sync value,
    // since UserSession reads from SharedPreferences.
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
      // Global dashboard: no specific bubble/note, so DLearningCenterPage
      // shows every active study plan + every engram across the user.
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
    return Center(child: Text('Unknown Page'));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          children: [
            // Left side: buttons
            Container(
              padding: EdgeInsetsGeometry.only(top: 24, bottom: 24, right: 6),
              decoration: BoxDecoration(
                color: colorScheme.onSurface,
                borderRadius: BorderRadiusGeometry.circular(12),
              ),
              height: 900,
              width: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SidebarButton(
                    icon: Icons.home,
                    label: 'Home',
                    selected: selectedPage == 0,
                    onPressed: () => changePage(0),
                  ),
                  SidebarButton(
                    icon: Icons.bubble_chart,
                    label: 'Study Bubble',
                    selected: selectedPage == 1,
                    onPressed: () => changePage(1),
                  ),
                  SidebarButton(
                    icon: Icons.book,
                    label: 'Learning Center',
                    selected: selectedPage == 2,
                    onPressed: () => changePage(2),
                  ),
                  SizedBox(height: 550),
                  IconButton(
                    color: context.cerebrum.surface.canvas,
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
                    icon: Icon(
                      Icons.settings,
                      color:
                          selectedPage == 3
                              ? context.cerebrum.text.onDark
                              : context.cerebrum.surface.canvas,
                      size: 38,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12), // spacing between buttons and window
            // Right side: main window
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: colorScheme.surface),
                child: Container(child: _buildPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
