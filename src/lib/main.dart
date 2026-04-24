import 'package:flutter/material.dart';
// import './responsive_layout.dart';
import 'ui/desktop/desktop_main.dart';

void main() {
  runApp(const CerebrumApp());
}

class CerebrumApp extends StatelessWidget {
  const CerebrumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const DesktopUI(),
      // TODO: tablet: const TabletUI()
    );
  }
}
