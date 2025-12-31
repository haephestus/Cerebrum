import 'package:flutter/material.dart';

class EditableTitle extends StatefulWidget {
  final String initialTitle;
  final Function(String) onTitleChanged;
  const EditableTitle({
    required this.initialTitle,
    required this.onTitleChanged,
  });

  @override
  State<EditableTitle> createState() => __EditableTitleState();
}

class __EditableTitleState extends State<EditableTitle> {
  bool isEditing = false;
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      return TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (value) {
          setState(() => isEditing = false);
          widget.onTitleChanged(value);
        },
        onTapOutside: (_) {
          setState(() => isEditing = false);
          widget.onTitleChanged(controller.text);
        },
      );
    }
    return GestureDetector(
      onTap: () => setState(() => isEditing = true),
      child: Text(
        widget.initialTitle,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          fontSize: 18,
        ),
      ),
    );
  }
}
