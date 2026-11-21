import 'package:cerebrum/common/keyboard_nav/keyboard_nav.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/features/study_bubble/api/bubbles_api.dart';
import 'package:cerebrum/features/study_bubble/widgets/create_study_bubble_dialog.dart';

import '../helpers/gap_repository.dart';

/// Dashboard-facing summary of the user's study bubbles.
///
/// Displays compact, icon-only bubble tiles that adapt to the available
/// dashboard space. Bubble names are available through hover tooltips.
///
/// Each ring's color is a real attention signal from GapRepository:
/// - no data -> neutral
/// - low attention -> amber
/// - higher attention -> red
class StudyBubblesSummaryCard extends StatefulWidget {
  final void Function(Map<String, dynamic> bubble) onOpenBubble;
  final VoidCallback onViewAll;
  final GapRepository gapRepository;
  final FocusNode? focusNode;

  const StudyBubblesSummaryCard({
    super.key,
    required this.onOpenBubble,
    required this.onViewAll,
    this.gapRepository = const LiveGapRepository(),
    this.focusNode,
  });

  @override
  State<StudyBubblesSummaryCard> createState() =>
      _StudyBubblesSummaryCardState();
}

class _StudyBubblesSummaryCardState extends State<StudyBubblesSummaryCard> {
  List<dynamic> _bubbles = [];
  bool _loading = true;
  String? _error;
  int _navIndex = 0;

  /// bubbleId -> attention score.
  Map<String, int> _attentionByBubble = const {};

  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'home-bubbles-nav'));

  @override
  void initState() {
    super.initState();
    _fetch();
    _loadAttention();
  }

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await BubblesApi.fetchBubbles();

      if (!mounted) return;

      setState(() {
        _bubbles = data;
        _loading = false;
        _navIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadAttention() async {
    try {
      final cached = await widget.gapRepository.cached();

      if (!mounted) return;

      setState(() {
        _attentionByBubble = {
          for (final e in cached.entries) e.key: e.value.attention,
        };
      });
    } catch (_) {
      // No gap data yet.
      // Rings remain neutral rather than guessing.
    }
  }

  Future<void> _createBubble() async {
    final newBubble = await showCreateStudyBubbleDialog(context);

    if (newBubble != null && mounted) {
      setState(() {
        _bubbles.insert(0, newBubble);
      });
    }
  }

  String _titleOf(dynamic bubble) {
    if (bubble is Map) {
      final name = bubble['name'] ?? bubble['title'];

      if (name is String && name.trim().isNotEmpty) {
        return name;
      }
    }

    return 'Untitled bubble';
  }

  String? _idOf(dynamic bubble) {
    if (bubble is Map && bubble['id'] != null) {
      return '${bubble['id']}';
    }

    return null;
  }

  /// Ring color from the real attention score.
  ///
  /// No score -> neutral.
  /// 1-3 -> amber.
  /// 4+ -> red.
  Color _ringColor(String? bubbleId) {
    final attention = bubbleId == null ? null : _attentionByBubble[bubbleId];

    if (attention == null || attention == 0) {
      return context.cerebrum.status.neutralSoft;
    }

    if (attention <= 3) {
      return context.cerebrum.brand.accent;
    }

    return context.cerebrum.status.danger;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardNavScope(
      focusNode: _focusNode,
      onLeft:
          () => setState(() {
            if (_navIndex > 0) _navIndex--;
          }),
      onRight: () => setState(() => _navIndex++),
      onUp:
          () => setState(() {
            if (_navIndex > 0) _navIndex--;
          }),
      onDown: () => setState(() => _navIndex++),
      onActivate: _activateFocused,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: Container(
          // Removed background color, border, and border radius
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Removed the title row - label moved to homepage
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  void _activateFocused() {
    if (_bubbles.isEmpty) return;
    const maxDisplay = 6;
    final displayBubbles = _bubbles.take(maxDisplay).toList();
    final hasMore = _bubbles.length > maxDisplay;
    final count = displayBubbles.length + (hasMore ? 1 : 0);
    if (count == 0) return;
    final idx = _navIndex.clamp(0, count - 1);
    if (hasMore && idx == displayBubbles.length) {
      widget.onViewAll();
      return;
    }
    widget.onOpenBubble(Map<String, dynamic>.from(displayBubbles[idx] as Map));
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couldn\'t load.',
              style: TextStyle(
                color: context.cerebrum.status.dangerDeep,
                fontSize: 11,
              ),
            ),
            TextButton(
              onPressed: _fetch,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    if (_bubbles.isEmpty) {
      return Center(
        child: IconButton(
          tooltip: 'Create study bubble',
          onPressed: _createBubble,
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Bigger tiles now that the card has real vertical room
        const minTileSize = 64.0;
        const maxTileSize = 96.0;
        const gap = 10.0;

        final availableWidth = constraints.maxWidth;

        final columns = (availableWidth / (minTileSize + gap)).floor().clamp(
          1,
          _bubbles.length,
        );

        final tileWidth = ((availableWidth - (columns - 1) * gap) / columns)
            .clamp(minTileSize, maxTileSize);

        const maxDisplay = 6;
        final displayBubbles = _bubbles.take(maxDisplay).toList();
        final hasMore = _bubbles.length > maxDisplay;
        final total = displayBubbles.length + (hasMore ? 1 : 0);
        if (total > 0) _navIndex = _navIndex.clamp(0, total - 1);

        return Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.start,
            children: [
              for (var i = 0; i < displayBubbles.length; i++)
                _BubbleRingChip(
                  title: _titleOf(displayBubbles[i]),
                  ringColor: _ringColor(_idOf(displayBubbles[i])),
                  size: tileWidth,
                  focused: _focusNode.hasFocus && _navIndex == i,
                  onTap: () {
                    setState(() => _navIndex = i);
                    widget.onOpenBubble(
                      Map<String, dynamic>.from(displayBubbles[i] as Map),
                    );
                  },
                ),
              if (hasMore)
                _BubbleRingChip(
                  title: '+${_bubbles.length - maxDisplay}',
                  ringColor: context.cerebrum.status.neutralSoft,
                  size: tileWidth,
                  focused:
                      _focusNode.hasFocus && _navIndex == displayBubbles.length,
                  onTap: () {
                    setState(() => _navIndex = displayBubbles.length);
                    widget.onViewAll();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BubbleRingChip extends StatelessWidget {
  final String title;
  final Color ringColor;
  final VoidCallback onTap;
  final double size;
  final bool focused;

  const _BubbleRingChip({
    required this.title,
    required this.ringColor,
    required this.onTap,
    required this.size,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: context.cerebrum.surface.overlay, // Transparent background
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    focused
                        ? context.cerebrum.brand.accent
                        : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: size * 0.42,
                height: size * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2),
                ),
                child: Icon(
                  Icons.bubble_chart,
                  size: size * 0.18,
                  color: context.cerebrum.brand.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
