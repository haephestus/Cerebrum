import 'package:flutter/material.dart';

/// A study-bubble card on the bubbles grid.
///
/// The page decides the accent color (real attention signal from
/// GapRepository); this widget only draws what it's told. `noteCount` and
/// `lastUpdated` are local NoteStore facts — null means unknown, and the card
/// hides the chip rather than inventing a number.
class CardView extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Opens the edit-dialog for this bubble (name/description/etc).
  final VoidCallback? onEdit;

  /// Attention rail color: neutral / amber / red from the gap rollup.
  /// When null the rail renders in the neutral color (no signal is not a
  /// defect, it's the starting state).
  final Color? accentColor;

  /// Local note count for this bubble. Null hides the chip.
  final int? noteCount;

  /// Most recent local note update. Null hides the chip.
  final DateTime? lastUpdated;

  const CardView({
    super.key,
    required this.data,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
    this.accentColor,
    this.noteCount,
    this.lastUpdated,
  });

  static const _neutralColor = Color(0xFFB9B4CC);

  @override
  Widget build(BuildContext context) {
    final domains =
        (data['domains'] as List?)?.whereType<String>().toList() ??
        const <String>[];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F23),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Attention rail: thin bar at the top of the card.
            Container(
              height: 4,
              color: accentColor ?? _neutralColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        color: const Color(0xFF2A2A30),
                        onSelected: (value) {
                          if (value == 'edit' && onEdit != null) {
                            onEdit!();
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        itemBuilder: (context) => [
                          if (onEdit != null)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      data["name"] ?? 'Untitled bubble',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data["description"] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (noteCount != null)
                          _MetaChip(
                            icon: Icons.notes,
                            label: '$noteCount ${noteCount == 1 ? 'note' : 'notes'}',
                          ),
                        for (final d in domains.take(2))
                          _MetaChip(icon: Icons.tag, label: d),
                        if (lastUpdated != null)
                          _MetaChip(
                            icon: Icons.schedule,
                            label: _relativeTime(lastUpdated!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}