import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget desktop;

  const ResponsiveLayout({required this.desktop, super.key});

  static const int mobileBreakpoint = 600;
  //TODO: static const int tabletBreakpoint = 1200;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < mobileBreakpoint) {
      // Mobile layout isn't built yet — the scaffold falls back to the desktop
      // layout so every width compiles and renders something.
      return desktop;
    } else {
      return desktop;
    }
  }
}
