import 'package:cerebrum/ui/screens/home/file_library.dart';
import 'package:cerebrum/ui/screens/home/notes.dart';
import 'package:cerebrum/ui/screens/home/suggested_reading.dart';
import 'package:cerebrum/ui/screens/home/upcoming_engrams.dart';
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
          children: [
            // No fixed height: the section sizes to its content and scrolls
            // internally past its own cap, so it never overflows on resize.
            const SizedBox(
              width: double.infinity,
              child: UpcomingEngramsSection(),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: Notes()),

                  const SizedBox(width: 16),

                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Expanded(child: FileLibrary()),

                        const SizedBox(height: 16),

                        Expanded(child: SuggestedReading()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
