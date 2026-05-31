import 'package:cerebrum_app/ui/desktop/screens/home/file_library.dart';
import 'package:cerebrum_app/ui/desktop/screens/home/notes.dart';
import 'package:cerebrum_app/ui/desktop/screens/home/suggested_reading.dart';
import 'package:cerebrum_app/ui/desktop/screens/home/tasks.dart';
import 'package:flutter/material.dart';

class DHomescreen extends StatefulWidget {
  const DHomescreen({super.key});

  @override
  State<DHomescreen> createState() => _DHomescreenState();
}

class _DHomescreenState extends State<DHomescreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Welcome Back User")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsetsGeometry.only(bottom: 12),
              height: 130,
              width: double.infinity,
              child: Tasks(),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 800, width: 1000, child: Notes()),

                Column(
                  children: [
                    SizedBox(height: 400, width: 780, child: FileLibrary()),
                    SizedBox(
                      height: 400,
                      width: 750,
                      child: SuggestedReading(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
