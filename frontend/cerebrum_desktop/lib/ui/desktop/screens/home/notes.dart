import 'package:flutter/material.dart';

class Notes extends StatefulWidget {
  const Notes({super.key});

  @override
  State<Notes> createState() => _NotesState();
}

class _NotesState extends State<Notes> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 64,
      decoration: BoxDecoration(color: Colors.black),
      child: Text("hello"),
    );
  }
}
