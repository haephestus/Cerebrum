import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/services/id.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/sync_service.dart';
import 'package:cerebrum/ui/editor/blocks/image/note_image_resolver.dart';
import 'package:cerebrum/ui/editor/editor_scaffold.dart';
import 'package:cerebrum/ui/widgets/editable_title.dart';

class DStudyBubblePage extends StatefulWidget {
  final bool addMode;
  final Map<String, dynamic>? bubble;
  final VoidCallback? onBack;

  const DStudyBubblePage({
    super.key,
    this.addMode = false,
    this.bubble,
    this.onBack,
  });

  @override
  State<DStudyBubblePage> createState() => _DStudyBubblePageState();
}

class _DStudyBubblePageState extends State<DStudyBubblePage> {
  List<Map<String, dynamic>> notes = [];
  late String bubbleId;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  bool isLoading = false;

  // Filename of whichever note row currently has a fetch-full-note request
  // in flight, so the tapped tile can show a spinner instead of the whole
  // list looking frozen while we go get its ink.
  String? _openingFilename;

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
  // NOTE: this hits the LIST endpoint, which deliberately returns
  // `ink: []` for every note (see backend comment on list_notes_in_bubble
  // — ink is intentionally excluded from the list response to keep it
  // cheap). Never build an EditorScaffold's `note:` param straight from
  // an entry in `notes` — go through `_openNote` below instead, which
  // fetches the detail endpoint first.
  Future<void> loadNotes(String bubbleId) async {
    // 1) Local-first: show whatever we have on disk immediately. Works fully
    // offline and makes the list appear instantly instead of waiting on the net.
    final local = await NoteStore.listNotes(bubbleId);
    if (mounted && local.isNotEmpty) {
      setState(
        () =>
            notes =
                local.map((n) => {...n, 'bubble_id': bubbleId}).toList(),
      );
    }

    // 2) Background-refresh from the daemon when reachable.
    try {
      final data = await BubbleNotesApi.fetchNotes(bubbleId);

      // Ensure each note has bubbleId and proper content structure
      for (var note in data) {
        // Ensure bubbleId is set
        note['bubble_id'] = bubbleId;

        // Ensure content has document key
        if (note['content'] is Map &&
            !note['content'].containsKey('document')) {
          note['content'] = {'document': note['content']};
        }
      }

      // Keep local-only notes the server doesn't know about yet (created or
      // queued while offline) so a refresh can't drop unsynced work.
      final serverFilenames =
          data.map((n) => n['filename']).whereType<String>().toSet();
      final localOnly = local.where(
        (l) =>
            l['filename'] == null ||
            !serverFilenames.contains(l['filename']),
      );

      if (mounted) {
        setState(
          () =>
              notes = [
                ...localOnly.map((n) => {...n, 'bubble_id': bubbleId}),
                ...List<Map<String, dynamic>>.from(data),
              ],
        );
      }
    } catch (e) {
      // Offline / hub down — the local list already stands in. Only surface an
      // error if we had nothing local to show.
      if (mounted && local.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    }
  }

  // -----------------------
  // Open an existing note in the editor
  // -----------------------
  // Fetches the full note (content + ink) via the detail endpoint before
  // navigating, since the list-view `note` map passed in here always has
  // `ink: []`. This is the fix for ink not loading when reopening a note.
  Future<void> _openNote(Map<String, dynamic> listNote) async {
    final filename = listNote['filename'] as String?;
    final noteId =
        listNote['note_id'] as String? ??
        (filename != null && filename.endsWith('.json')
            ? filename.substring(0, filename.length - 5)
            : filename);
    if (filename == null && noteId == null) return;

    setState(() => _openingFilename = filename ?? noteId);

    try {
      // 1) Local-first read — instant and works offline.
      Map<String, dynamic>? fullNote =
          noteId != null ? await NoteStore.readNote(bubbleId, noteId) : null;

      // 2) If online and the note isn't carrying unsynced local edits, prefer
      // the daemon's copy — it's authoritative and also carries server-only
      // fields (analysis, etc.). Locally-dirty notes keep the local copy so we
      // don't clobber a queued edit with a stale server version.
      final sync =
          noteId != null
              ? await NoteStore.readSyncState(bubbleId, noteId)
              : const <String, dynamic>{'dirty': false};
      final locallyDirty = sync['dirty'] == true;
      if (filename != null && (fullNote == null || !locallyDirty)) {
        try {
          final remote = await BubbleNotesApi.fetchNoteByFileName(
            bubbleId,
            filename,
          );
          remote['bubble_id'] = bubbleId;
          fullNote = remote;
        } catch (_) {
          // Offline / hub down — fall back to the local copy (if any).
        }
      }

      if (fullNote == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Note isn't available offline yet.")),
          );
        }
        return;
      }

      fullNote['bubble_id'] = bubbleId;
      if (noteId != null) fullNote['note_id'] ??= noteId;

      // Prime the image resolver before the editor renders so embedded
      // cerebrum-image:// refs resolve on the first frame.
      final resolvedId = fullNote['note_id'] as String?;
      if (resolvedId != null) {
        await NoteImageResolver.configureForNote(
          bubbleId: bubbleId,
          noteId: resolvedId,
        );
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorScaffold(note: fullNote!)),
      );

      // Reload notes when returning from editor
      loadNotes(bubbleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to open note: $e")));
      }
    } finally {
      if (mounted) setState(() => _openingFilename = null);
    }
  }

  // -----------------------
  // Add a new note
  // -----------------------
  Future<void> addNote() async {
    try {
      // Blank AppFlowy document (one empty paragraph on one page).
      final Map<String, dynamic> blankDocument = {
        "type": "page",
        "children": [
          {
            "type": "paragraph",
            "data": {
              "delta": [
                {"insert": ""},
              ],
            },
          },
        ],
      };

      // Client-owned identity (phase 4): the note exists locally the instant
      // it's created — before the daemon ever sees it — so a note can be created
      // fully offline. The daemon's createNote then becomes the FIRST PUSH of an
      // already-local note (SyncService materialises it and back-fills the
      // server filename).
      final noteId = Ulid.generate();
      final pages = <Map<String, dynamic>>[
        {
          'page_id': 'p1',
          'page_index': 0,
          'document': blankDocument,
          'ink': <Map<String, dynamic>>[],
        },
      ];

      // 1) Persist locally first — always succeeds, offline included.
      await NoteStore.writeNote(
        bubbleId: bubbleId,
        noteId: noteId,
        manifest: {
          'title': 'Untitled Note',
          'filename': null,
          'note_id': noteId,
          'bubble_id': bubbleId,
          'analyse_note': true,
        },
        pages: pages,
      );
      await NoteStore.markDirty(bubbleId, noteId);

      // 2) Best-effort first push (create on the daemon). Queued for retry if
      // we're offline; on success SyncService back-fills the server filename
      // into the local manifest.
      final merged = await SyncService.queueSave(
        bubbleId: bubbleId,
        noteId: noteId,
        title: 'Untitled Note',
        pages: pages,
        filename: null,
      );

      final Map<String, dynamic> newNote = {
        "title": merged?['title'] ?? 'Untitled Note',
        "note_id": noteId,
        "filename": merged?['filename'], // null while still local-only
        "bubble_id": bubbleId,
        "pages": merged?['pages'] ?? pages,
      };

      // Show it in the list immediately.
      setState(() {
        notes.insert(0, newNote);
      });

      // Prime the image resolver for the new note before opening the editor.
      await NoteImageResolver.configureForNote(
        bubbleId: bubbleId,
        noteId: noteId,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditorScaffold(note: newNote)),
        ).then((_) {
          // Reload notes after returning from editor
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
  //  Rename a note
  // -----------------------
  Future<void> renameNote(
    String bubbleId,
    String oldFilename,
    String newFilename,
  ) async {
    try {
      await BubbleNotesApi.renameNote(bubbleId, oldFilename, newFilename);
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
  // Delete note
  // -----------------------
  Future<void> deleteNote(
    String bubbleId,
    String? filename, {
    String? noteId,
  }) async {
    final localId =
        noteId ??
        (filename != null && filename.endsWith('.json')
            ? filename.substring(0, filename.length - 5)
            : filename);

    // Tombstone locally first so the row disappears immediately and a background
    // refresh can't resurrect it — offline included.
    if (localId != null) await NoteStore.markDeleted(bubbleId, localId);

    if (filename != null && localId != null) {
      // Exists on the server → queue the delete. It runs now if the daemon is
      // reachable, else on the next drain (start/resume/reconnect); the local
      // folder is purged once the daemon confirms.
      await SyncService.queueDelete(
        bubbleId: bubbleId,
        noteId: localId,
        filename: filename,
      );
    } else if (localId != null) {
      // Local-only note (never pushed) → nothing on the server; just drop it.
      await NoteStore.purge(bubbleId, localId);
    }

    await loadNotes(bubbleId);
  }

  // -----------------------
  // Create bubble (add mode)
  // -----------------------
  Future<void> createBubble() async {
    setState(() => isLoading = true);
    try {
      final name = nameCtrl.text.trim();
      final result = await BubblesApi.createBubble(
        name: name,
        description: descCtrl.text.trim(),
        domains: [],
        userGoals: [],
        // md5-of-name (matches the daemon fallback), kept distinct from the
        // ULID note ids. Hash the exact string we send as `name`.
        bubbleId: bubbleIdFromName(name),
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
                    // TODO: add rename buttom
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
                  final noteKey = note['filename'] ?? note['note_id'];
                  final isOpening = _openingFilename == noteKey;

                  return ListTile(
                    key: ValueKey(noteKey),
                    title: EditableTitle(
                      initialTitle: note['title'] ?? 'Untitled',
                      onTitleChanged: (newTitle) async {
                        if (newTitle.isNotEmpty && newTitle != note['title']) {
                          final oldTitle = note['filename'];
                          setState(() {
                            note['title'] = newTitle;
                          });
                          await renameNote(bubbleId, oldTitle, newTitle);
                        }
                      },
                    ),
                    subtitle: Text(
                      note["filename"] ?? "",
                      style: TextStyle(fontSize: 12),
                    ),
                    // Was previously: build EditorScaffold directly from
                    // `note` (the list-view entry, ink always []). Now
                    // routes through `_openNote`, which fetches the full
                    // note — content + real ink — via the detail endpoint
                    // first.
                    onTap: isOpening ? null : () => _openNote(note),
                    trailing:
                        isOpening
                            ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : IconButton(
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
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
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
                                  await deleteNote(
                                    bubbleId,
                                    note["filename"] as String?,
                                    noteId: note["note_id"] as String?,
                                  );
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
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: "Back to Study Bubbles",
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    Text(
                      widget.bubble?['name'] ?? "No name",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
