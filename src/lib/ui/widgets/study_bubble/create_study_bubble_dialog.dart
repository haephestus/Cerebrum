import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/services/id.dart';

/// Ask for a new study bubble's name/description and create it via
/// BubblesApi. Returns the created bubble map, or null if dismissed.
///
/// Creation lives HERE (a dialog launched from wherever bubbles are listed),
/// not inside DStudyBubblePage — a bubble page has no business creating
/// bubbles. Mirrors the old addMode flow: createBubble(name, description)
/// with md5-of-name bubbleId, popping the created bubble back to the caller.
Future<Map<String, dynamic>?> showCreateStudyBubbleDialog(
  BuildContext context,
) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  final created = await showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (dialogContext) =>
            _CreateStudyBubbleDialog(nameCtrl: nameCtrl, descCtrl: descCtrl),
  );

  nameCtrl.dispose();
  descCtrl.dispose();
  return created;
}

class _CreateStudyBubbleDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;

  const _CreateStudyBubbleDialog({
    required this.nameCtrl,
    required this.descCtrl,
  });

  @override
  State<_CreateStudyBubbleDialog> createState() =>
      _CreateStudyBubbleDialogState();
}

class _CreateStudyBubbleDialogState extends State<_CreateStudyBubbleDialog> {
  bool _submitting = false;

  Future<void> _submit() async {
    final name = widget.nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final result = await BubblesApi.createBubble(
        name: name,
        description: widget.descCtrl.text.trim(),
        domains: [],
        userGoals: [],
        // md5-of-name (matches the daemon fallback), kept distinct from the
        // ULID note ids. Hash the exact string we send as `name`.
        bubbleId: bubbleIdFromName(name),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create Study Bubble"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.nameCtrl,
            decoration: const InputDecoration(labelText: "Bubble Name"),
            autofocus: true,
          ),
          TextField(
            controller: widget.descCtrl,
            decoration: const InputDecoration(labelText: "Description"),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child:
              _submitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text("Create"),
        ),
      ],
    );
  }
}
