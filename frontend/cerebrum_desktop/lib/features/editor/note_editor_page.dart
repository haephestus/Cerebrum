import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/bubbles_api.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'note_editor_commands.dart'; // Import your shortcuts

class NoteEditorPage extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? initialTextJson;
  final List<Map<String, dynamic>>? initialInkJson;

  const NoteEditorPage({
    super.key,
    required this.note,
    this.initialTextJson,
    this.initialInkJson,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late EditorState _editorState;
  late DrawingController _drawingController;
  Timer? _debounce;
  bool _isSaving = false;
  bool drawingEnabled = true;
  String _lastSavedState = '';

  @override
  void initState() {
    super.initState();

    debugPrint('Initializing NoteEditorPage with note: ${widget.note}');

    // Initialize editor with saved content or blank
    Map<String, dynamic>? contentData =
        widget.initialTextJson ??
        widget.note['content'] as Map<String, dynamic>?;

    Map<String, dynamic> docJson;

    if (contentData != null) {
      // Unwrap document key safely
      var doc = contentData['document'];
      if (doc is Map<String, dynamic>) {
        // Handle double-wrapped document
        if (doc.containsKey('document') &&
            doc['document'] is Map<String, dynamic>) {
          docJson = doc['document'] as Map<String, dynamic>;
        } else {
          docJson = doc;
        }
      } else {
        docJson = {
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
      }
    } else {
      docJson = {
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
    }

    debugPrint('Document JSON for editor: $docJson');

    try {
      _editorState = EditorState(
        document: Document.fromJson({'document': docJson}),
      );
    } catch (e) {
      debugPrint('Error loading document: $e');
      _editorState = EditorState.blank();
    }

    // Initialize DrawingBoard
    _drawingController = DrawingController();

    // Load initial ink strokes
    if (widget.initialInkJson != null) {
      _loadInkFromJson(widget.initialInkJson!);
    } else if (widget.note['ink'] != null) {
      _loadInkFromJson(List<Map<String, dynamic>>.from(widget.note['ink']));
    }

    // Autosave setup
    _setupAutosave();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateLastSavedState();
    });
  }

  void _setupAutosave() {
    _editorState.transactionStream.listen(
      (_) => _scheduleSave(),
      onError: (error) => debugPrint('Editor transaction stream error: $error'),
    );

    _drawingController.addListener(() => _scheduleSave());
  }

  void _updateLastSavedState() {
    try {
      final documentJson = _editorState.document.toJson();
      final inkJson = _drawingController.getJsonList();
      _lastSavedState = '$documentJson|$inkJson';
    } catch (e) {
      debugPrint('Error updating last saved state: $e');
      _lastSavedState = '';
    }
  }

  bool _hasUnsavedChanges() {
    try {
      final documentJson = _editorState.document.toJson();
      final inkJson = _drawingController.getJsonList();
      final currentState = '$documentJson|$inkJson';
      return currentState != _lastSavedState;
    } catch (e) {
      debugPrint('Error checking unsaved changes: $e');
      return false;
    }
  }

  void _loadInkFromJson(List<Map<String, dynamic>> jsonList) {
    final List<PaintContent> contents = [];
    for (var item in jsonList) {
      final type = item['type'] as String;
      try {
        switch (type) {
          case 'SimpleLine':
            contents.add(SimpleLine.fromJson(item));
            break;
          case 'SmoothLine':
            contents.add(SmoothLine.fromJson(item));
            break;
          case 'StraightLine':
            contents.add(StraightLine.fromJson(item));
            break;
          case 'Circle':
            contents.add(Circle.fromJson(item));
            break;
          case 'Rectangle':
            contents.add(Rectangle.fromJson(item));
            break;
          case 'Eraser':
            contents.add(Eraser.fromJson(item));
            break;
          default:
            debugPrint('Unknown PaintContent type: $type');
        }
      } catch (e) {
        debugPrint('Error loading PaintContent of type $type: $e');
      }
    }
    if (contents.isNotEmpty) {
      _drawingController.addContents(contents);
    }
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
      final documentJson = _editorState.document.toJson();
      final inkJson = _drawingController.getJsonList();

      // Ensure correct wrapping
      final contentForApi =
          documentJson.containsKey('document')
              ? documentJson
              : {'document': documentJson};

      String? bubbleId =
          widget.note['bubbleId'] as String? ??
          widget.note['bubble_id'] as String?;

      if (bubbleId == null || bubbleId.isEmpty) {
        throw Exception('Missing bubbleId for note.');
      }

      final filename = widget.note['filename'] as String?;
      Map<String, dynamic> updatedNote;

      if (filename != null && filename.isNotEmpty) {
        updatedNote = await BubbleNotesApi.updateNote(
          bubbleId: bubbleId,
          filename: filename,
          title: widget.note['title'] ?? 'Untitled Note',
          content: contentForApi,
          ink: inkJson,
        );
      } else {
        updatedNote = await BubbleNotesApi.createNote(
          bubbleId: bubbleId,
          title: widget.note['title'] ?? 'Untitled Note',
          content: contentForApi,
          ink: inkJson,
        );
        widget.note['filename'] = updatedNote['filename'];
      }

      // Update local state
      setState(() {
        widget.note['content'] = updatedNote['content'];
        widget.note['ink'] = updatedNote['ink'];
        widget.note['bubbleId'] =
            updatedNote['bubbleId'] ?? updatedNote['bubble_id'] ?? bubbleId;
      });

      _updateLastSavedState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Save error: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges()) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text(
                'You have unsaved changes. Save before leaving?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Discard'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _save();
                    if (mounted) Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
      );
      return shouldPop ?? false;
    }
    return true;
  }

  void _toggleMode() {
    setState(() {
      drawingEnabled = !drawingEnabled;
      if (drawingEnabled) FocusScope.of(context).unfocus();
    });
  }

  void _clearDrawing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Drawing'),
            content: const Text('Are you sure you want to clear all drawings?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      _drawingController.clear();
      _scheduleSave();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note['title'] ?? 'Edit Note'),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else if (_hasUnsavedChanges())
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.circle, size: 8, color: Colors.orange),
              ),
            IconButton(
              icon: Icon(drawingEnabled ? Icons.brush : Icons.text_fields),
              tooltip:
                  drawingEnabled
                      ? 'Switch to Text Mode'
                      : 'Switch to Drawing Mode',
              onPressed: _toggleMode,
            ),
            if (drawingEnabled)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'undo':
                      _drawingController.undo();
                      break;
                    case 'redo':
                      _drawingController.redo();
                      break;
                    case 'clear':
                      _clearDrawing();
                      break;
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'undo',
                        child: Row(
                          children: [
                            Icon(Icons.undo),
                            SizedBox(width: 8),
                            Text('Undo'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'redo',
                        child: Row(
                          children: [
                            Icon(Icons.redo),
                            SizedBox(width: 8),
                            Text('Redo'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.clear_all, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Clear All',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
              ),
          ],
        ),
        body: Stack(
          children: [
            AbsorbPointer(
              absorbing: drawingEnabled,
              child: AppFlowyEditor(
                editorState: _editorState,
                commandShortcutEvents: [
                  ...standardCommandShortcutEvents,
                  ...EditorShortcuts.getCustomShortcuts(),
                ],
                characterShortcutEvents: [...standardCharacterShortcutEvents],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !drawingEnabled,
                child: Opacity(
                  opacity: drawingEnabled ? 1.0 : 0.3,
                  child: DrawingBoard(
                    controller: _drawingController,
                    background: Container(color: Colors.transparent),
                    showDefaultActions: drawingEnabled,
                    showDefaultTools: drawingEnabled,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _save,
          tooltip: 'Save Note',
          child:
              _isSaving
                  ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.save),
        ),
      ),
    );
  }
}
