import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/bubbles_api.dart';
import 'package:cerebrum_app/ui/desktop/widgets/card_view.dart';
import 'package:cerebrum_app/ui/desktop/screens/study_bubble/d_study_bubble_page.dart';

class DStudyBubbleHome extends StatefulWidget {
  final Function(Map<String, dynamic> bubble) onOpenBubble;
  const DStudyBubbleHome({super.key, required this.onOpenBubble});

  @override
  State<DStudyBubbleHome> createState() => _DStudyBubbleHomeState();
}

class _DStudyBubbleHomeState extends State<DStudyBubbleHome> {
  List<dynamic> bubbles = [];

  @override
  void initState() {
    super.initState();
    fetchBubbles();
  }

  Future<void> fetchBubbles() async {
    try {
      final data = await BubblesApi.fetchBubbles();
      setState(() => bubbles = data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> deleteBubbles(bubbleId) async {
    try {
      await BubblesApi.deleteBubble(bubbleId);
      final updatedBubbles = await BubblesApi.fetchBubbles();
      setState(() => bubbles = updatedBubbles);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  void addBubbleWidget() async {
    final newBubble = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DStudyBubblePage(addMode: true)),
    );

    // When creation page returns a project
    if (newBubble != null) {
      setState(() => bubbles.insert(0, newBubble));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Study Bubbles")),
      floatingActionButton: FloatingActionButton(
        onPressed: addBubbleWidget,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.builder(
          itemCount: bubbles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) {
            final bubble = bubbles[index];

            return CardView(
              data: bubble,
              onTap: () {
                widget.onOpenBubble(bubble);
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (BuildContext dialogContext) => AlertDialog(
                        title: const Text("Delete Study Bubble"),
                        content: const Text(
                          "Are you sure you want to delete this study bubble?",
                        ),
                        actions: [
                          TextButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(true),
                            child: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          TextButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(false),
                            child: const Text("Cancel"),
                          ),
                        ],
                      ),
                );

                if (confirm == true) await deleteBubbles(bubble['id']);
              },
            );
          },
        ),
      ),
    );
  }
}
