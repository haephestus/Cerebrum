import 'package:flutter/material.dart';

class FileLibrary extends StatefulWidget {
  const FileLibrary({super.key});

  @override
  State<FileLibrary> createState() => _FileLibraryState();
}

class _FileLibraryState extends State<FileLibrary> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 64,
      decoration: BoxDecoration(color: Colors.red),
      child: Text("hello"),
    );
    ;
  }
}
