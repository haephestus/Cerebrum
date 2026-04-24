import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';

class NoteDrawingLayer extends StatelessWidget {
  final DrawingController controller;

  const NoteDrawingLayer({Key? key, required this.controller})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DrawingBoard(
      controller: controller,
      background: Container(color: Colors.transparent),
      showDefaultActions: true, // show toolbar with pen/erase etc
      showDefaultTools: true,
    );
  }
}
