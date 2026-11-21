import 'dart:math' as math;

import 'package:cerebrum/features/chat/api/chat_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// A draggable, resizable floating window that hosts the editor chat.
///
/// Note-scoped when `noteId` is present: the daemon route is
/// `POST /chat/notes/{noteId}` and retrieval is grounded on the note plus the
/// sources its analysis used. Without a note id it falls back to the
/// bubble-wide route. History is persisted per bubble on the daemon
/// (`study_bubbles/<bubbleId>/chat/history.db`) and partitioned by note, so
/// the transcript survives a fresh mount; the widget loads it on open.
///
/// `_historyLimit` is the last-N toggle: how many prior turns the daemon
/// feeds back into the next answer (0 = off). Compaction events come back
/// inline from the history endpoint.
///
/// Window chrome mirrors floating_reader.dart: fractions of screen size,
/// Visibility.maintainState so messages/position survive hide, Offstage for
/// collapse, and a coloured border while focused.
class FloatingChatWindow extends StatefulWidget {
  final String? bubbleId;
  final String? noteId;
  final String noteTitle;
  final bool visible;
  final VoidCallback onClose;
  final FocusNode? chatFocusNode;
  final VoidCallback? onReleaseFocus;

  const FloatingChatWindow({
    super.key,
    required this.bubbleId,
    this.noteId,
    required this.noteTitle,
    required this.visible,
    required this.onClose,
    this.chatFocusNode,
    this.onReleaseFocus,
  });

  @override
  State<FloatingChatWindow> createState() => _FloatingChatWindowState();
}

class _Message {
  final bool isUser;
  final String text;
  final bool isCompaction;
  const _Message({
    required this.isUser,
    required this.text,
    this.isCompaction = false,
  });
}

/// Parsed compaction event returned by the daemon history endpoints.
class CompactionEvent {
  final int fromSeq;
  final int toSeq;
  final int messageCount;
  final String summary;
  final String? model;
  final String? createdAt;

  CompactionEvent({
    required this.fromSeq,
    required this.toSeq,
    required this.messageCount,
    required this.summary,
    this.model,
    this.createdAt,
  });

  factory CompactionEvent.fromJson(Map<String, dynamic> json) {
    return CompactionEvent(
      fromSeq: (json['from_seq'] as num).toInt(),
      toSeq: (json['to_seq'] as num).toInt(),
      messageCount: (json['message_count'] as num).toInt(),
      summary: json['summary'] as String? ?? '',
      model: json['model'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class _FloatingChatWindowState extends State<FloatingChatWindow> {
  static const _minSize = Size(360, 320);
  static const _titleBarHeight = 40.0;
  static const _edge = 8.0;
  static const _margin = 12.0;

  Size _frac = const Size(0.38, 0.7);
  Offset? _posFrac;
  bool _maximized = false;
  bool _collapsed = false;

  final List<_Message> _messages = [];
  final List<CompactionEvent> _compactionEvents = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  /// Last-N history toggle: how many prior turns to feed into the next answer.
  /// 0 means stateless (off).
  int _historyLimit = 10;

  bool get _bubbleReady =>
      widget.bubbleId != null && widget.bubbleId!.isNotEmpty;

  static String? _extractText(Map entry) {
    for (final k in ['message', 'content', 'text', 'answer', 'response']) {
      final v = entry[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_bubbleReady) return;
    setState(() {
      _messages.add(_Message(isUser: true, text: text));
      _input.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final res = await ChatApi.sendMessage(
        bubbleId: widget.bubbleId!,
        noteId: widget.noteId,
        message: text,
        historyLimit: _historyLimit,
      );
      final answer = _extractText(Map.of(res)) ?? 'No answer returned.';
      final compaction = res['compaction'] != null
          ? CompactionEvent.fromJson(res['compaction'] as Map<String, dynamic>)
          : null;
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(isUser: false, text: answer));
        if (compaction != null) _compactionEvents.add(compaction);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Failed to send: $e';
      });
    }
  }

  Future<void> _loadHistory() async {
    if (!_bubbleReady) return;
    try {
      final data = await ChatApi.history(
        bubbleId: widget.bubbleId,
        noteId: widget.noteId,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        final loaded = <_Message>[];
        final compactions = <CompactionEvent>[];
        for (final entry in data['messages'] as List) {
          if (entry['kind'] == 'compaction') continue;
          final extracted = _extractText(Map.of(entry));
          if (extracted != null) {
            loaded.add(
              _Message(
                isUser: entry['role'] == 'user',
                text: extracted,
              ),
            );
          }
        }
        for (final c in data['compactions'] as List) {
          compactions.add(CompactionEvent.fromJson(Map.of(c)));
        }
        _messages
          ..clear()
          ..addAll(loaded);
        _compactionEvents
          ..clear()
          ..addAll(compactions);
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load history: $e';
      });
    }
  }

  Future<void> _toggleCompaction(CompactionEvent c) async {
    if (!_bubbleReady) return;
    try {
      await ChatApi.clearHistory(
        bubbleId: widget.bubbleId,
        noteId: widget.noteId,
      );
      if (!mounted) return;
      // Reload to get uncompacted turns
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to clear history: $e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Rect _resolveRect(Size screen, Size bounds) {
    if (_maximized) {
      return Rect.fromLTWH(
        _margin,
        _margin,
        math.max(_minSize.width, bounds.width - _margin * 2),
        math.max(_minSize.height, bounds.height - _margin * 2),
      );
    }
    final maxW = math.max(_minSize.width, bounds.width);
    final maxH = math.max(_minSize.height, bounds.height);
    final w =
        (screen.width * _frac.width).clamp(_minSize.width, maxW).toDouble();
    final h =
        (screen.height * _frac.height).clamp(_minSize.height, maxH).toDouble();
    final rawLeft =
        _posFrac == null
            ? bounds.width - w - _margin
            : _posFrac!.dx * screen.width;
    final rawTop = _posFrac == null ? _margin : _posFrac!.dy * screen.height;
    final left = rawLeft.clamp(0.0, math.max(0.0, bounds.width - w)).toDouble();
    final top =
        rawTop
            .clamp(0.0, math.max(0.0, bounds.height - _titleBarHeight))
            .toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  void _commit(Rect r, Size screen) {
    setState(() {
      _frac = Size(r.width / screen.width, r.height / screen.height);
      _posFrac = Offset(r.left / screen.width, r.top / screen.height);
    });
  }

  void _move(Rect r, Size screen, Offset d) {
    if (_maximized) return;
    _commit(r.shift(d), screen);
  }

  void _resize(
    Rect r,
    Size screen, {
    double left = 0,
    double right = 0,
    double bottom = 0,
  }) {
    if (_maximized) return;
    var l = r.left, w = r.width, h = r.height;
    if (left != 0) {
      final nw = w - left;
      if (nw >= _minSize.width) {
        l += left;
        w = nw;
      }
    }
    if (right != 0) w = math.max(_minSize.width, w + right);
    if (bottom != 0) h = math.max(_minSize.height, h + bottom);
    _commit(Rect.fromLTWH(l, r.top, w, h), screen);
  }

  void _toggleMaximized() => setState(() => _maximized = !_maximized);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: Visibility(
        visible: widget.visible,
        maintainState: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rect = _resolveRect(screen, constraints.biggest);
            final height = _collapsed ? _titleBarHeight : rect.height;
            return Stack(
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: height,
                  child: RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        if (widget.chatFocusNode != null) widget.chatFocusNode!,
                      ]),
                      builder:
                          (context, _) => Material(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color:
                                    (widget.chatFocusNode?.hasFocus ?? false)
                                        ? scheme.primary
                                        : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            color: scheme.surface,
                            child: Column(
                              children: [
                                _titleBar(scheme, rect, screen),
                                Expanded(
                                  child: Offstage(
                                    offstage: _collapsed,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Focus(
                                            focusNode: widget.chatFocusNode,
                                            onKeyEvent: (node, event) {
                                              if (event is KeyDownEvent &&
                                                  event.logicalKey ==
                                                      LogicalKeyboardKey
                                                          .escape) {
                                                widget.onReleaseFocus?.call();
                                                return KeyEventResult.handled;
                                              }
                                              return KeyEventResult.ignored;
                                            },
                                            child: Listener(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onPointerDown: (_) {
                                                final n = widget.chatFocusNode;
                                                if (n != null && !n.hasFocus)
                                                  n.requestFocus();
                                              },
                                              child: _chatBody(),
                                            ),
                                          ),
                                        ),
                                        if (!_maximized)
                                          ..._resizeHandles(rect, screen),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chatBody() {
    final scheme = Theme.of(context).colorScheme;
    if (!_bubbleReady) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Save the note to enable chat for its bubble.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final isNoteChat = widget.noteId != null && widget.noteId!.isNotEmpty;
    return Column(
      children: [
        // Inline compaction dividers
        if (_compactionEvents.isNotEmpty)
          ..._compactionEvents.map((c) => _compactionRow(c, scheme)).toList(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${isNoteChat ? "Note chat" : "Bubble chat"} · ${widget.noteTitle}',
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Expanded(
          child:
              _messages.isEmpty
                  ? Center(
                    child: Text(
                      isNoteChat
                          ? 'Ask about this note or its sources.'
                          : 'Ask about this bubble\'s knowledge.',
                      textAlign: TextAlign.center,
                    ),
                  )
                  : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return Align(
                        alignment:
                            m.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                m.isUser
                                    ? scheme.primary
                                    : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              m.isUser
                                  ? Text(
                                    m.text,
                                    style: TextStyle(color: scheme.onPrimary),
                                  )
                                  : GptMarkdown(
                                    m.text,
                                    style: TextStyle(color: scheme.onSurface),
                                  ),
                        ),
                      );
                    },
                  ),
        ),
        if (_sending) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ask… (Enter sends)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _historyLimit > 0 ? Icons.history : Icons.history_toggle_off,
                          size: 20,
                        ),
                        tooltip: _historyLimit > 0
                            ? 'History limit: $_historyLimit (tap to disable)'
                            : 'History off (tap to enable)',
                        onPressed: () {
                          setState(() {
                            _historyLimit = _historyLimit > 0 ? 0 : 10;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactionRow(CompactionEvent c, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.compress, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Conversation compacted ${c.messageCount} messages. Summary: ${c.summary}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.clear, size: 16),
            onPressed: () => _toggleCompaction(c),
            tooltip: 'Clear and re-expand',
          ),
        ],
      ),
    );
  }

  List<Widget> _resizeHandles(Rect rect, Size screen) {
    Widget handle({
      required MouseCursor cursor,
      required void Function(Offset d) onDelta,
      double? left,
      double? right,
      double? top,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onDelta(d.delta),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    return [
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, left: d.dx),
      ),
      handle(
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: 0,
        bottom: _edge * 2,
        width: _edge,
        onDelta: (d) => _resize(rect, screen, right: d.dx),
      ),
      handle(
        cursor: SystemMouseCursors.resizeUpDown,
        left: _edge * 2,
        right: _edge * 2,
        bottom: 0,
        height: _edge,
        onDelta: (d) => _resize(rect, screen, bottom: d.dy),
      ),
      handle(
        cursor: SystemMouseCursors.resizeDownLeft,
        left: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        onDelta: (d) => _resize(rect, screen, left: d.dx, bottom: d.dy),
      ),
      handle(
        cursor: SystemMouseCursors.resizeDownRight,
        right: 0,
        bottom: 0,
        width: _edge * 3,
        height: _edge * 3,
        onDelta: (d) => _resize(rect, screen, right: d.dx, bottom: d.dy),
      ),
    ];
  }

  Widget _titleBar(ColorScheme scheme, Rect rect, Size screen) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => _move(rect, screen, d.delta),
      onDoubleTap: _toggleMaximized,
      child: MouseRegion(
        cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.move,
        child: Container(
          height: _titleBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Chat · Bubble',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _maximized ? 'Restore size' : 'Maximize',
                icon: Icon(
                  _maximized ? Icons.close_fullscreen : Icons.open_in_full,
                  size: 18,
                ),
                onPressed: _toggleMaximized,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _collapsed ? 'Expand' : 'Collapse',
                icon: Icon(
                  _collapsed ? Icons.unfold_more : Icons.unfold_less,
                  size: 18,
                ),
                onPressed: () => setState(() => _collapsed = !_collapsed),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Close (Esc)',
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
