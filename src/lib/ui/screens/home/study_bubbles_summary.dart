import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/ui/screens/study_bubble/d_study_bubble_page.dart';

/// Dashboard-facing summary of the user's study bubbles.
///
/// This intentionally does NOT reimplement DStudyBubbleHome's grid --
/// it's a compact preview (top N bubbles) with two ways out:
///   - tap a bubble -> onOpenBubble(bubble), same contract DesktopUI
///     already wires up for DStudyBubbleHome.onOpenBubble
///   - "View all" -> onViewAll(), hands off to the full Study Bubble page
///
/// NOTE: the bubble map's display-name key isn't confirmed from any repo
/// file I've seen -- CardView/BubblesApi weren't in the upload set. This
/// tries `name` then `title` then falls back to a placeholder so it never
/// crashes on an unexpected shape. If the real key differs, swap it in
/// _titleOf below.
class StudyBubblesSummaryCard extends StatefulWidget {
  final void Function(Map<String, dynamic> bubble) onOpenBubble;
  final VoidCallback onViewAll;
  final int maxPreview;

  const StudyBubblesSummaryCard({
    super.key,
    required this.onOpenBubble,
    required this.onViewAll,
    this.maxPreview = 3,
  });

  @override
  State<StudyBubblesSummaryCard> createState() =>
      _StudyBubblesSummaryCardState();
}

class _StudyBubblesSummaryCardState extends State<StudyBubblesSummaryCard> {
  List<dynamic> _bubbles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
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

  Future<void> _createBubble() async {
    // Same push-based creation flow DStudyBubbleHome.addBubbleWidget uses --
    // this goes through Navigator directly rather than the sidebar's
    // selectedPage switch, since that's how bubble creation already works.
    final newBubble = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DStudyBubblePage(addMode: true)),
    );
    if (newBubble != null && mounted) {
      setState(() => _bubbles.insert(0, newBubble));
    }
  }

  String _titleOf(dynamic bubble) {
    if (bubble is Map) {
      final name = bubble['name'] ?? bubble['title'];
      if (name is String && name.trim().isNotEmpty) return name;
    }
    return 'Untitled bubble';
  }

  String _subtitleOf(dynamic bubble) {
    if (bubble is Map) {
      final count = bubble['source_count'] ?? bubble['sources'];
      if (count != null) return '$count sources';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3DEF2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Study bubbles',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: widget.onViewAll,
                    child: const Text('View all'),
                  ),
                  IconButton(
                    tooltip: 'New study bubble',
                    onPressed: _createBubble,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Couldn\'t load study bubbles.',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                  TextButton(onPressed: _fetch, child: const Text('Retry')),
                ],
              ),
            )
          else if (_bubbles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No study bubbles yet.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Group related notes and sources into a bubble to start '
                    'tracking your understanding.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _createBubble,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create study bubble'),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (final bubble in _bubbles.take(widget.maxPreview))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap:
                            () => widget.onOpenBubble(
                              Map<String, dynamic>.from(bubble as Map),
                            ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3DEF2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.bubble_chart,
                                  size: 18,
                                  color: Color(0xFF6C4FCE),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _titleOf(bubble),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_subtitleOf(bubble).isNotEmpty)
                                      Text(
                                        _subtitleOf(bubble),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_bubbles.length > widget.maxPreview)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '+${_bubbles.length - widget.maxPreview} more',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
