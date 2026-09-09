import 'package:cerebrum/ui/screens/home/file_library.dart';
import 'package:cerebrum/ui/screens/home/quickview.dart';
import 'package:cerebrum/ui/screens/home/suggested_reading.dart';
import 'package:cerebrum/ui/screens/home/upcoming_engrams.dart';
import 'package:flutter/material.dart';

// from analysis api, we get concept_map.confused_links
// concept_map.weak_areas
// suggested_sources -> this will the be passed onto the suggested_reading widget
// a study bubble only view clustering weak_areas
// the goal for this is to be fyp for education, firstly what the user needs
// help with, secondly what the could interest the user (need to hook into the
// daemons suggested_reading updates)
//
// signal for overdue engrams (flashcard, mcp, long qs, short qs and readings)
//
// possibly a featured reading? (based of a topic that user is struggling with,
// can be a carrousel of cards, the  would be syncfusion pdf views (this way
// texts and etc are properly rendered and interacted with))
//
// redesign of widgets - the current maybe lacking, quickview was suggested as a
// renaming for notes, but more descriptive and appropriate names(named after
// widgets purpose)
//
// could have progress tracking of a study plan(user could change focus to
// different study plans to see progress).
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
                  Expanded(flex: 3, child: Quickview()),

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
