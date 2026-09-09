import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/ui/screens/study_bubble/d_study_bubble_page.dart';

import 'gap_repository.dart';

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

  const StudyBubblesSummaryCard({
    super.key,
    required this.onOpenBubble,
    required this.onViewAll,
    this.gapRepository = const LiveGapRepository(),
  });

  @override
  State<StudyBubblesSummaryCard> createState() =>
      _StudyBubblesSummaryCardState();
}

class _StudyBubblesSummaryCardState extends State<StudyBubblesSummaryCard> {
  List<dynamic> _bubbles = [];
  bool _loading = true;
  String? _error;

  /// bubbleId -> attention score.
  Map<String, int> _attentionByBubble = const {};

  @override
  void initState() {
    super.initState();
    _fetch();
    _loadAttention();
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
    final newBubble = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DStudyBubblePage(addMode: true)),
    );

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
      return const Color(0xFFB9B4CC);
    }

    if (attention <= 3) {
      return const Color(0xFFC9A24B);
    }

    return const Color(0xFFB3261E);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 40,
        child: Row(
          children: [
            Text(
              'Couldn\'t load.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 11),
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
      return SizedBox(
        height: 40,
        child: Center(
          child: IconButton(
            tooltip: 'Create study bubble',
            onPressed: _createBubble,
            icon: const Icon(Icons.add_circle_outline),
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Larger tiles to fill the available height
        const minTileSize = 40.0;
        const maxTileSize = 56.0;
        const gap = 6.0;

        final availableWidth = constraints.maxWidth;

        // Calculate how many columns can fit
        final columns = (availableWidth / (minTileSize + gap)).floor().clamp(
          1,
          _bubbles.length,
        );

        // Calculate tile width based on available space
        final tileWidth = ((availableWidth - (columns - 1) * gap) / columns)
            .clamp(minTileSize, maxTileSize);

        // Show max 6 bubbles, with "more" indicator if needed
        const maxDisplay = 6;
        final displayBubbles = _bubbles.take(maxDisplay).toList();
        final hasMore = _bubbles.length > maxDisplay;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.start,
          children: [
            for (final bubble in displayBubbles)
              _BubbleRingChip(
                title: _titleOf(bubble),
                ringColor: _ringColor(_idOf(bubble)),
                size: tileWidth,
                onTap: () {
                  widget.onOpenBubble(Map<String, dynamic>.from(bubble as Map));
                },
              ),
            if (hasMore)
              _BubbleRingChip(
                title: '+${_bubbles.length - maxDisplay}',
                ringColor: const Color(0xFFB9B4CC),
                size: tileWidth,
                onTap: widget.onViewAll,
              ),
          ],
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

  const _BubbleRingChip({
    required this.title,
    required this.ringColor,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.grey.shade200, // Transparent background
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
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
                  color: const Color(0xFF6C4FCE),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
