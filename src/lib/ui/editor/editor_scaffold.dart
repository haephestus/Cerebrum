import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/id.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/sync_service.dart';
import 'package:cerebrum/ui/editor/blocks/image/note_image_resolver.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:cerebrum/ui/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/editor/controllers/analysis_mode_controller.dart';
import 'package:cerebrum/ui/editor/controllers/text_editing_driver.dart';
import 'package:cerebrum/ui/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/editor/screens/paged_editor.dart';
import 'package:cerebrum/ui/editor/screens/radial_tool_dial.dart';

enum _TextEngine { appFlowy, superEditor }

/// Everything that surrounds the editor: note loading/saving, autosave
/// scheduling, the analysis panel + its API calls, the app bar, and the
/// save FAB. This class only ever talks to the editor through
/// [NoteEditorController], which itself only talks to [TextEditingDriver]
/// — the AppFlowy/super_editor switch in the app bar below swaps the
/// driver at runtime without this class needing to know either engine
/// exists.
class EditorScaffold extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? initialTextJson;
  final List<Map<String, dynamic>>? initialInkJson;

  const EditorScaffold({
    super.key,
    required this.note,
    this.initialTextJson,
    this.initialInkJson,
  });

  @override
  State<EditorScaffold> createState() => _EditorScaffoldState();
}

class _EditorScaffoldState extends State<EditorScaffold> {
  late final PagedNoteController _editorController;
  _TextEngine _currentEngine = _TextEngine.appFlowy;

  // Captured ONCE at open from the note map, and used for every request instead
  // of re-reading widget.note['bubble_id'] each time. The daemon's note response
  // carries an EMPTY bubble_id (it's a computed field off manifest.bubble_id,
  // which the note manifest doesn't persist), and `_save` merges that response
  // back into widget.note — which would otherwise clobber the good bubble_id and
  // send later saves to `/bubbles//notes/update/...` (404). This stable copy is
  // immune to that clobber.
  String? _bubbleId;

  /// Eraser mode, shared by the tool wheel (which toggles it) and every page's
  /// ink layer (which reads it). Lives here so the choice is global across pages.
  /// Defaults to partial (split) erase — the mode we built for note-taking.
  final ValueNotifier<bool> _partialEraser = ValueNotifier(true);

  /// Eraser diameter (logical px), shared by the tool wheel (which sizes it from
  /// its size selector) and every page's ink layer (which erases by it). Lives
  /// here so the choice is global across pages. Seeded from the persisted
  /// [EditorSettings.eraserWidth] default; the wheel pushes the loaded value
  /// once its settings load.
  final ValueNotifier<double> _eraserWidth = ValueNotifier(24);

  /// SCAFFOLD — drives the vim "analysis" review mode: step through analysis
  /// chunks, or open the full panel. Fed from [_analysisChunks] on load; the
  /// per-chunk highlight/scroll is still a TODO inside the controller.
  final AnalysisModeController _analysisMode = AnalysisModeController();

  // App-session default for which mode a note opens in. Lives only for
  // the lifetime of the app process — flip it from the "More" menu and
  // it applies to the next note you open. If you want it to survive an
  // app relaunch, persist this alongside your other user settings
  // (shared_preferences, or a user-settings API call) instead of a
  // static field.
  static bool _defaultStartInDrawingMode = false;

  Timer? _debounce;
  bool _isSaving = false;
  String _lastSavedState = '';

  String? _cachedAnalysis; // used only for error/empty/regenerate-raw messages
  Map<String, dynamic>? _analysisData; // raw /fetch/analysis/full payload

  /// The raw analysis payload, in case something outside the panel UI
  /// (debugging, a future detail view, etc.) needs it. Not read anywhere
  /// in this file itself — [_overviewMarkdown]/[_analysisChunks]/
  /// [_cachedAnalysis] are the derived views the panel actually renders.
  Map<String, dynamic>? get analysisData => _analysisData;
  String?
  _overviewMarkdown; // formatted note_overview, rendered once above the list
  List<Map<String, dynamic>> _analysisChunks =
      []; // flattened + numerically sorted

  /// pageId → (stable block id → the analysis chunks covering it). Built from
  /// `_analysisChunks` (each chunk carries `pageId` + `blockIds`, the daemon's
  /// `source_block_ids`). Keyed by stable id, not position, so the mapping
  /// survives edits/reorders. Drives the inline per-block popover — see
  /// PageSurface.
  Map<String, Map<String, List<Map<String, dynamic>>>> _blockAnalysis = {};
  bool _hasAttemptedLoad =
      false; // did we already try loading, vs. just toggling the panel
  bool _isLoadingAnalysis = false;
  bool _showAnalysisPanel = false;
  bool _isGeneratingAnalysis = false;

  late bool _analysisEnabled;
  bool _isTogglingAnalysis = false;

  String? _noteIdFromFilename(String? filename) {
    if (filename == null || filename.isEmpty) return null;
    return filename.endsWith('.json')
        ? filename.substring(0, filename.length - 5)
        : filename;
  }

  @override
  void initState() {
    super.initState();

    final rawFilename = widget.note['filename'];
    final parsedNoteId = _noteIdFromFilename(rawFilename as String?);
    _bubbleId = widget.note['bubble_id'] as String?;
    debugPrint(
      '[EditorScaffold] Opening note. filename="$rawFilename" '
      'noteId="$parsedNoteId"',
    );

    // Seed the toggle from the note payload (backend field: analyse_note).
    _analysisEnabled = widget.note['analyse_note'] as bool? ?? true;

    // "Opt to see the full analysis" from analysis-review mode → open the panel
    // (loading it first if we haven't yet).
    _analysisMode.onOpenFullPanel = () {
      if (!_hasAttemptedLoad) {
        _loadAnalysis();
      } else {
        setState(() => _showAnalysisPanel = true);
      }
    };

    final contentData =
        widget.initialTextJson ??
        widget.note['content'] as Map<String, dynamic>?;
    final docJson = contentData?['document'] as Map<String, dynamic>?;

    final inkJson =
        widget.initialInkJson ??
        (widget.note['ink'] != null
            ? List<Map<String, dynamic>>.from(widget.note['ink'])
            : null);

    // TEMP DEBUG — remove once the ink-loading issue is confirmed/fixed.
    debugPrint(
      '[EditorScaffold] widget.note has "ink" key: '
      '${widget.note.containsKey('ink')}, '
      'inkJson length: ${inkJson?.length}, '
      'first-elem keys: ${inkJson?.firstOrNull?.keys.toList()}',
    );

    // Ensure the note has a client-owned id up front, so images can be cached
    // locally (and the note can persist) before the daemon ever assigns a
    // filename.
    final noteId =
        (widget.note['note_id'] as String?) ??
        parsedNoteId ??
        Ulid.generate();
    widget.note['note_id'] = noteId;

    // Prime the image resolver for this note (local cache paths + recorded
    // daemon URLs). The open path awaits this before navigating; this refresh
    // covers notes opened another way.
    final bid = _bubbleId;
    if (bid != null && bid.isNotEmpty) {
      NoteImageResolver.configureForNote(bubbleId: bid, noteId: noteId);
    }

    // Loaded documents hold stable `cerebrum-image://` refs; swap them for
    // loadable display values (local file path, else daemon URL) before the
    // editor renders. `resolve` leaves legacy absolute URLs untouched.
    final rawPages =
        widget.note['pages'] != null
            ? List<Map<String, dynamic>>.from(widget.note['pages'])
            : null;
    final loadedPages =
        rawPages == null
            ? null
            : NoteImageResolver.mapPagesUrls(rawPages, NoteImageResolver.resolve);

    _editorController = PagedNoteController.fromNote(
      pages: loadedPages,
      legacyDocument: docJson,
      legacyInk: inkJson,
    );
    _editorController.addListener(_onEditorChanged);

    // Image uploads target this note's folder on the daemon. Reads filename
    // dynamically (not captured) so it also works after a brand-new note gets
    // its filename on first save.
    _editorController.imageUploader = (bytes, name) async {
      final bubbleId = _bubbleId;
      if (bubbleId == null || bubbleId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Save the note before adding images.')),
          );
        }
        return null;
      }
      final nId = widget.note['note_id'] as String;
      final ext = name.contains('.') ? name.split('.').last : 'png';
      final imageName = '${Ulid.generate()}.$ext';
      try {
        // Cache the bytes locally FIRST (works offline), then queue the upload.
        // We hand the editor the local file path to render now; on save the doc
        // stores a stable `cerebrum-image://` ref (see NoteImageResolver.toRef).
        final file = await NoteStore.writeImage(
          bubbleId,
          nId,
          imageName,
          bytes,
        );
        NoteImageResolver.noteLocalImage(imageName);
        await SyncService.queueImageUpload(
          bubbleId: bubbleId,
          noteId: nId,
          name: imageName,
        );
        return file.path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Image save failed: $e')));
        }
        return null;
      }
    };

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateLastSavedState(),
    );
  }

  void _onEditorChanged() {
    // Autosave scheduling needs to run on every driver change, no matter
    // what. UI that reacts to every keystroke — the save indicator, the
    // drawing-mode icon — used to be refreshed via a blanket
    // `setState(() {})` here, which rebuilt the ENTIRE scaffold (app
    // bar, analysis panel, everything) on every single character typed.
    // That's now scoped to just those two widgets via their own
    // `AnimatedBuilder(animation: _editorController, ...)` down in
    // build() instead, so a keystroke no longer forces the whole
    // scaffold — including the AppFlowyEditor subtree one level down —
    // through a rebuild on top of AppFlowyEditor's own internal
    // focus/selection handling for that same keystroke.
    _scheduleSave();
  }

  String _serializedEditorState() =>
      jsonEncode(_editorController.toPagesJson());

  void _updateLastSavedState() {
    _lastSavedState = _serializedEditorState();
  }

  bool _hasUnsavedChanges() => _serializedEditorState() != _lastSavedState;

  void _scheduleSave() {
    if (!_hasUnsavedChanges()) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (_isSaving || !_hasUnsavedChanges()) return;

    final bubbleId = _bubbleId;
    if (bubbleId == null || bubbleId.isEmpty) {
      // Without a bubble id the URL is `/bubbles//notes/update/...` (404). Don't
      // hammer the daemon every autosave tick — bail quietly.
      debugPrint('[EditorScaffold] skipping save: missing bubble_id');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final filename = widget.note['filename'] as String?;
      final title = widget.note['title'] ?? 'Untitled';

      // Client-owned note id, so the note can persist locally before the daemon
      // ever assigns it a filename. Minted in initState; kept here as a guard.
      var noteId =
          widget.note['note_id'] as String? ?? _noteIdFromFilename(filename);
      if (noteId == null || noteId.isEmpty) {
        noteId = Ulid.generate();
        widget.note['note_id'] = noteId;
      }

      // The live doc holds loadable image srcs (local file paths / URLs); the
      // persisted + pushed copy stores stable `cerebrum-image://` refs instead,
      // so it survives base-URL changes and offline reloads.
      final pages = NoteImageResolver.mapPagesUrls(
        _editorController.toPagesJson(),
        NoteImageResolver.toRef,
      );

      // 1) Local write FIRST — always succeeds, offline or not. This is the
      // never-lose-a-write guarantee: the edit is durable before we ever touch
      // the network.
      await NoteStore.writeNote(
        bubbleId: bubbleId,
        noteId: noteId,
        manifest: {
          'title': title,
          'filename': filename,
          'note_id': noteId,
          'bubble_id': bubbleId,
          'analyse_note': _analysisEnabled,
          if (widget.note['version'] != null) 'version': widget.note['version'],
        },
        pages: pages,
      );
      await NoteStore.markDirty(bubbleId, noteId);
      // The local copy is saved, so from the user's POV the note is saved.
      _updateLastSavedState();

      // 2) Best-effort push through the outbox. Reconciles per page_id on the
      // daemon (edits + adds + deletes, LWW); queued for retry if we're offline.
      // On success SyncService persists the server-merged copy locally + clears
      // the dirty flag, so we just adopt the merged fields into the live map.
      final merged = await SyncService.queueSave(
        bubbleId: bubbleId,
        noteId: noteId,
        title: title,
        pages: pages,
        filename: filename,
        analyseNote: _analysisEnabled,
      );
      if (merged != null) {
        widget.note.addAll(merged);
        // The daemon echoes an empty bubble_id — keep the real one in the map so
        // anything still reading widget.note (and our own re-reads) stays valid.
        widget.note['bubble_id'] = bubbleId;
        widget.note['note_id'] = noteId;
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleAnalysis(bool newValue) async {
    final bubbleId = _bubbleId;
    final filename = widget.note['filename'] as String?;

    if (bubbleId == null || filename == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save the note before changing analysis settings'),
          ),
        );
      }
      return;
    }

    // Optimistically flip the UI, then reconcile with the server response.
    setState(() {
      _analysisEnabled = newValue;
      _isTogglingAnalysis = true;
    });

    try {
      final result = await BubbleNotesApi.toggleNoteAnalysis(
        bubbleId,
        filename,
      );

      widget.note.addAll(result);

      setState(() {
        _analysisEnabled = result['analyse_note'] as bool? ?? _analysisEnabled;
        _isTogglingAnalysis = false;
      });
    } catch (e) {
      setState(() {
        _analysisEnabled = !newValue;
        _isTogglingAnalysis = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update analysis setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadAnalysis() async {
    final bubbleId = _bubbleId;
    final noteId = _noteIdFromFilename(widget.note['filename'] as String?);
    final version = widget.note["version"];

    if (bubbleId == null || noteId == null) return;

    setState(() => _isLoadingAnalysis = true);

    try {
      final full = await LearningCenterApi.getFullCachedAnalysis(
        bubbleId: bubbleId,
        noteId: noteId,
        currentVersion: version is num ? version.toDouble() : null,
      );

      setState(() {
        _hasAttemptedLoad = true;
        if (full != null) {
          _analysisData = full;
          _overviewMarkdown = _formatOverviewMarkdown(full);
          _analysisChunks = _flattenAndSortChunks(
            full['chunk_diagnostics'] as List<dynamic>? ?? [],
          );
          _rebuildBlockAnalysis();
          _rebuildAnalysisModeChunks();
          _cachedAnalysis = null;
        } else {
          _analysisData = null;
          _overviewMarkdown = null;
          _analysisChunks = [];
          _blockAnalysis = {};
          _cachedAnalysis = 'No cached analysis found for this note.';
        }
        _showAnalysisPanel = true;
        _isLoadingAnalysis = false;
      });
    } catch (e) {
      setState(() {
        _hasAttemptedLoad = true;
        _analysisData = null;
        _overviewMarkdown = null;
        _analysisChunks = [];
        _blockAnalysis = {};
        _cachedAnalysis = 'Error loading analysis:\n$e';
        _showAnalysisPanel = true;
        _isLoadingAnalysis = false;
      });
    }
  }

  // Formats just the note-level overview (topic, mastery, concept map,
  // priority study order, suggested sources) as markdown. Chunk-level
  // findings are rendered separately as widgets, not text — see
  // _flattenAndSortChunks and _ChunkExpansionTile below.
  String _formatOverviewMarkdown(Map<String, dynamic> data) {
    final buffer = StringBuffer();

    if (data['is_current'] == false && data['cached_version'] != null) {
      buffer.writeln(
        '> ⚠️ Showing cached analysis from **v${data['cached_version']}** '
        '— this may be out of date.',
      );
      buffer.writeln();
    }

    final overview = data['note_overview'] as Map<String, dynamic>?;
    if (overview == null) return buffer.toString();

    buffer.writeln('## ${overview['topic'] ?? 'Overview'}');
    buffer.writeln();
    if (overview['mastery_signal'] != null) {
      buffer.writeln(
        '**Mastery:** ${overview['mastery_signal']} '
        '(${overview['progress_delta'] ?? 'n/a'})',
      );
      buffer.writeln();
    }

    final conceptMap = overview['concept_map'] as Map<String, dynamic>?;
    if (conceptMap != null) {
      final strong = conceptMap['strong_areas'] as List<dynamic>? ?? [];
      final weak = conceptMap['weak_areas'] as List<dynamic>? ?? [];
      final confused = conceptMap['confused_links'] as List<dynamic>? ?? [];

      if (strong.isNotEmpty) {
        buffer.writeln('**Strong areas:**');
        for (final s in strong) buffer.writeln('- $s');
        buffer.writeln();
      }
      if (weak.isNotEmpty) {
        buffer.writeln('**Weak areas:**');
        for (final w in weak) buffer.writeln('- $w');
        buffer.writeln();
      }
      if (confused.isNotEmpty) {
        buffer.writeln('**Confused concepts:**');
        for (final c in confused) {
          final cm = c as Map<String, dynamic>;
          buffer.writeln(
            '- *${cm['concept_a']}* vs *${cm['concept_b']}*: ${cm['confusion_description']}',
          );
        }
        buffer.writeln();
      }
    }

    final gaps = overview['knowledge_gaps_summary'] as List<dynamic>? ?? [];
    if (gaps.isNotEmpty) {
      buffer.writeln('**Knowledge gaps:**');
      for (final g in gaps) buffer.writeln('- $g');
      buffer.writeln();
    }

    final priority = overview['priority_study_areas'] as List<dynamic>? ?? [];
    if (priority.isNotEmpty) {
      buffer.writeln('**Priority study order:**');
      for (final p in priority) buffer.writeln('1. $p');
      buffer.writeln();
    }

    final sources = overview['suggested_sources'] as List<dynamic>? ?? [];
    if (sources.isNotEmpty) {
      buffer.writeln('**Suggested reading:**');
      for (final s in sources) {
        final sm = s as Map<String, dynamic>;
        buffer.writeln('- *${sm['title']}* — ${sm['reason']}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  // Flattens the nested chunk_diagnostics payload into one list per finding
  // group, and sorts NUMERICALLY by the index embedded in chunk_id (e.g.
  // "chunk_2" before "chunk_10") — the raw glob().sort() on the backend is
  // a lexicographic string sort and gets this wrong past chunk_9.
  List<Map<String, dynamic>> _flattenAndSortChunks(List<dynamic> rawChunks) {
    final flattened = <Map<String, dynamic>>[];

    for (final outer in rawChunks) {
      final outerMap = outer as Map<String, dynamic>;
      final diagnostics = outerMap['chunk_diagnostics'] as List<dynamic>? ?? [];

      for (final diag in diagnostics) {
        final d = diag as Map<String, dynamic>;
        final chunkId = (d['chunk_id'] ?? 'chunk').toString();
        final match = RegExp(r'(\d+)').firstMatch(chunkId);
        final chunkIndex = match != null ? int.parse(match.group(1)!) : 1 << 30;

        // Block linkage (added daemon-side): which page + which blocks this
        // chunk's analysis covers. `source_block_ids` are STABLE block ids
        // (AppFlowy node ids, or content-hash ids for id-less blocks) — keep
        // them as-is; they key the per-block popover directly.
        final pageId = outerMap['page_id'] as String?;
        final blockIds = (outerMap['source_block_ids'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();

        flattened.add({
          'chunkId': chunkId,
          'chunkIndex': chunkIndex,
          'excerpt': d['chunk_excerpt'] as String?,
          'findings': d['findings'] as List<dynamic>? ?? [],
          'pageId': pageId,
          'blockIds': blockIds,
        });
      }
    }

    flattened.sort(
      (a, b) => (a['chunkIndex'] as int).compareTo(b['chunkIndex'] as int),
    );
    return flattened;
  }

  /// Analysis chunks covering the block with id [blockId] on page [pageId], or
  /// null. Passed to PagedEditor as the inline-popover lookup while the panel is
  /// open.
  List<Map<String, dynamic>>? _lookupBlockAnalysis(
    String pageId,
    String blockId,
  ) =>
      _blockAnalysis[pageId]?[blockId];

  /// Feed the flattened chunks to the analysis-review controller (SCAFFOLD).
  /// Only chunks that actually map to a page/blocks are navigable.
  void _rebuildAnalysisModeChunks() {
    final refs = <AnalysisChunkRef>[
      for (final chunk in _analysisChunks)
        if ((chunk['pageId'] as String?)?.isNotEmpty ?? false)
          AnalysisChunkRef(
            chunkId: (chunk['chunkId'] ?? '').toString(),
            pageId: chunk['pageId'] as String,
            blockIds: (chunk['blockIds'] as List?)?.cast<String>() ?? const [],
            chunk: chunk,
          ),
    ];
    _analysisMode.setChunks(refs);
  }

  /// Rebuild the pageId → blockId → chunks lookup from `_analysisChunks`.
  void _rebuildBlockAnalysis() {
    final map = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final chunk in _analysisChunks) {
      final pageId = chunk['pageId'] as String?;
      if (pageId == null) continue;
      final blockIds =
          (chunk['blockIds'] as List?)?.cast<String>() ?? const [];
      final perPage = map.putIfAbsent(pageId, () => {});
      for (final blockId in blockIds) {
        perPage.putIfAbsent(blockId, () => []).add(chunk);
      }
    }
    _blockAnalysis = map;
  }

  Future<void> _generateAnalysis() async {
    final bubbleId = _bubbleId;
    final filename = widget.note['filename'] as String?;

    if (bubbleId == null || filename == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot generate analysis: Note not saved yet'),
          ),
        );
      }
      return;
    }

    setState(() => _isGeneratingAnalysis = true);

    try {
      final analysis = await LearningCenterApi.runActiveAnalysis(
        bubbleId: bubbleId,
        filename: filename,
      );

      setState(() {
        // runActiveAnalysis returns raw text, not the structured
        // chunk_diagnostics/note_overview payload — show it as a plain
        // message until the next _loadAnalysis() call repopulates the
        // structured view from the cache.
        _analysisData = null;
        _overviewMarkdown = null;
        _analysisChunks = [];
        _blockAnalysis = {};
        _cachedAnalysis =
            analysis ?? 'Analysis generated but no content returned.';
        _hasAttemptedLoad = true;
        _showAnalysisPanel = true;
        _isGeneratingAnalysis = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Analysis generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _analysisData = null;
        _overviewMarkdown = null;
        _analysisChunks = [];
        _blockAnalysis = {};
        _cachedAnalysis = 'Error generating analysis:\n$e';
        _hasAttemptedLoad = true;
        _showAnalysisPanel = true;
        _isGeneratingAnalysis = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate analysis: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Whether the current driver has vim-style modal editing at all —
  /// not every engine implements [VimModeAware] (see
  /// text_editing_driver.dart), so the menu item below disables itself
  /// rather than toggling something that doesn't exist.
  bool get _vimModeAvailable =>
      _editorController.activeController.driver is VimModeAware;

  bool get _vimModeEnabled {
    final driver = _editorController.activeController.driver;
    if (driver is! VimModeAware) return false;
    return (driver as VimModeAware).vimMode.isEnabled;
  }

  void _toggleVimMode() {
    final driver = _editorController.activeController.driver;
    if (driver is! VimModeAware) return;
    final vimAware = driver as VimModeAware;
    vimAware.vimMode.setEnabled(!vimAware.vimMode.isEnabled);
    // vimMode notifies its own listeners, which _onEditorChanged is
    // already wired to (driver -> controller -> this widget), so no
    // separate setState is strictly required — but this menu is
    // rebuilt from scratch on open each time anyway.
  }

  /// Enter analysis-review mode on the active page's driver (SCAFFOLD). Loads
  /// the analysis first if we haven't yet, so there are chunks to step through.
  void _enterAnalysisMode() {
    final driver = _editorController.activeController.driver;
    if (driver is! VimModeAware) return;
    if (!_hasAttemptedLoad) _loadAnalysis();
    (driver as VimModeAware).vimMode.enterAnalysisMode();
  }

  /// SCAFFOLD toolbar shown while any page is in analysis-review mode: step
  /// through chunks (◀ ▶) or open the full panel. The actual chunk highlight /
  /// scroll is [AnalysisModeController.onFocusChunk] — still a TODO.
  Widget _analysisModeBar() {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, _) {
        final driver = _editorController.activeController.driver;
        if (driver is! VimModeAware) return const SizedBox.shrink();
        final vimMode = (driver as VimModeAware).vimMode;
        return AnimatedBuilder(
          animation: vimMode,
          builder: (context, __) {
            if (!vimMode.isAnalysis) return const SizedBox.shrink();
            return AnimatedBuilder(
              animation: _analysisMode,
              builder: (context, ___) {
                final cur = _analysisMode.current;
                final label = cur == null
                    ? 'No analysis chunks'
                    : 'Chunk ${_analysisMode.index + 1} / ${_analysisMode.count}';
                return Material(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left,
                              color: Colors.white),
                          onPressed:
                              _analysisMode.hasChunks ? _analysisMode.prev : null,
                        ),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right,
                              color: Colors.white),
                          onPressed:
                              _analysisMode.hasChunks ? _analysisMode.next : null,
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _analysisMode.openFullPanel,
                          child: const Text('Full analysis',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// The vim NORMAL/INSERT badge (lives in the app bar). Collapses to nothing
  /// when drawing, for non-vim engines, or when vim is disabled.
  ///
  /// Why TWO nested AnimatedBuilders: vim mode is PER-PAGE (each page's driver
  /// owns its own VimModeController), so the badge has to watch two different
  /// things. The OUTER one listens to the controller and fires when the ACTIVE
  /// page changes — that's what re-points the badge at the new page's vimMode
  /// (a single builder bound to one page's mode would go stale the moment you
  /// switch pages). The INNER one listens to that resolved vimMode and fires when
  /// the mode value itself flips (i / Esc). Neither alone is enough.
  Widget _vimModeBadge() {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, _) {
        final driver = _editorController.activeController.driver;
        if (_editorController.drawingEnabled || driver is! VimModeAware) {
          return const SizedBox.shrink();
        }
        final vimMode = (driver as VimModeAware).vimMode;
        return AnimatedBuilder(
          animation: vimMode,
          builder: (context, __) {
            if (!vimMode.isEnabled) return const SizedBox.shrink();
            final (label, color) = switch (vimMode.value) {
              VimMode.normal => ('NORMAL', Colors.blueGrey),
              VimMode.insert => ('INSERT', Colors.teal),
              VimMode.analysis => ('ANALYSIS', Colors.deepPurple),
            };
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _switchEngine(_TextEngine engine) {
    if (engine == _currentEngine) return;

    final TextEditingDriver newDriver;
    switch (engine) {
      case _TextEngine.appFlowy:
        // Reuse whatever content the previous driver reports, so
        // switching back to AppFlowy after testing doesn't lose it.
        newDriver = AppFlowyTextDriver(
          initialDocumentJson: _editorController.activeController.documentJson,
        );
        break;
      case _TextEngine.superEditor:
        // newDriver = SuperEditorTextDriver();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'super_editor is a testing engine — content typed here '
                "won't be saved until its serializer is finished.",
              ),
            ),
          );
        }
        break;
    }

    setState(() {
      _currentEngine = engine;
      // _editorController.switchDriver(newDriver);
    });
  }

  @override
  void dispose() {
    _editorController.removeListener(_onEditorChanged);
    _editorController.dispose();
    _partialEraser.dispose();
    _eraserWidth.dispose();
    _analysisMode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note['title'] ?? 'Edit Note'),
        actions: [
          // Vim mode indicator, in the app bar (Center → vertically aligned).
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _vimModeBadge(),
            ),
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_isGeneratingAnalysis)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),

          // The primary mode switch: which view of this note you're
          // looking at. Replaces the old bare analytics IconButton — same
          // load-on-first-open / toggle-after behavior, just legible.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Note')),
                ButtonSegment(value: true, label: Text('Analysis')),
              ],
              selected: {_showAnalysisPanel},
              onSelectionChanged:
                  _isLoadingAnalysis
                      ? null
                      : (selection) {
                        final wantsAnalysis = selection.first;
                        if (wantsAnalysis && !_hasAttemptedLoad) {
                          _loadAnalysis();
                        } else {
                          setState(() => _showAnalysisPanel = wantsAnalysis);
                        }
                      },
            ),
          ),

          AnimatedBuilder(
            animation: _editorController,
            builder: (context, _) {
              final drawingEnabled = _editorController.drawingEnabled;
              return IconButton(
                icon: Icon(drawingEnabled ? Icons.brush : Icons.text_fields),
                tooltip:
                    drawingEnabled
                        ? 'Switch to text mode'
                        : 'Switch to drawing mode',
                onPressed: () {
                  _editorController.toggleDrawingMode();
                  if (_editorController.drawingEnabled) {
                    FocusScope.of(context).unfocus();
                  }
                },
              );
            },
          ),

          // Page layout: vertical scroll (default) ↔ horizontal slideshow.
          AnimatedBuilder(
            animation: _editorController,
            builder: (context, _) {
              final horizontal =
                  _editorController.layout == PageLayoutMode.horizontal;
              return IconButton(
                icon: Icon(horizontal ? Icons.view_carousel : Icons.view_day),
                tooltip:
                    horizontal
                        ? 'Pages: slideshow (tap for scroll)'
                        : 'Pages: scroll (tap for slideshow)',
                onPressed: _editorController.toggleLayout,
              );
            },
          ),


          // Secondary, settings-style actions that don't need to be
          // permanently visible: whether analysis runs for this note at
          // all (distinct from just viewing the panel above), and the
          // editing-engine switch, which is a testing tool, not a
          // day-to-day control.
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'toggle_analysis_enabled':
                  _toggleAnalysis(!_analysisEnabled);
                  break;
                case 'engine_appFlowy':
                  _switchEngine(_TextEngine.appFlowy);
                  break;
                case 'engine_superEditor':
                  _switchEngine(_TextEngine.superEditor);
                  break;
                case 'default_start_in_drawing_mode':
                  setState(
                    () =>
                        _defaultStartInDrawingMode =
                            !_defaultStartInDrawingMode,
                  );
                  break;
                case 'toggle_vim_mode':
                  setState(_toggleVimMode);
                  break;
                case 'enter_analysis_mode':
                  _enterAnalysisMode();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  CheckedPopupMenuItem<String>(
                    value: 'toggle_analysis_enabled',
                    checked: _analysisEnabled,
                    enabled: !_isTogglingAnalysis,
                    child: const Text('Analysis enabled for this note'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'engine_appFlowy',
                    child: Row(
                      children: [
                        Icon(
                          _currentEngine == _TextEngine.appFlowy
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Editing engine: AppFlowy'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'engine_superEditor',
                    child: Row(
                      children: [
                        Icon(
                          _currentEngine == _TextEngine.superEditor
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Editing engine: super_editor (testing)'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem<String>(
                    value: 'default_start_in_drawing_mode',
                    checked: _defaultStartInDrawingMode,
                    child: const Text('Open new notes in drawing mode'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'toggle_vim_mode',
                    checked: _vimModeEnabled,
                    enabled: _vimModeAvailable,
                    child: Text(
                      _vimModeAvailable
                          ? 'Neovim keybindings'
                          : 'Neovim keybindings (unsupported by this engine)',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'enter_analysis_mode',
                    enabled: _vimModeEnabled,
                    child: const Text('Analysis review mode (vim)'),
                  ),
                ],
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PagedEditor(
                controller: _editorController,
                partialEraser: _partialEraser,
                eraserWidth: _eraserWidth,
                // While the analysis panel is open, tapping a block that has
                // analysis shows its findings inline (see PageSurface). Null
                // when closed → no popovers during normal editing.
                analysisForBlock:
                    _showAnalysisPanel ? _lookupBlockAnalysis : null,
              ),
            ),

            // Single screen-level drawing dial (was previously embedded once
            // per page). Shown only in drawing mode and pointed at the ACTIVE
            // page's ink notifier, so switching pages retargets the same dial.
            // It floats above the whole page list; empty areas of the overlay
            // don't absorb pointers, so strokes still reach the page canvas
            // underneath. Positioned.fill is the direct Stack child (a Positioned
            // returned from inside the AnimatedBuilder would break parent-data).
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _editorController,
                builder: (context, _) {
                  if (!_editorController.drawingEnabled) {
                    return const SizedBox.shrink();
                  }
                  return ToolDialHub(
                    notifier:
                        _editorController.activeController.drawingNotifier,
                    // Selecting a pen/highlighter/eraser follows across pages.
                    onSelectTool: _editorController.applyDrawingTool,
                    // Re-tapping the eraser toggles this partial/whole flag.
                    partialEraser: _partialEraser,
                    // The size selector sizes the eraser too (shared with pages).
                    eraserWidth: _eraserWidth,
                  );
                },
              ),
            ),

            if (_showAnalysisPanel && _hasAttemptedLoad)
              Positioned(
                right: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 900,
                    width: 800,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.insights_rounded, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Note Analysis',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      (_isGeneratingAnalysis ||
                                              !_analysisEnabled)
                                          ? null
                                          : _generateAnalysis,
                                  icon:
                                      _isGeneratingAnalysis
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(Icons.auto_awesome),
                                  label: Text(
                                    _isGeneratingAnalysis
                                        ? 'Generating...'
                                        : 'Regenerate',
                                  ),
                                ),

                                const SizedBox(width: 8),

                                IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Close',
                                  onPressed: () {
                                    setState(() {
                                      _showAnalysisPanel = false;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(),
                        if (!_analysisEnabled)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Analysis is currently turned off for this note.',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        Expanded(
                          child:
                              _cachedAnalysis != null
                                  // Error / empty / raw-regenerate-result states —
                                  // no structured chunk data to build a list from.
                                  ? SingleChildScrollView(
                                    child: GptMarkdown(_cachedAnalysis!),
                                  )
                                  : ListView.builder(
                                    itemCount: 1 + _analysisChunks.length,
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return _overviewMarkdown != null &&
                                                _overviewMarkdown!
                                                    .trim()
                                                    .isNotEmpty
                                            ? Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: GptMarkdown(
                                                _overviewMarkdown!,
                                              ),
                                            )
                                            : const SizedBox.shrink();
                                      }
                                      return _ChunkExpansionTile(
                                        chunk: _analysisChunks[index - 1],
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Passive save-status indicator, replacing the old bare Save
            // FAB. Tapping it still forces an immediate save — it's the
            // same _save() call — but at rest it now tells you whether
            // there's anything to save at all, instead of always looking
            // like an unpressed button.
            // SCAFFOLD: analysis-review toolbar (only visible in analysis mode).
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _analysisModeBar(),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 16,
              child: AnimatedBuilder(
                animation: _editorController,
                builder: (context, _) {
                  final hasUnsaved = _hasUnsavedChanges();
                  return Material(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _isSaving ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSaving)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Icon(
                                hasUnsaved ? Icons.circle : Icons.check,
                                size: 14,
                                color:
                                    hasUnsaved ? Colors.orange : Colors.green,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _isSaving
                                  ? 'Saving…'
                                  : (hasUnsaved ? 'Unsaved changes' : 'Saved'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One expandable list item per chunk. Collapsed shows the chunk id and a
/// finding count; expanded shows the source excerpt plus each finding as
/// its own nested expansion tile (see _FindingTile).
class _ChunkExpansionTile extends StatelessWidget {
  final Map<String, dynamic> chunk;

  const _ChunkExpansionTile({required this.chunk});

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final findings = chunk['findings'] as List<dynamic>? ?? [];
    final excerpt = chunk['excerpt'] as String?;
    final chunkId = chunk['chunkId'] as String? ?? 'chunk';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(
          chunkId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${findings.length} finding${findings.length == 1 ? '' : 's'}',
        ),
        children: [
          if (excerpt != null && excerpt.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(color: Colors.grey.shade400, width: 3),
                  ),
                ),
                child: Text(
                  excerpt,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          for (final f in findings)
            _FindingTile(
              finding: f as Map<String, dynamic>,
              severityColor: _severityColor,
            ),
        ],
      ),
    );
  }
}

/// One expandable finding within a chunk. Collapsed shows a severity dot
/// and the finding type; expanded shows claim / correct-understanding
/// (only if it actually differs from the claim) / gap explanation.
class _FindingTile extends StatelessWidget {
  final Map<String, dynamic> finding;
  final Color Function(String) severityColor;

  const _FindingTile({required this.finding, required this.severityColor});

  @override
  Widget build(BuildContext context) {
    final severity = (finding['severity'] ?? 'unknown').toString();
    final type = (finding['type'] ?? 'finding').toString().replaceAll('_', ' ');
    final claim = finding['student_claim'] as String?;
    final correct = finding['correct_understanding'] as String?;
    final gap = finding['gap_explanation'] as String?;
    final showCorrect = correct != null && correct != claim;

    return ExpansionTile(
      leading: CircleAvatar(
        radius: 6,
        backgroundColor: severityColor(severity),
      ),
      title: Text(
        type,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        severity.toUpperCase(),
        style: TextStyle(fontSize: 11, color: severityColor(severity)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (claim != null) ...[
                const Text(
                  'Claim',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(claim),
                const SizedBox(height: 8),
              ],
              if (showCorrect) ...[
                const Text(
                  'Correct understanding',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(correct),
                const SizedBox(height: 8),
              ],
              if (gap != null) ...[
                const Text(
                  'Gap',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(gap),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
