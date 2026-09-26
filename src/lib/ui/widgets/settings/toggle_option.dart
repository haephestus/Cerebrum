import 'package:flutter/material.dart';

class SwitchSettingItem extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchSettingItem({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      activeThumbColor: cs.primary,
      activeTrackColor: cs.primary.withValues(alpha: 0.5),
      inactiveThumbColor: cs.secondary,
      inactiveTrackColor: cs.secondary.withValues(alpha: 0.3),
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
