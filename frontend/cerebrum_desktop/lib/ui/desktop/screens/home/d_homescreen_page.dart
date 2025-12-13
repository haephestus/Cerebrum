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
      body: Column(
        children: [
          Text("upcomming quizes"),
          Text("results from last quiz"),
          Text("add file to knowledgebase"),
          Text("files in the knowledgebase"),
        ],
      ),
    );
  }
}
