import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/id.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/sync_service.dart';
import 'package:cerebrum/ui/screens/editor/blocks/image/note_image_resolver.dart';
import 'package:cerebrum/ui/screens/editor/editor_scaffold.dart';
import 'package:cerebrum/ui/screens/home/gap_repository.dart';
import 'package:cerebrum/ui/widgets/note_card_view.dart';

/// The per-note facts a card renders. Everything here is either a local
/// NoteStore fact or a daemon-cached state (analysis status / gap rollup);
/// nothing is invented on the client.
class _NoteCardData {
  final String? noteId;
  final String? filename;
  final String title;
  final String snippet;
  final bool dirty; // local unsynced edits
  final String? lastEdited; // ISO or null when unknown (chip hidden)
  final AnalysisDisplayStatus analysis; // needs / current / stale / off / unknown
  final int? gapCount; // null when the rollup has no data for this note

  const _NoteCardData({
    required this.noteId,
    required this.filename,
    required this.title,
    required this.snippet,
    required this.dirty,
    required this.lastEdited,
    required this.analysis,
    required this.gapCount,
  });

  String get key => filename ?? noteId ?? title;

  /// Sort key 1: needs-analysis float to the top.
  bool get needsAnalysis =>
      analysis == AnalysisDisplayStatus.needsAnalysis;

  /// Sort key 2: more gaps = higher attention (null gap count sorts last so an
  /// unknown isn't ranked above a known zero).
  int get gapRank => gapCount ?? -1;
}

extension on _NoteCardData {
  DateTime? parseLastEdited() =>
      lastEdited == null ? null : DateTime.tryParse(lastEdited!);
}

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

  // Enriched per-note card data, keyed by the same key used in `notes`.
  Map<String, _NoteCardData> _cardData = const {};

  // Filename of whichever note row currently has a fetch-full-note request
  // in flight, so the tapped tile can show a spinner instead of the whole
  // list looking frozen while we go get its ink.
  String? _openingFilename;

  // Selected note key (context sidebar). Null = no selection.
  String? _selectedKey;

  // Pending outbox count for the sync indicator.
  int _pendingSync = 0;
  bool _syncIndicatorLoaded = false;

  @override
  void initState() {
    super.initState();

    if (!widget.addMode && widget.bubble != null) {
      bubbleId = widget.bubble!["id"].toString();
      loadNotes(bubbleId);
      _loadSyncIndicator();
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
      final merged = local.map((n) => {...n, 'bubble_id': bubbleId}).toList();
      setState(() {
        notes = merged;
        _cardData = _buildCardData(merged);
      });
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
            l['filename'] == null || !serverFilenames.contains(l['filename']),
      );

      if (mounted) {
        final merged = [
          ...localOnly.map((n) => {...n, 'bubble_id': bubbleId}),
          ...List<Map<String, dynamic>>.from(data),
        ];
        setState(() {
          notes = merged;
          _cardData = _buildCardData(merged);
        });
        _hydrateLocalSnippets(localOnly.toList());
        _refreshOnlineFacts(merged);
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

  /// Enrich the note list into card data using ONLY local facts + cached
  /// daemon state (gap rollup). Snippet comes from each note's pages when the
  /// payload carries them (daemon list), else a cheap local first-page read.
  Map<String, _NoteCardData> _buildCardData(
    List<Map<String, dynamic>> source,
  ) {
    final out = <String, _NoteCardData>{};

    for (final n in source) {
      final noteId = n['note_id'] as String?;
      final filename = n['filename'] as String?;
      final key = filename ?? noteId ?? '${n['title']}';
      final title = (n['title'] as String?)?.trim().isNotEmpty == true
          ? n['title'].toString().trim()
          : 'Untitled';

      final localDirty = n['dirty'] == true;
      final lastEdited =
          (n['updated_at'] as String?) ??
          (n['manifest'] is Map
              ? (n['manifest'] as Map)['last_modified'] as String?
              : null) ??
          (n['last_modified'] as String?);

      // Server list payloads carry the first page's document → snippet is free.
      String snippet = '';
      final pages = (n['pages'] as List?) ?? const [];
      if (pages.isNotEmpty && pages.first is Map) {
        snippet = NoteStore.documentSnippet(
          Map<String, dynamic>.from(
            (pages.first as Map)['document'] as Map? ?? const {},
          ),
        );
      }

      AnalysisDisplayStatus analysis = AnalysisDisplayStatus.unknown;
      if (noteId == null) {
        analysis = AnalysisDisplayStatus.unknown;
      } else if (n['analyse_note'] == false) {
        analysis = AnalysisDisplayStatus.off;
      } else if (filename == null) {
        // Local-only note: can't inspect daemon state yet. Presence of a
        // server-computed analysis on disk is the honest offline signal.
        analysis = AnalysisDisplayStatus.needsAnalysis;
      } else {
        // Optimistic from what the list payload says (manifest may carry the
        // note-level overview); refined by _refreshOnlineFacts.
        final hasOverview =
            n['manifest'] is Map &&
            (n['manifest'] as Map)['overview'] != null;
        analysis = hasOverview
            ? AnalysisDisplayStatus.current
            : AnalysisDisplayStatus.needsAnalysis;
      }

      out[key] = _NoteCardData(
        noteId: noteId,
        filename: filename,
        title: title,
        snippet: snippet,
        dirty: localDirty,
        lastEdited: lastEdited,
        analysis: analysis,
        gapCount: null, // filled from the cached rollup in _loadGapCounts
      );
    }

    return out;
  }

  /// Background enrichment: per-note daemon analysis status + gap count from
  /// the cached rollup. Both degrade silently offline (the card already shows
  /// the local-first state).
  Future<void> _refreshOnlineFacts(List<Map<String, dynamic>> source) async {
    // No blocking waits — fire all status checks and apply whichever resolve.
    for (final n in source) {
      final noteId = n['note_id'] as String?;
      final filename = n['filename'] as String?;
      if (filename == null) continue;

      unawaited(_loadAnalysisStatus(noteId!, filename));
    }
    await _loadGapCounts();
  }

  Future<void> _loadAnalysisStatus(String noteId, String filename) async {
    try {
      final status = await LearningCenterApi.getAnalysisStatus(
        bubbleId: bubbleId,
        filename: filename,
      );
      if (!mounted || status == null) return;

      var changed = false;
      _cardData.forEach((k, v) {
        if (v.noteId != noteId) return;
        final AnalysisDisplayStatus next;
        if (status['exists'] == true) {
          next = status['is_current'] == true
              ? AnalysisDisplayStatus.current
              : AnalysisDisplayStatus.stale;
        } else {
          next = AnalysisDisplayStatus.needsAnalysis;
        }
        if (next != v.analysis) {
          changed = true;
          _cardData[k] = _NoteCardData(
            noteId: v.noteId,
            filename: v.filename,
            title: v.title,
            snippet: v.snippet,
            dirty: v.dirty,
            lastEdited: v.lastEdited,
            analysis: next,
            gapCount: v.gapCount,
          );
        }
      });
      if (mounted && changed) setState(() {});
    } catch (_) {
      // Offline — keep the local-first status.
    }
  }

  Future<void> _loadGapCounts() async {
    try {
      final rollup = await const LiveGapRepository().cached();
      final summary = rollup[bubbleId];
      if (summary == null || !mounted) return;

      // Per-note gap count = rollup items whose evidence points at this note.
      final byNote = <String, int>{};
      for (final item in summary.items) {
        for (final e in item.evidence) {
          byNote[e.noteId] = (byNote[e.noteId] ?? 0) + 1;
        }
      }

      _cardData = Map<String, _NoteCardData>.from(_cardData);
      _cardData.forEach((k, v) {
        final count = v.noteId == null ? null : byNote[v.noteId!];
        _cardData[k] = _NoteCardData(
          noteId: v.noteId,
          filename: v.filename,
          title: v.title,
          snippet: v.snippet,
          dirty: v.dirty,
          lastEdited: v.lastEdited,
          analysis: v.analysis,
          gapCount: count,
        );
      });
      if (mounted) setState(() {});
    } catch (_) {
      // No rollup cache yet — cards hide the gap chip rather than guessing.
    }
  }

  /// Snippet for local-only notes (no server pages in the payload): the cheap
  /// per-note disk read.
  Future<void> _hydrateLocalSnippets(List<Map<String, dynamic>> localOnly) async {
    for (final n in localOnly) {
      final noteId = n['note_id'] as String?;
      final key = n['filename'] ?? noteId;
      if (noteId == null || key == null) continue;
      if ((_cardData[key]?.snippet ?? '').isNotEmpty) continue;
      final snippet = await NoteStore.readFirstPageSnippet(bubbleId, noteId);
      if (!mounted || snippet.isEmpty) continue;
      setState(() {
        final old = _cardData[key];
        if (old == null) return;
        _cardData = Map<String, _NoteCardData>.from(_cardData)
          ..[key] = _NoteCardData(
            noteId: old.noteId,
            filename: old.filename,
            title: old.title,
            snippet: snippet,
            dirty: old.dirty,
            lastEdited: old.lastEdited,
            analysis: old.analysis,
            gapCount: old.gapCount,
          );
      });
    }
  }

  Future<void> _loadSyncIndicator() async {
    final pending = await SyncService.pendingCount();
    if (!mounted) return;
    setState(() {
      _pendingSync = pending;
      _syncIndicatorLoaded = true;
    });
  }

  /// The attention-sorted card list: needs-analysis first, then gap count
  /// desc, then recency desc.
  List<_NoteCardData> get _sortedCards {
    final list = notes
        .map((n) {
          final key = n['filename'] ?? n['note_id'] ?? '${n['title']}';
          return _cardData[key];
        })
        .whereType<_NoteCardData>()
        .toList();

    list.sort((a, b) {
      if (a.needsAnalysis != b.needsAnalysis) {
        return a.needsAnalysis ? -1 : 1;
      }
      final gapCmp = b.gapRank.compareTo(a.gapRank);
      if (gapCmp != 0) return gapCmp;
      final ta = a.parseLastEdited();
      final tb = b.parseLastEdited();
      if (ta != null && tb != null) return tb.compareTo(ta);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.title.compareTo(b.title);
    });

    return list;
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
      _loadSyncIndicator();
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
        _cardData[noteId] = _NoteCardData(
          noteId: noteId,
          filename: null,
          title: 'Untitled Note',
          snippet: '',
          dirty: true,
          lastEdited: DateTime.now().toUtc().toIso8601String(),
          analysis: AnalysisDisplayStatus.needsAnalysis,
          gapCount: null,
        );
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
          _loadSyncIndicator();
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
    _loadSyncIndicator();
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

    final cards = _sortedCards;
    final selected = _selectedKey == null ? null : _cardData[_selectedKey];

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      // Always at least the add-note tile; the empty state
                      // rides below it so "no notes yet" never hides the
                      // way to create one.
                      itemCount: 1 + (notes.isEmpty ? 1 : cards.length),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _AddNoteTile(onTap: addNote);
                        }
                        if (notes.isEmpty) {
                          return const _EmptyNotes();
                        }
                        final data = cards[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: NoteCardView(
                            data: {
                              'title': data.title,
                              'snippet': data.snippet,
                            },
                            accentColor: _ringColor(data),
                            analysis: data.analysis,
                            gapCount: data.gapCount,
                            lastEdited: data.lastEdited,
                            isSelected: data.key == _selectedKey,
                            isOpening: _openingFilename == data.key,
                            onTap: () => _selectNote(data.key),
                            onOpen: () {
                              final note = notes.firstWhere(
                                (n) =>
                                    (n['filename'] ?? n['note_id']) ==
                                    data.key,
                                orElse: () => const {},
                              );
                              if (note.isNotEmpty) _openNote(note);
                            },
                            onDelete: () => _confirmDelete(data),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // RIGHT: context sidebar — updates on selection.
          Container(
            width: 400,
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: _ContextSidebar(
              bubble: widget.bubble,
              selected: selected,
              bubbleId: bubbleId,
              onOpen: selected == null
                  ? null
                  : () {
                      final note = notes.firstWhere(
                        (n) => (n['filename'] ?? n['note_id']) == selected.key,
                        orElse: () => const {},
                      );
                      if (note.isNotEmpty) _openNote(note);
                    },
              onDelete: selected == null ? null : () => _confirmDelete(selected),
              onRunAnalysis: selected == null || selected.filename == null
                  ? null
                  : () => _runAnalysis(selected),
              onBack: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.bubble?['name'] ?? "No name",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _SyncIndicator(
            pending: _pendingSync,
            loaded: _syncIndicatorLoaded,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: "Back to Study Bubbles",
            onPressed: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _selectNote(String key) {
    setState(() {
      if (_selectedKey == key) {
        _selectedKey = null; // toggle off
      } else {
        _selectedKey = key;
      }
    });
  }

  Future<void> _runAnalysis(_NoteCardData data) async {
    final filename = data.filename;
    if (filename == null) return;
    try {
      final result = await LearningCenterApi.runActiveAnalysis(
        bubbleId: bubbleId,
        filename: filename,
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Analysis generated")),
        );
      }
      await loadNotes(bubbleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to run analysis: $e")));
      }
    }
  }

  Future<void> _confirmDelete(_NoteCardData data) async {
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
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text("Cancel"),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await deleteNote(
        bubbleId,
        data.filename,
        noteId: data.noteId,
      );
      if (mounted && _selectedKey == data.key) {
        setState(() => _selectedKey = null);
      }
    }
  }

  /// Attention rail: needs-analysis → red (the loudest signal), stale → amber,
  /// gap-heavy current notes → amber, else neutral.
  Color _ringColor(_NoteCardData data) {
    switch (data.analysis) {
      case AnalysisDisplayStatus.needsAnalysis:
        return const Color(0xFFB3261E);
      case AnalysisDisplayStatus.stale:
        return const Color(0xFFC9A24B);
      case AnalysisDisplayStatus.current:
      case AnalysisDisplayStatus.off:
      case AnalysisDisplayStatus.unknown:
        break;
    }
    final gaps = data.gapCount;
    if (gaps != null && gaps > 3) return const Color(0xFFC9A24B);
    return const Color(0xFFB9B4CC);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }
}

/// The "Add New Note" tile: the first item in the notes list. A one-tap
/// affordance that replaces the FAB — it lives with the content it creates,
/// stays visible above the empty state, and reads like a new-note card rather
/// than a floating action.
class _AddNoteTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddNoteTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF4F2F8),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: Color(0xFF2B5BD7)),
                SizedBox(width: 10),
                Text(
                  "Add New Note",
                  style: TextStyle(
                    color: Color(0xFF2B5BD7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notes, size: 48, color: Color(0xFFB9B4CC)),
          const SizedBox(height: 12),
          const Text(
            'No notes yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Use "Add New Note" above to create your first note.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Header chip: shows pending outbox work when present, a synced check once
/// loaded with nothing queued, and nothing while undiscovered.
class _SyncIndicator extends StatelessWidget {
  final int pending;
  final bool loaded;

  const _SyncIndicator({required this.pending, required this.loaded});

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const SizedBox.shrink();

    final pendingNow = pending > 0;
    final color = pendingNow ? const Color(0xFFC9A24B) : const Color(0xFF2E7D32);
    final icon = pendingNow ? Icons.cloud_upload_outlined : Icons.cloud_done;

    return Tooltip(
      message: pendingNow
          ? '$pending change${pending == 1 ? '' : 's'} waiting to sync'
          : 'All changes synced',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (pendingNow) ...[
            const SizedBox(width: 4),
            Text(
              '$pending',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
/// The context sidebar's right pane — analysis status for the selected note
/// plus quick actions. Updates on every selection; never static.
class _ContextSidebar extends StatelessWidget {
  final Map<String, dynamic>? bubble;
  final _NoteCardData? selected;
  final String bubbleId;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRunAnalysis;
  final VoidCallback? onBack;

  const _ContextSidebar({
    required this.bubble,
    required this.selected,
    required this.bubbleId,
    required this.onOpen,
    required this.onDelete,
    required this.onRunAnalysis,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              tooltip: "Back to Study Bubbles",
              onPressed: onBack,
            ),
            Icon(Icons.bubble_chart, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                bubble?['name'] ?? "No name",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          bubble?['description'] ?? "No description yet.",
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        const SizedBox(height: 20),
        const Divider(color: Colors.white24),
        const SizedBox(height: 12),
        if (selected == null)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.white38, size: 40),
                  SizedBox(height: 8),
                  Text(
                    'Select a note to see its analysis',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          _SelectedSummary(
            title: selected!.title,
            analysis: selected!.analysis,
            gapCount: selected!.gapCount,
            snippet: selected!.snippet,
            onOpen: onOpen,
            onDelete: onDelete,
            onRunAnalysis: onRunAnalysis,
          ),
      ],
    );
  }
}

/// A selected note's analysis status line + quick actions. Render-only: all
/// facts are passed in by the page, so labels can never drift from the state
/// the card list displays.
class _SelectedSummary extends StatelessWidget {
  final String title;
  final AnalysisDisplayStatus analysis;
  final int? gapCount;
  final String snippet;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRunAnalysis;

  const _SelectedSummary({
    required this.title,
    required this.analysis,
    required this.gapCount,
    required this.snippet,
    required this.onOpen,
    required this.onDelete,
    required this.onRunAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    final showAnalyze =
        analysis == AnalysisDisplayStatus.needsAnalysis ||
        analysis == AnalysisDisplayStatus.stale;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (snippet.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              snippet,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatusLine(),
              if (gapCount != null) ...[
                const SizedBox(width: 4),
                Text(
                  '· $gapCount ${gapCount == 1 ? 'gap' : 'gaps'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
              ),
              if (showAnalyze && onRunAnalysis != null)
                OutlinedButton.icon(
                  onPressed: onRunAnalysis,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Run analysis'),
                ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Tip: pick a note to see it here. Double-click a card opens it.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine() {
    final (label, color) = switch (analysis) {
      AnalysisDisplayStatus.current => ('Analyzed', const Color(0xFF81C784)),
      AnalysisDisplayStatus.stale => ('Stale analysis', const Color(0xFFC9A24B)),
      AnalysisDisplayStatus.needsAnalysis => (
        'Needs analysis',
        const Color(0xFFEF9A9A),
      ),
      AnalysisDisplayStatus.off => ('Analysis off', const Color(0xFFBDBDBD)),
      AnalysisDisplayStatus.unknown => (
        'Analysis unavailable offline',
        const Color(0xFFBDBDBD),
      ),
    };
    return Text(label, style: TextStyle(color: color, fontSize: 13));
  }
}
