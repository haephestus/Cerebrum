import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/bubbles_api.dart';
import 'package:cerebrum_app/features/editor/note_editor_page.dart';

class DStudyBubblePage extends StatefulWidget {
  final bool addMode;
  final Map<String, dynamic>? bubble;

  const DStudyBubblePage({super.key, this.addMode = false, this.bubble});

  @override
  State<DStudyBubblePage> createState() => _DStudyBubblePageState();
}

class _DStudyBubblePageState extends State<DStudyBubblePage> {
  List<Map<String, dynamic>> notes = [];
  late String bubbleId;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    if (!widget.addMode && widget.bubble != null) {
      bubbleId = widget.bubble!["id"].toString();
      loadNotes(bubbleId);
    }
  }

  // -----------------------
  // Load notes
  // -----------------------
  Future<void> loadNotes(String bubbleId) async {
    try {
      final data = await BubbleNotesApi.fetchNotes(bubbleId);

      // Ensure each note has bubbleId and proper content structure
      for (var note in data) {
        // Ensure bubbleId is set
        note['bubbleId'] = bubbleId;

        // Ensure content has document key
        if (note['content'] is Map &&
            !note['content'].containsKey('document')) {
          note['content'] = {'document': note['content']};
        }
      }

      setState(() => notes = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    }
  }

  // -----------------------
  // Add a new note
  // -----------------------
  Future<void> addNote() async {
    try {
      // Blank AppFlowy document structure
      final blankDoc = {
        "document": {
          "type": "page",
          "children": [
            {"type": "paragraph", "data": {}},
          ],
        },
      };

      Map<String, dynamic> newNote = {
        "title": "Untitled Note",
        "content": blankDoc,
        "ink": <Map<String, dynamic>>[],
        "bubbleId": bubbleId,
        "filename": null,
      };

      // Create note in backend
      final createdNote = await BubbleNotesApi.createNote(
        bubbleId: bubbleId,
        title: newNote['title']!,
        content: newNote['content']!,
        ink: newNote['ink']!,
      );

      // Update newNote with backend data
      newNote['filename'] = createdNote['filename'];
      newNote['title'] = createdNote['title'];
      newNote['content'] = createdNote['content'];
      newNote['ink'] = createdNote['ink'];
      newNote['bubbleId'] = bubbleId; // Ensure bubbleId is set

      setState(() {
        notes.insert(0, newNote);
      });

      // Open editor
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => NoteEditorPage(
                  note: newNote,
                  initialTextJson: newNote['content'],
                  initialInkJson: List<Map<String, dynamic>>.from(
                    newNote['ink'],
                  ),
                ),
          ),
        ).then((_) {
          // Reload notes when returning from editor
          loadNotes(bubbleId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    }
  }

  // -----------------------
  // Delete note
  // -----------------------
  Future<void> deleteNote(String bubbleId, String filename) async {
    try {
      await BubbleNotesApi.deleteNote(bubbleId, filename);
      await loadNotes(bubbleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    }
  }

  // -----------------------
  // Create bubble (add mode)
  // -----------------------
  Future<void> createBubble() async {
    setState(() => isLoading = true);
    try {
      final result = await BubblesApi.createBubble(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        domains: [],
        userGoals: [],
      );
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.addMode) {
      return Scaffold(
        appBar: AppBar(title: const Text("Create Study Bubble")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Bubble Name"),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: "Description"),
              ),
              const SizedBox(height: 20),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                    onPressed: createBubble,
                    child: const Text("Create"),
                  ),
            ],
          ),
        ),
      );
    }

    // Desktop view
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // CENTER: notes list
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: ListView.builder(
                itemCount: notes.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.add, color: Colors.blue),
                      title: const Text(
                        "Add New Note",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: addNote,
                    );
                  }

                  final note = notes[index - 1];

                  return ListTile(
                    key: ValueKey(note["filename"]),
                    title: Text(note["title"] ?? "Untitled"),
                    subtitle: Text(note["filename"] ?? ""),
                    onTap: () {
                      // Ensure note has bubbleId before opening
                      final noteToEdit = Map<String, dynamic>.from(note);
                      noteToEdit['bubbleId'] = bubbleId;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteEditorPage(note: noteToEdit),
                        ),
                      ).then((_) {
                        // Reload notes when returning from editor
                        loadNotes(bubbleId);
                      });
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_rounded),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (dialogContext) => AlertDialog(
                                title: const Text("Delete Note"),
                                content: const Text(
                                  "Are you sure you want to delete this note?",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                    child: const Text(
                                      "Delete",
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                    child: const Text("Cancel"),
                                  ),
                                ],
                              ),
                        );

                        if (confirm == true) {
                          await deleteNote(bubbleId, note["filename"]);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ),

          // RIGHT: bubble info
          Container(
            width: 400,
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.bubble?['name'] ?? "No name",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.bubble?['description'] ?? "No description yet.",
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

