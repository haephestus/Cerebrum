import 'package:flutter/material.dart';

class ThemeFamily {
  final String id;
  final String label;
  final ThemeData light;
  final ThemeData dark;

  const ThemeFamily({
    required this.id,
    required this.label,
    required this.light,
    required this.dark,
  });
}
