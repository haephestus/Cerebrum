import 'package:flutter/material.dart';

class SuggestedReading extends StatefulWidget {
  const SuggestedReading({super.key});

  @override
  State<SuggestedReading> createState() => _SuggestedReadingState();
}

class _SuggestedReadingState extends State<SuggestedReading> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 64,
      decoration: BoxDecoration(color: Colors.blue),
      child: Text("hello"),
    );
    ;
  }
}
