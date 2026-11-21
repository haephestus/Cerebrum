import 'package:cerebrum/features/editor/helpers/analysis_mode_controller.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/common/widgets/floating_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating, focusable window that walks the analysis findings chunk by chunk.
///
/// This is the CHUNK-BY-CHUNK review surface (`n` / `N` through
/// [AnalysisModeController]); it is deliberately separate from the note
/// overview / full analysis side panel, which stays the general, whole-note
/// view. The window reads the controller as its single source of truth, so
/// stepping the editor (`n` / `N`) and stepping here stay in lock-step.
///
/// Must be a DIRECT child of the editor scaffold's [Stack].
///
/// Keys while focused:
///   j / k or ↓ / ↑   move between the chunk header and its findings
///   Ctrl+d / Ctrl+u   page the findings list
///   g / G             jump to the chunk header / last finding
///   n / N             next / previous chunk
///   Esc / q           hand focus back to the editor
class AnalysisFindingsWindow extends StatefulWidget {
  final bool visible;
  final AnalysisModeController analysis;
  final FocusNode? focusNode;
  final VoidCallback onClose;
  final VoidCallback? onReleaseFocus;
  final VoidCallback onOpenFullPanel;

  const AnalysisFindingsWindow({
    super.key,
    required this.visible,
    required this.analysis,
    required this.onClose,
    required this.onOpenFullPanel,
    this.focusNode,
    this.onReleaseFocus,
  });

  @override
  State<AnalysisFindingsWindow> createState() => _AnalysisFindingsWindowState();
}

class _AnalysisFindingsWindowState extends State<AnalysisFindingsWindow> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  final List<GlobalKey> _findingKeys = [];

  /// -1 = the chunk header/excerpt tile, >=0 = findings[index]. The header is
  /// a tile precisely so `k` / `g` can reach the very top of the list.
  int _selected = -1;
  String? _lastChunkId;

  @override
  void initState() {
    super.initState();
    widget.analysis.addListener(_onAnalysisChanged);
    _lastChunkId = widget.analysis.current?.chunkId;
  }

  @override
  void didUpdateWidget(AnalysisFindingsWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analysis != widget.analysis) {
      oldWidget.analysis.removeListener(_onAnalysisChanged);
      widget.analysis.addListener(_onAnalysisChanged);
    }
  }

  @override
  void dispose() {
    widget.analysis.removeListener(_onAnalysisChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onAnalysisChanged() {
    final chunkId = widget.analysis.current?.chunkId;
    if (chunkId != _lastChunkId) {
      _lastChunkId = chunkId;
      _selected = -1;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _findings() {
    final raw = widget.analysis.current?.chunk['findings'];
    if (raw is! List) return const [];
    return [
      for (final f in raw)
        if (f is Map) f.cast<String, dynamic>(),
    ];
  }

  void _select(int i, int count) {
    final next = i.clamp(-1, count - 1);
    if (next == _selected) return;
    setState(() => _selected = next);
    _revealSelected();
  }

  /// Keep one key per finding so [Scrollable.ensureVisible] can reveal the
  /// selected row without estimating row heights.
  void _ensureFindingKeys(int n) {
    while (_findingKeys.length < n) {
      _findingKeys.add(GlobalKey());
    }
    if (_findingKeys.length > n) {
      _findingKeys.removeRange(n, _findingKeys.length);
    }
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selected < 0) {
        // Header tile selected: scroll fully to the top, not just "into view".
        if (_scroll.hasClients) {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
        return;
      }
      if (_selected >= _findingKeys.length) return;
      final ctx = _findingKeys[_selected].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  void _page(double direction) {
    if (!_scroll.hasClients) return;
    final step = _scroll.position.viewportDimension * 0.85 * direction;
    _scroll.animateTo(
      (_scroll.offset + step).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed;
    final key = event.logicalKey;
    final findings = _findings();

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyQ) {
      widget.onReleaseFocus?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      if (hk.isShiftPressed) {
        widget.analysis.prev();
      } else {
        widget.analysis.next();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1, findings.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1, findings.length);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyD) {
      _page(1);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyU) {
      _page(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      _select(hk.isShiftPressed ? findings.length - 1 : -1, findings.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.analysis.current;
    final findings = _findings();
    _ensureFindingKeys(findings.length);
    if (findings.isNotEmpty && _selected >= findings.length) {
      _selected = findings.length - 1;
    }
    final tokens = context.cerebrum;

    return FloatingWindow(
      visible: widget.visible,
      title:
          cur == null
              ? 'Analysis findings'
              : 'Findings · chunk ${widget.analysis.index + 1} / '
                  '${widget.analysis.count}',
      leadingIcon: Icons.fact_check_outlined,
      focusNode: widget.focusNode,
      onClose: widget.onClose,
      minSize: const Size(380, 300),
      initialSizeFraction: const Size(0.34, 0.72),
      defaultTopLeftFraction: const Offset(0.02, 0.14),
      actions: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous chunk (N)',
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: widget.analysis.hasChunks ? widget.analysis.prev : null,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Next chunk (n)',
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: widget.analysis.hasChunks ? widget.analysis.next : null,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Open full analysis',
          icon: const Icon(Icons.open_in_new, size: 18),
          onPressed: widget.onOpenFullPanel,
        ),
      ],
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => widget.focusNode?.requestFocus(),
          child: Scrollbar(
            controller: _scroll,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                if (cur == null)
                  Text(
                    'No analysis chunks. Run analysis to review findings.',
                    style: TextStyle(fontSize: 12, color: tokens.text.muted),
                  )
                else ...[
                  _ChunkHeaderTile(
                    key: _headerKey,
                    chunk: cur.chunk,
                    pageId: cur.pageId,
                    selected: _selected < 0,
                    onTap: () {
                      _select(-1, findings.length);
                      widget.focusNode?.requestFocus();
                    },
                  ),
                  const SizedBox(height: 12),
                  if (findings.isEmpty)
                    Text(
                      'No findings for this chunk.',
                      style: TextStyle(fontSize: 12, color: tokens.text.muted),
                    )
                  else
                    for (var i = 0; i < findings.length; i++)
                      _FindingRow(
                        key: _findingKeys[i],
                        index: i,
                        finding: findings[i],
                        selected: i == _selected,
                        onTap: () {
                          _select(i, findings.length);
                          widget.focusNode?.requestFocus();
                        },
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'j/k findings · n/N chunk · g/G top/bottom · Esc release',
                    style: TextStyle(fontSize: 10, color: tokens.text.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chunk context (excerpt + metadata) as a real, selectable tile — same
/// shape as a finding row so `k` / `g` can land on it and scroll to the very
/// top of the list.
class _ChunkHeaderTile extends StatelessWidget {
  const _ChunkHeaderTile({
    super.key,
    required this.chunk,
    required this.pageId,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> chunk;
  final String pageId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cerebrum;
    final scheme = Theme.of(context).colorScheme;
    final excerpt = (chunk['excerpt'] ?? '').toString().trim();
    final chunkId = (chunk['chunkId'] ?? '').toString().trim();
    final blockIds = (chunk['blockIds'] as List?)?.cast<String>() ?? const [];
    final meta = [
      if (chunkId.isNotEmpty) chunkId,
      if (pageId.isNotEmpty) 'page $pageId',
      '${blockIds.length} block${blockIds.length == 1 ? '' : 's'}',
    ].join(' · ');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (excerpt.isNotEmpty) ...[
              Text(
                excerpt,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              meta,
              style: TextStyle(fontSize: 10, color: tokens.text.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    super.key,
    required this.index,
    required this.finding,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Map<String, dynamic> finding;
  final bool selected;
  final VoidCallback onTap;

  static Color _severityColor(BuildContext context, String severity) {
    final status = context.cerebrum.status;
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        return status.danger;
      case 'medium':
      case 'moderate':
      case 'low':
      case 'minor':
        return status.warning;
      default:
        return status.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = (finding['severity'] ?? 'unknown').toString();
    final type = (finding['type'] ?? 'finding').toString().replaceAll('_', ' ');
    final gap = finding['gap_explanation'] as String?;
    final claim = finding['student_claim'] as String?;
    final detail = gap ?? claim;
    final color = _severityColor(context, severity);
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. $type',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  severity.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
