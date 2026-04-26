import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/bubbles_api.dart';
import 'package:cerebrum_app/api/learning_center_api.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'helpers/editor_commands.dart';

class CerebrumEditorPage extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? initialTextJson;
  final List<Map<String, dynamic>>? initialInkJson;

  const CerebrumEditorPage({
    super.key,
    required this.note,
    this.initialTextJson,
    this.initialInkJson,
  });

  @override
  State<CerebrumEditorPage> createState() => _CerebrumEditorPageState();
}

class _CerebrumEditorPageState extends State<CerebrumEditorPage> {
  late EditorState _editorState;
  late DrawingController _drawingController;

  Timer? _debounce;
  bool _isSaving = false;
  bool drawingEnabled = true;
  String _lastSavedState = '';

  String? _cachedAnalysis;
  bool _isLoadingAnalysis = false;
  bool _showAnalysisPanel = false;
  bool _isGeneratingAnalysis = false;

  String? _noteIdFromFilename(String? filename) {
    if (filename == null || filename.isEmpty) return null;
    return filename.endsWith('.json')
        ? filename.substring(0, filename.length - 5)
        : filename;
  }

  @override
  void initState() {
    super.initState();

    final contentData =
        widget.initialTextJson ??
        widget.note['content'] as Map<String, dynamic>?;

    final docJson =
        contentData?['document'] ??
        {
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

    try {
      _editorState = EditorState(
        document: Document.fromJson({'document': docJson}),
      );
    } catch (_) {
      _editorState = EditorState.blank();
    }

    _drawingController = DrawingController();

    if (widget.initialInkJson != null) {
      _loadInkFromJson(widget.initialInkJson!);
    } else if (widget.note['ink'] != null) {
      _loadInkFromJson(List<Map<String, dynamic>>.from(widget.note['ink']));
    }

    _setupAutosave();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateLastSavedState(),
    );
  }

  void _setupAutosave() {
    _editorState.transactionStream.listen((_) => _scheduleSave());
    _drawingController.addListener(_scheduleSave);
  }

  void _updateLastSavedState() {
    final doc = _editorState.document.toJson();
    final ink = _drawingController.getJsonList();
    _lastSavedState = '$doc|$ink';
  }

  bool _hasUnsavedChanges() {
    final doc = _editorState.document.toJson();
    final ink = _drawingController.getJsonList();
    return '$doc|$ink' != _lastSavedState;
  }

  void _scheduleSave() {
    if (!_hasUnsavedChanges()) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (_isSaving || !_hasUnsavedChanges()) return;

    setState(() => _isSaving = true);

    try {
      final bubbleId = widget.note['bubble_id'] as String;
      final filename = widget.note['filename'] as String?;

      final updated =
          filename != null
              ? await BubbleNotesApi.updateNote(
                bubbleId: bubbleId,
                filename: filename,
                title: widget.note['title'] ?? 'Untitled',
                content: {
                  'document': _editorState.document.toJson()['document'],
                },
                ink: _drawingController.getJsonList(),
              )
              : await BubbleNotesApi.createNote(
                bubbleId: bubbleId,
                title: widget.note['title'] ?? 'Untitled',
                content: {
                  'document': _editorState.document.toJson()['document'],
                },
                ink: _drawingController.getJsonList(),
              );

      widget.note.addAll(updated);
      _updateLastSavedState();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadAnalysis() async {
    final bubbleId = widget.note['bubble_id'] as String?;
    final noteId = _noteIdFromFilename(widget.note['filename'] as String?);
    final version = widget.note['version'] as int? ?? 0;

    if (bubbleId == null || noteId == null) return;

    setState(() => _isLoadingAnalysis = true);

    try {
      final analysis = await LearningCenterApi.getNoteAnalysis(
        bubbleId: bubbleId,
        noteId: noteId,
        version: version,
      );

      setState(() {
        _cachedAnalysis = analysis ?? 'No cached analysis found for this note.';
        _showAnalysisPanel = true;
        _isLoadingAnalysis = false;
      });
    } catch (e) {
      setState(() {
        _cachedAnalysis = 'Error loading analysis:\n$e';
        _showAnalysisPanel = true;
        _isLoadingAnalysis = false;
      });
    }
  }

  Future<void> _generateAnalysis() async {
    final bubbleId = widget.note['bubble_id'] as String?;
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
        _cachedAnalysis =
            analysis ?? 'Analysis generated but no content returned.';
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
        _cachedAnalysis = 'Error generating analysis:\n$e';
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

  void _loadInkFromJson(List<Map<String, dynamic>> jsonList) {
    for (final item in jsonList) {
      try {
        final type = item['type'];
        final content = switch (type) {
          'SimpleLine' => SimpleLine.fromJson(item),
          'SmoothLine' => SmoothLine.fromJson(item),
          'StraightLine' => StraightLine.fromJson(item),
          'Circle' => Circle.fromJson(item),
          'Rectangle' => Rectangle.fromJson(item),
          'Eraser' => Eraser.fromJson(item),
          _ => null,
        };
        if (content != null) _drawingController.addContent(content);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _drawingController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note['title'] ?? 'Edit Note'),
        actions: [
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
          IconButton(
            icon: Icon(drawingEnabled ? Icons.brush : Icons.text_fields),
            tooltip:
                drawingEnabled
                    ? 'Switch to Text Mode'
                    : 'Switch to Drawing Mode',
            onPressed: () {
              setState(() {
                drawingEnabled = !drawingEnabled;
                if (drawingEnabled) FocusScope.of(context).unfocus();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'View Cached Analysis',
            onPressed:
                _isLoadingAnalysis
                    ? null
                    : () {
                      if (_cachedAnalysis != null) {
                        setState(() {
                          _showAnalysisPanel = !_showAnalysisPanel;
                        });
                      } else {
                        _loadAnalysis();
                      }
                    },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate New Analysis',
            onPressed: _isGeneratingAnalysis ? null : _generateAnalysis,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Editor + Drawing board share same space
            Positioned.fill(
              child: Stack(
                children: [
                  // Text Editor
                  AbsorbPointer(
                    absorbing: drawingEnabled,
                    child: AppFlowyEditor(
                      editorState: _editorState,
                      commandShortcutEvents: [
                        ...standardCommandShortcutEvents,
                        ...EditorShortcuts.getCustomShortcuts(),
                      ],
                    ),
                  ),
                  // Drawing Board
                  IgnorePointer(
                    ignoring: !drawingEnabled,
                    child: DrawingBoard(
                      controller: _drawingController,
                      background: Container(color: Colors.transparent),
                      showDefaultActions: drawingEnabled,
                      showDefaultTools: drawingEnabled,
                    ),
                  ),
                ],
              ),
            ),

            // Analysis Panel
            if (_showAnalysisPanel && _cachedAnalysis != null)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Note Analysis',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _showAnalysisPanel = false;
                                });
                              },
                            ),
                          ],
                        ),
                        const Divider(),
                        Flexible(
                          child: SingleChildScrollView(
                            child: GptMarkdown(_cachedAnalysis!),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        child: const Icon(Icons.save),
      ),
    );
  }
}
