import 'package:flutter/material.dart';

class DropDownSettingItem<T> extends StatelessWidget {
  final List<DropdownMenuEntry<T>> dropdownMenuEntries;
  final String label;
  final ValueChanged<T> onSelected;
  final T initialSelection;

  const DropDownSettingItem({
    required this.label,
    required this.onSelected,
    required this.initialSelection,
    required this.dropdownMenuEntries,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          DropdownMenu<T>(
            key: ValueKey(initialSelection),
            width: size.width * 0.10,
            dropdownMenuEntries: dropdownMenuEntries,
            initialSelection: initialSelection,
            onSelected: (value) {
              if (value != null) onSelected(value);
            },
            inputDecorationTheme: const InputDecorationTheme(
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.transparent),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.transparent),
              ),
            ),
            menuStyle: const MenuStyle(
              alignment: Alignment(-0.95, 0.5),
              maximumSize: WidgetStatePropertyAll(Size(180, 128)),
            ),
          ),
        ],
      ),
    );
  }
}
