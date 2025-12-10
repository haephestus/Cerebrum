import 'package:flutter/material.dart';

class NoteTextLayer extends StatelessWidget {
  final TextEditingController controller;

  const NoteTextLayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }
}
