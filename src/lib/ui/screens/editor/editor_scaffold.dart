import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/knowledgebase_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/id.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/sync_service.dart';
import 'package:cerebrum/ui/screens/editor/blocks/image/note_image_resolver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/analysis_mode_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/text_editing_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart';
import 'package:cerebrum/ui/screens/editor/widgets/radial_tool_dial.dart';
import 'package:cerebrum/ui/screens/readings/floating_reader.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

enum _TextEngine { appFlowy, superEditor }

class EditorScaffold extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? initialTextJson;
  final List<Map<String, dynamic>>? initialInkJson;
  final List<String>? startBlockIds;
  final String? startPageId;

  const EditorScaffold({
    super.key,
    required this.note,
    this.initialTextJson,
    this.initialInkJson,
    this.startBlockIds,
    this.startPageId,
  });

  @override
  State<EditorScaffold> createState() => _EditorScaffoldState();
}

class _EditorScaffoldState extends State<EditorScaffold> {
  late final PagedNoteController _editorController;
  _TextEngine _currentEngine = _TextEngine.appFlowy;

  final FocusNode _readerFocus = FocusNode(debugLabel: 'floating reader');
  String? _bubbleId;

  /// Shared zoom transform for the Strategy-B single-document editor. Owned
  /// here so the user's zoom survives PageSurface rebuilds.
  final TransformationController _zoomController = TransformationController();

  /// Latest viewport metrics reported by PageSurface:
  ///  * [_fitWidthScale] — the default zoom (Ctrl+0), also the ceiling/5 basis
  ///    for max zoom.
  ///  * [_fitHeightScale] — the floor for zoom-out.
  ///  * [_viewportSize] — center anchor for keyboard/menu zoom.
  double _fitWidthScale = 1.0;
  double _fitHeightScale = 0.3;
  Size? _viewportSize;

  static const double _zoomInFactor = 1.25;
  static const double _zoomOutFactor = 1 / _zoomInFactor;

  /// Zoom around the viewport center (Samsung Notes / browser convention).
  /// Multiplies the current matrix by T(c) · S(f) · T(-c), which keeps the
  /// point at c fixed while everything else scales away/toward it. Applied
  /// to the LEFT of the current matrix so it operates in viewport space.
  void _zoomAroundViewportCenter(double factor) {
    final vp = _viewportSize;
    if (vp == null) return;
    final center = Offset(vp.width / 2, vp.height / 2);
    _zoomAroundPoint(center, factor);
  }

  void _zoomAroundPoint(Offset focal, double factor) {
    final current = _zoomController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final target = (currentScale * factor).clamp(
      math.min(_fitHeightScale, _fitWidthScale),
      _fitWidthScale * 5.0,
    );
    if ((target - currentScale).abs() < 0.0001) return;
    final f = target / currentScale;
    _zoomController.value =
        Matrix4.identity()
          ..translate(focal.dx, focal.dy)
          ..multiply(Matrix4.identity()..scale(f))
          ..multiply(Matrix4.identity()..translate(-focal.dx, -focal.dy))
          ..multiply(current);
  }

  void _zoomIn() => _zoomAroundViewportCenter(_zoomInFactor);
  void _zoomOut() => _zoomAroundViewportCenter(_zoomOutFactor);

  /// Ctrl+0: fit-width, top-aligned. Same as the initial transform.
  void _resetZoom() {
    _zoomController.value = Matrix4.identity()..scale(_fitWidthScale);
  }

  /// Ctrl+Shift+0: fit whole document in viewport, centered.
  void _fitAllZoom() {
    final vp = _viewportSize;
    if (vp == null || _fitWidthScale <= 0 || _fitHeightScale <= 0) return;
    // Content dims recovered from the fit scales:
    //   fitWidth  = vp.width / contentWidth  → contentWidth  = vp.width  / fitWidth
    //   fitHeight = vp.height / contentHeight → contentHeight = vp.height / fitHeight
    final contentW = vp.width / _fitWidthScale;
    final contentH = vp.height / _fitHeightScale;
    final fitAllScale = math.min(vp.width / contentW, vp.height / contentH);
    final scaledW = contentW * fitAllScale;
    final scaledH = contentH * fitAllScale;
    final dx = (vp.width - scaledW) / 2;
    final dy = (vp.height - scaledH) / 2;
    _zoomController.value =
        Matrix4.identity()
          ..translate(dx, dy)
          ..scale(fitAllScale);
  }

  final ValueNotifier<bool> _partialEraser = ValueNotifier(true);
  final ValueNotifier<double> _eraserWidth = ValueNotifier(24);
  final AnalysisModeController _analysisMode = AnalysisModeController();

  static bool _defaultStartInDrawingMode = false;

  bool _showReader = false;
  String? _readerFingerprint;
  static String? _lastReaderFingerprint;

  Future<void> _pickReaderFile() async {
    final fp = await showDialog<String>(
      context: context,
      builder: (_) => _ReaderFilePicker(currentFingerprint: _readerFingerprint),
    );
    if (fp == null || fp.isEmpty || !mounted) return;
    setState(() {
      _readerFingerprint = fp;
      _showReader = true;
    });
  }

  void _focusEditor() {
    final d = _editorController.activeController.driver;
    if (d is AppFlowyTextDriver) d.requestEditorFocus();
  }

  void _focusReader() {
    if (!_showReader) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _readerFocus.requestFocus();
    });
  }

  void _toggleReader() {
    if (_readerFingerprint == null) {
      _pickReaderFile();
      return;
    }
    setState(() => _showReader = !_showReader);
    _showReader ? _focusReader() : _focusEditor();
  }

  bool get _editorInVimCommandMode {
    if (_editorController.drawingEnabled) return false;
    final d = _editorController.activeController.driver;
    if (d is! VimModeAware) return false;
    final v = (d as VimModeAware).vimMode;
    return v.isEnabled && (v.isNormal || v.isAnalysis);
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final fctx = FocusManager.instance.primaryFocus?.context;
    if (fctx != null &&
        (fctx.widget is EditableText ||
            fctx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final hk = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyW &&
        hk.isControlPressed &&
        !hk.isAltPressed &&
        !hk.isMetaPressed) {
      if (!_showReader) return false;
      _readerFocus.hasFocus ? _focusEditor() : _focusReader();
      return true;
    }
    if (key == LogicalKeyboardKey.keyR &&
        !hk.isControlPressed &&
        !hk.isAltPressed &&
        !hk.isMetaPressed &&
        !hk.isShiftPressed) {
      if ((_showReader && _readerFocus.hasFocus) || _editorInVimCommandMode) {
        _toggleReader();
        return true;
      }
    }
    return false;
  }

  Timer? _debounce;
  bool _isSaving = false;
  String _lastSavedState = '';

  String? _cachedAnalysis;
  Map<String, dynamic>? _analysisData;
  Map<String, dynamic>? get analysisData => _analysisData;
  String? _overviewMarkdown;
  List<Map<String, dynamic>> _analysisChunks = [];
  Map<String, Map<String, List<Map<String, dynamic>>>> _blockAnalysis = {};
  bool _hasAttemptedLoad = false;
  bool _isLoadingAnalysis = false;
  bool _showAnalysisPanel = false;
  bool _isGeneratingAnalysis = false;
  bool _pendingInitialJump = false;
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
    _pendingInitialJump =
        widget.startBlockIds != null &&
        widget.startBlockIds!.isNotEmpty &&
        widget.startPageId != null;
    debugPrint(
      '[EditorScaffold] Opening note. filename="$rawFilename" '
      'noteId="$parsedNoteId"',
    );
    _analysisEnabled = widget.note['analyse_note'] as bool? ?? true;
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _analysisMode.onOpenFullPanel = () {
      if (!_hasAttemptedLoad) {
        _loadAnalysis();
      } else {
        setState(() => _showAnalysisPanel = true);
      }
    };
    _analysisMode.onFocusChunk = (ref) {
      _focusAnalysisChunk(ref);
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
    debugPrint(
      '[EditorScaffold] widget.note has "ink" key: '
      '${widget.note.containsKey('ink')}, '
      'inkJson length: ${inkJson?.length}, '
      'first-elem keys: ${inkJson?.firstOrNull?.keys.toList()}',
    );
    final noteId =
        (widget.note['note_id'] as String?) ?? parsedNoteId ?? Ulid.generate();
    widget.note['note_id'] = noteId;
    final bid = _bubbleId;
    if (bid != null && bid.isNotEmpty) {
      NoteImageResolver.configureForNote(bubbleId: bid, noteId: noteId);
    }
    final rawPages =
        widget.note['pages'] != null
            ? List<Map<String, dynamic>>.from(widget.note['pages'])
            : null;
    final loadedPages =
        rawPages == null
            ? null
            : NoteImageResolver.mapPagesUrls(
              rawPages,
              NoteImageResolver.resolve,
            );
    _editorController = PagedNoteController.fromNote(
      pages: loadedPages,
      legacyDocument: docJson,
      legacyInk: inkJson,
    );
    _editorController.addListener(_onEditorChanged);
    _editorController.stepAnalysisChunk = (delta) {
      if (delta > 0) {
        _analysisMode.next();
      } else {
        _analysisMode.prev();
      }
    };
    _editorController.enterAnalysisMode = _enterAnalysisMode;
    _editorController.toggleAnalysisPanel = _toggleAnalysisPanel;
    _editorController.imageUploader = (bytes, name) async {
      final bubbleId = _bubbleId;
      if (bubbleId == null || bubbleId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Save the note before adding images.'),
            ),
          );
        }
        return null;
      }
      final nId = widget.note['note_id'] as String;
      final ext = name.contains('.') ? name.split('.').last : 'png';
      final imageName = '${Ulid.generate()}.$ext';
      try {
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
    if (_pendingInitialJump) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAnalysis(openPanel: false);
      });
    }
  }

  void _onEditorChanged() {
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
      debugPrint('[EditorScaffold] skipping save: missing bubble_id');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final filename = widget.note['filename'] as String?;
      final title = widget.note['title'] ?? 'Untitled';
      var noteId =
          widget.note['note_id'] as String? ?? _noteIdFromFilename(filename);
      if (noteId == null || noteId.isEmpty) {
        noteId = Ulid.generate();
        widget.note['note_id'] = noteId;
      }
      final pages = NoteImageResolver.mapPagesUrls(
        _editorController.toPagesJson(),
        NoteImageResolver.toRef,
      );
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
      _updateLastSavedState();
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
            backgroundColor: context.cerebrum.status.danger,
          ),
        );
      }
    }
  }

  Future<void> _loadAnalysis({bool openPanel = true}) async {
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
        _showAnalysisPanel = openPanel;
        _isLoadingAnalysis = false;
      });
      if (_pendingInitialJump && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToInitialChunk(),
        );
      }
    } catch (e) {
      setState(() {
        _hasAttemptedLoad = true;
        _analysisData = null;
        _overviewMarkdown = null;
        _analysisChunks = [];
        _blockAnalysis = {};
        _cachedAnalysis = 'Error loading analysis:\n$e';
        _showAnalysisPanel = openPanel;
        _isLoadingAnalysis = false;
        _pendingInitialJump = false;
      });
    }
  }

  void _jumpToInitialChunk() {
    if (!_pendingInitialJump) return;
    _pendingInitialJump = false;
    final blockIds = widget.startBlockIds ?? const <String>[];
    final pageId = widget.startPageId;
    final chunks = _analysisMode.chunks;
    if (chunks.isEmpty) return;
    int? match;
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      if (pageId != null && c.pageId != pageId) continue;
      if (c.blockIds.any((b) => blockIds.contains(b))) {
        match = i;
        break;
      }
    }
    if (match == null) {
      debugPrint(
        '[jumpToInitialChunk] no chunk matches page="$pageId" '
        'blockIds=$blockIds',
      );
      return;
    }
    debugPrint('[jumpToInitialChunk] jumping to chunk index $match');
    _analysisMode.jumpTo(match);
  }

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
        final pageId = outerMap['page_id'] as String?;
        final blockIds =
            (outerMap['source_block_ids'] as List<dynamic>? ?? [])
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

  List<Map<String, dynamic>>? _lookupBlockAnalysis(
    String pageId,
    String blockId,
  ) => _blockAnalysis[pageId]?[blockId];

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
    debugPrint(
      '[rebuildAnalysisModeChunks] ${refs.length} navigable chunks; '
      'withBlockIds=${refs.where((r) => r.blockIds.isNotEmpty).length}',
    );
    _analysisMode.setChunks(refs);
  }

  void _rebuildBlockAnalysis() {
    final map = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final chunk in _analysisChunks) {
      final pageId = chunk['pageId'] as String?;
      if (pageId == null) continue;
      final blockIds = (chunk['blockIds'] as List?)?.cast<String>() ?? const [];
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
          SnackBar(
            content: const Text('Analysis generated successfully!'),
            backgroundColor: context.cerebrum.status.success,
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
            backgroundColor: context.cerebrum.status.danger,
          ),
        );
      }
    }
  }

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
  }

  void _focusAnalysisChunk(AnalysisChunkRef ref) {
    final pages = _editorController.pages;
    final targetPageIdx = pages.indexWhere((p) => p.pageId == ref.pageId);
    debugPrint(
      '[focusAnalysisChunk] chunk=${ref.chunkId} page=${ref.pageId} '
      'blockIds=${ref.blockIds} targetPageIdx=$targetPageIdx',
    );
    if (targetPageIdx == -1) return;
    if (_editorController.activeIndex != targetPageIdx) {
      _editorController.setActive(targetPageIdx);
    }
    final driver = _editorController.activeController.driver;
    if (driver is! AppFlowyTextDriver) return;
    if (!driver.vimMode.isAnalysis) {
      driver.vimMode.enterAnalysisMode();
    }
    final document = driver.editorState.document;
    Selection? target;
    final firstBlockId = ref.blockIds.firstOrNull;
    if (firstBlockId != null) {
      final found = _findNodeByStableId(document.root, firstBlockId);
      final selectable = found?.node.selectable;
      if (selectable != null) {
        final start = selectable.start();
        final end = selectable.end();
        target =
            start == end
                ? Selection.collapsed(start)
                : Selection(start: start, end: end);
      }
    }
    if (target == null && document.root.children.isNotEmpty) {
      final selectable = document.root.children.first.selectable;
      if (selectable != null) {
        target = Selection(start: selectable.start(), end: selectable.end());
      }
    }
    if (target != null) {
      driver.editorState.updateSelectionWithReason(
        target,
        reason: SelectionUpdateReason.uiEvent,
      );
    }
    final activeDriver = _editorController.activeController.driver;
    if (activeDriver is AppFlowyTextDriver) activeDriver.requestEditorFocus();
  }

  ({Node node, int depth})? _findNodeByStableId(Node root, String id) {
    Node? found;
    var foundDepth = 0;
    void walk(Node node, int depth) {
      if (found != null) return;
      if (node.id == id) {
        found = node;
        foundDepth = depth;
        return;
      }
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(root, 0);
    return found == null ? null : (node: found!, depth: foundDepth);
  }

  void _enterAnalysisMode() {
    final driver = _editorController.activeController.driver;
    if (driver is! AppFlowyTextDriver) return;
    if (!driver.vimMode.isEnabled) return;
    if (!_hasAttemptedLoad) _loadAnalysis(openPanel: false);
    driver.vimMode.enterAnalysisMode();
    final sel = driver.editorState.selection;
    if (sel != null && sel.isCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final node = driver.editorState.getNodeAtPath(sel.start.path);
        final selectable = node?.selectable;
        if (selectable != null) {
          final start = selectable.start();
          final end = selectable.end();
          if (start != end) {
            driver.editorState.updateSelectionWithReason(
              Selection(start: start, end: end),
              reason: SelectionUpdateReason.uiEvent,
            );
          }
        }
      });
    }
  }

  void _toggleAnalysisPanel() {
    if (_showAnalysisPanel) {
      setState(() => _showAnalysisPanel = false);
      return;
    }
    if (!_hasAttemptedLoad) {
      _loadAnalysis();
    } else {
      setState(() => _showAnalysisPanel = true);
    }
  }

  Widget _analysisViewToggle() {
    return SegmentedButton<bool>(
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
    );
  }

  Widget _analysisModeBar() {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, _) {
        if (_editorController.drawingEnabled) return const SizedBox.shrink();
        final driver = _editorController.activeController.driver;
        if (driver is! VimModeAware) return const SizedBox.shrink();
        final vimMode = (driver as VimModeAware).vimMode;
        return AnimatedBuilder(
          animation: vimMode,
          builder: (context, __) {
            if (!vimMode.isEnabled || !vimMode.isAnalysis) {
              return const SizedBox.shrink();
            }
            return AnimatedBuilder(
              animation: _analysisMode,
              builder: (context, ___) {
                final cur = _analysisMode.current;
                final label =
                    cur == null
                        ? 'No analysis chunks'
                        : 'Chunk ${_analysisMode.index + 1} / ${_analysisMode.count}';
                final tokens = context.cerebrum;
                return Material(
                  color: tokens.brand.primary,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.chevron_left,
                            color: tokens.brand.onPrimary,
                          ),
                          onPressed:
                              _analysisMode.hasChunks
                                  ? _analysisMode.prev
                                  : null,
                        ),
                        Text(
                          label,
                          style: TextStyle(
                            color: tokens.brand.onPrimary,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.chevron_right,
                            color: tokens.brand.onPrimary,
                          ),
                          onPressed:
                              _analysisMode.hasChunks
                                  ? _analysisMode.next
                                  : null,
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _analysisMode.openFullPanel,
                          child: Text(
                            'Full analysis',
                            style: TextStyle(color: tokens.brand.onPrimary),
                          ),
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
            final editor = context.cerebrum.editor;
            final (label, color) = switch (vimMode.value) {
              VimMode.normal => ('NORMAL', editor.modeBadgeNormal),
              VimMode.insert => ('INSERT', editor.modeBadgeInsert),
              VimMode.analysis => ('ANALYSIS', editor.modeBadgeAnalysis),
              VimMode.visual => ('VISUAL', editor.modeBadgeVisual),
            };
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: context.cerebrum.text.onModeBadge,
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

  Widget _headingBadge() {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, _) {
        final driver = _editorController.activeController.driver;
        if (driver is! AppFlowyTextDriver) return const SizedBox.shrink();
        final doc = driver.documentJson;
        final children = (doc['children'] as List?) ?? const [];
        final idx = driver.selectedBlockIndex;
        if (idx == null) return const SizedBox.shrink();
        int? level;
        for (var i = idx; i >= 0 && i < children.length; i--) {
          final b = children[i] as Map?;
          if (b != null && b['type'] == 'heading') {
            level = (b['data'] as Map?)?['level'] as int? ?? 1;
            break;
          }
        }
        if (level == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.cerebrum.surface.sunken,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: context.cerebrum.surface.outline),
          ),
          child: Text(
            'H$level',
            style: TextStyle(
              color: context.cerebrum.text.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        );
      },
    );
  }

  void _switchEngine(_TextEngine engine) {
    if (engine == _currentEngine) return;
    final TextEditingDriver newDriver;
    switch (engine) {
      case _TextEngine.appFlowy:
        newDriver = AppFlowyTextDriver(
          initialDocumentJson: _editorController.activeController.documentJson,
        );
        break;
      case _TextEngine.superEditor:
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
    });
  }

  @override
  void dispose() {
    _editorController.removeListener(_onEditorChanged);
    _editorController.dispose();
    _partialEraser.dispose();
    _eraserWidth.dispose();
    _analysisMode.dispose();
    _zoomController.dispose();
    _debounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _readerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _save(),
        SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        SingleActivator(LogicalKeyboardKey.equal, meta: true): _zoomIn,
        SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
        SingleActivator(LogicalKeyboardKey.minus, meta: true): _zoomOut,
        SingleActivator(LogicalKeyboardKey.digit0, control: true): _resetZoom,
        SingleActivator(LogicalKeyboardKey.digit0, meta: true): _resetZoom,
        SingleActivator(LogicalKeyboardKey.digit0, control: true, shift: true):
            _fitAllZoom,
        SingleActivator(LogicalKeyboardKey.digit0, meta: true, shift: true):
            _fitAllZoom,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note['title'] ?? 'Edit Note'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _headingBadge(),
              ),
            ),
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
              Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.cerebrum.editor.analysisBadge,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AnimatedBuilder(
                animation: _editorController,
                builder: (context, _) {
                  final driver = _editorController.activeController.driver;
                  if (driver is! VimModeAware) return _analysisViewToggle();
                  final vimMode = (driver as VimModeAware).vimMode;
                  return AnimatedBuilder(
                    animation: vimMode,
                    builder: (context, __) {
                      if (vimMode.isEnabled) return const SizedBox.shrink();
                      return _analysisViewToggle();
                    },
                  );
                },
              ),
            ),
            IconButton(
              icon: Icon(
                _showReader ? Icons.menu_book : Icons.menu_book_outlined,
              ),
              tooltip: _showReader ? 'Hide reader' : 'Open reader',
              onPressed: _toggleReader,
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
                  case 'zoom_in':
                    _zoomIn();
                    break;
                  case 'zoom_out':
                    _zoomOut();
                    break;
                  case 'reset_zoom':
                    _resetZoom();
                    break;
                  case 'fit_all':
                    _fitAllZoom();
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
                      value: 'zoom_in',
                      child: Row(
                        children: const [
                          Icon(Icons.zoom_in, size: 18),
                          SizedBox(width: 8),
                          Text('Zoom in      Ctrl + ='),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'zoom_out',
                      child: Row(
                        children: const [
                          Icon(Icons.zoom_out, size: 18),
                          SizedBox(width: 8),
                          Text('Zoom out    Ctrl + -'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'reset_zoom',
                      child: Row(
                        children: const [
                          Icon(Icons.fit_screen, size: 18),
                          SizedBox(width: 8),
                          Text('Fit width    Ctrl + 0'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'fit_all',
                      child: Row(
                        children: const [
                          Icon(Icons.fullscreen, size: 18),
                          SizedBox(width: 8),
                          Text('Fit page     Ctrl + Shift + 0'),
                        ],
                      ),
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
                      enabled:
                          _vimModeAvailable &&
                          !_editorController.drawingEnabled,
                      child: Text(
                        _vimModeAvailable
                            ? 'Neovim keybindings'
                            : 'Neovim keybindings (unsupported by this engine)',
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'enter_analysis_mode',
                      enabled:
                          _vimModeEnabled && !_editorController.drawingEnabled,
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
                child: AnimatedBuilder(
                  animation: _editorController,
                  builder: (context, _) {
                    final driver = _editorController.activeController.driver;
                    final vimMode =
                        driver is VimModeAware
                            ? (driver as VimModeAware).vimMode
                            : null;
                    Widget pagedEditor() => PagedEditor(
                      controller: _editorController,
                      partialEraser: _partialEraser,
                      eraserWidth: _eraserWidth,
                      analysisForBlock:
                          (_showAnalysisPanel || (vimMode?.isAnalysis ?? false))
                              ? _lookupBlockAnalysis
                              : null,
                      zoomController: _zoomController,
                      onViewportChanged: (fitW, fitH, vp) {
                        // Assign directly — do NOT setState here. PageSurface
                        // calls this from a post-frame callback, and a
                        // setState mid-frame would re-trigger the whole
                        // editor rebuild; these fields are read lazily at
                        // tap/zoom time, not during build.
                        _fitWidthScale = fitW;
                        _fitHeightScale = fitH;
                        _viewportSize = vp;
                      },
                    );
                    if (vimMode == null) return pagedEditor();
                    return AnimatedBuilder(
                      animation: vimMode,
                      builder: (context, __) => pagedEditor(),
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _editorController,
                  builder: (context, _) {
                    if (!_editorController.drawingEnabled) {
                      return const SizedBox.shrink();
                    }
                    return ToolDialHub(
                      notifier: _editorController.dialNotifier,
                      onSelectTool: _editorController.applyDrawingTool,
                      partialEraser: _partialEraser,
                      eraserWidth: _eraserWidth,
                    );
                  },
                ),
              ),
              if (_showAnalysisPanel && _hasAttemptedLoad)
                Positioned(
                  right: 16,
                  top: 16,
                  bottom: 16,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
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
                                    'Analysis Summary',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
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
                                          ? 'Analysing...'
                                          : 'Re-analyse',
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
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Analysis is currently turned off for this note.',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: context.cerebrum.text.muted,
                                ),
                              ),
                            ),
                          Expanded(
                            child:
                                _cachedAnalysis != null
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
                                        return const SizedBox.shrink();
                                      },
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                bottom: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: context.cerebrum.surface.raised,
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: Tooltip(
                        preferBelow: false,
                        message: 'Add Page',
                        child: IconButton(
                          icon: const Icon(Icons.note_add_outlined),
                          onPressed: _editorController.addPage,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _editorController,
                      builder: (context, _) {
                        final hasUnsaved = _hasUnsavedChanges();
                        return Material(
                          color: context.cerebrum.surface.raised,
                          elevation: 2,
                          shape: const CircleBorder(),
                          child: Tooltip(
                            preferBelow: false,
                            message:
                                _isSaving
                                    ? 'Saving…'
                                    : hasUnsaved
                                    ? 'Unsaved changes'
                                    : 'Saved',
                            child: IconButton(
                              onPressed: _isSaving ? null : _save,
                              icon:
                                  _isSaving
                                      ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : Icon(
                                        hasUnsaved ? Icons.circle : Icons.check,
                                        size: 14,
                                        color:
                                            hasUnsaved
                                                ? context
                                                    .cerebrum
                                                    .editor
                                                    .unsavedBadge
                                                : context
                                                    .cerebrum
                                                    .editor
                                                    .savedBadge,
                                      ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_readerFingerprint != null)
                FloatingReaderWindow(
                  fileFingerprint: _readerFingerprint!,
                  visible: _showReader,
                  readerFocusNode: _readerFocus,
                  onReleaseFocus: _focusEditor,
                  onClose: () {
                    setState(() => _showReader = false);
                    _focusEditor();
                  },
                  onChangeFile: _pickReaderFile,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChunkExpansionTile extends StatelessWidget {
  final Map<String, dynamic> chunk;

  const _ChunkExpansionTile({required this.chunk});

  Color _severityColor(BuildContext context, String severity) {
    final status = context.cerebrum.status;
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return status.danger;
      case 'medium':
        return status.warning;
      case 'low':
        return status.success;
      default:
        return status.neutral;
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
                  color: context.cerebrum.surface.sunken,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(
                      color: context.cerebrum.brand.primary,
                      width: 3,
                    ),
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

class _FindingTile extends StatelessWidget {
  final Map<String, dynamic> finding;
  final Color Function(BuildContext, String) severityColor;
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
        backgroundColor: severityColor(context, severity),
      ),
      title: Text(
        type,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        severity.toUpperCase(),
        style: TextStyle(fontSize: 11, color: severityColor(context, severity)),
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

class _ReaderFilePicker extends StatefulWidget {
  final String? currentFingerprint;
  const _ReaderFilePicker({this.currentFingerprint});

  @override
  State<_ReaderFilePicker> createState() => _ReaderFilePickerState();
}

class _ReaderFilePickerState extends State<_ReaderFilePicker> {
  late final Future<List<Map<String, dynamic>>> _files = _load();
  String _query = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await KnowledgebaseApi.showFiles();
    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open document'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search documents',
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _files,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load documents: ${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final files =
                      (snap.data ?? []).where((f) {
                        final name =
                            (f['original_name'] ?? '').toString().toLowerCase();
                        return _query.isEmpty || name.contains(_query);
                      }).toList();
                  if (files.isEmpty) {
                    return const Center(child: Text('No documents found'));
                  }
                  return ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final f = files[i];
                      final fp = f['file_fingerprint'] as String?;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.picture_as_pdf),
                        title: Text(
                          (f['original_name'] ?? 'Unnamed file').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing:
                            fp == widget.currentFingerprint
                                ? const Icon(Icons.check, size: 18)
                                : null,
                        enabled: fp != null,
                        onTap:
                            fp == null
                                ? null
                                : () => Navigator.pop(context, fp),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
