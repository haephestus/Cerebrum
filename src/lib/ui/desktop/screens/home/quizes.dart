import 'package:flutter/material.dart';

class Quizes extends StatefulWidget {
  const Quizes({super.key});

  @override
  State<Quizes> createState() => _QuizesState();
}

class _QuizesState extends State<Quizes> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 64,
      decoration: BoxDecoration(color: Colors.grey),
      child: Text("hello"),
    );
    ;
  }
}
