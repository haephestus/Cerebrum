import 'package:cerebrum_app/ui/desktop/screens/settings.dart';
import 'package:flutter/material.dart';
import '/features/home/home_page.dart';
import 'package:cerebrum_app/ui/desktop/widgets/sidebar_button.dart';
import 'package:cerebrum_app/ui/desktop/screens/study_bubble/d_study_bubble_page.dart';
import 'package:cerebrum_app/ui/desktop/screens/study_bubble/d_study_bubble_home.dart';

class DesktopUI extends StatefulWidget {
  const DesktopUI({super.key});

  @override
  State<DesktopUI> createState() => _DesktopUIState();
}

class _DesktopUIState extends State<DesktopUI> {
  int selectedPage = 0;
  Map<String, dynamic>? payload;

  void changePage(int page) {
    setState(() {
      selectedPage = page;
    });
  }

  Widget _buildPage() {
    if (selectedPage == 0) {
      return HomePage();
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
      return Text("data");
    } else if (selectedPage == 3) {
      return Setting();
    } else if (selectedPage == 4) {
      return DStudyBubblePage(addMode: false, bubble: payload);
    }

    return Center(child: Text('Unknown Page'));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              // Left side: buttons
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    icon: Icons.folder,
                    label: 'Projects',
                    selected: selectedPage == 2,
                    onPressed: () => changePage(2),
                  ),
                  SidebarButton(
                    icon: Icons.settings,
                    label: 'Settings',
                    selected: selectedPage == 3,
                    onPressed: () => changePage(3),
                  ),
                ],
              ),
              SizedBox(width: 12), // spacing between buttons and window
              // Right side: main window
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white),
                  child: Container(child: _buildPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
