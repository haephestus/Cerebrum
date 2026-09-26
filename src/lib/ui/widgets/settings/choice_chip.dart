import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

class ChoiceSettingItem extends StatefulWidget {
  final dynamic value;
  final String label;
  final List<dynamic> choices;
  final ValueChanged<dynamic> onSelected;
  const ChoiceSettingItem({
    required this.label,
    required this.value,
    required this.onSelected,
    required this.choices,
    super.key,
  });

  @override
  State<ChoiceSettingItem> createState() => _ChoiceSettingItemState();
}

class _ChoiceSettingItemState extends State<ChoiceSettingItem> {
  late dynamic _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsGeometry.only(left: 18, right: 20),
      child: Row(
        children: <Widget>[
          Text(widget.label, style: TextStyle(fontSize: 16)),
          Spacer(),
          Wrap(
            children:
                List<Widget>.generate(widget.choices.length, (int index) {
                  return ChoiceChip(
                    showCheckmark: false,
                    selectedColor: context.cerebrum.status.danger,
                    disabledColor:
                        cs.surfaceContainerHighest, // ← was context.cerebrum.surface.outlineStrong
                    label: Text(
                      widget.choices[index].toString(),
                      style: TextStyle(
                        color:
                            _selected == index
                                ? cs
                                    .surface // ← text on selected chip
                                : cs.onSurface,
                      ),
                    ),
                    selected: _selected == index,
                    onSelected: (bool selected) {
                      setState(() {
                        _selected = selected ? index : null;
                      });
                      widget.onSelected(index);
                    },
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}
