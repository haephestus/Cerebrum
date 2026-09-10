import 'package:flutter/material.dart';

/// Whether a note's analysis is up to date, stale, missing, turned off, or
/// unverifiable right now. Each state is a real daemon/cached fact — `unknown`
/// means "we could not verify", never an invented label.
enum AnalysisDisplayStatus { current, stale, needsAnalysis, off, unknown }

/// A note card in the bubble notes list.
///
/// Cards carry the daemon-derived analysis state (see
/// [AnalysisDisplayStatus]), the cached gap rollup count, and local facts
/// (snippet, last edit, unsynced dirty state). Everything shown is passed in
/// by the page; this widget never guesses a status itself.
class NoteCardView extends StatelessWidget {
  final Map<String, dynamic> data;
  final AnalysisDisplayStatus analysis;
  final int? gapCount;
  final String? lastEdited;
  final bool isSelected;
  final bool isOpening;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const NoteCardView({
    super.key,
    required this.data,
    required this.analysis,
    required this.gapCount,
    required this.lastEdited,
    required this.isSelected,
    required this.isOpening,
    required this.accentColor,
    required this.onTap,
    required this.onOpen,
    required this.onDelete,
  });

  String get _title => (data['title'] as String?)?.trim().isNotEmpty == true
      ? data['title'].toString().trim()
      : 'Untitled';

  String get _snippet => (data['snippet'] as String?)?.trim() ?? '';

  bool get _dirty => data['dirty'] == true;

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF26262C) : const Color(0xFF1F1F23),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: const Color(0xFF6C4FCE), width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Attention rail: real analysis/gap signal from the page.
            Container(height: 4, color: accentColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_snippet.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _AnalysisChip(status: analysis),
                            if (_dirty) const _MetaChip(
                              icon: Icons.cloud_upload_outlined,
                              label: 'Unsynced',
                            ),
                            if (gapCount != null)
                              _MetaChip(
                                icon: Icons.insights,
                                label: '$gapCount ${gapCount == 1 ? 'gap' : 'gaps'}',
                              ),
                            if (lastEdited != null)
                              () {
                                final t = DateTime.tryParse(lastEdited!);
                                return t == null
                                    ? const SizedBox.shrink()
                                    : _MetaChip(
                                        icon: Icons.schedule,
                                        label: _relativeTime(t),
                                      );
                              }(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: isOpening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.open_in_new,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 18,
                          ),
                    tooltip: 'Open note',
                    onPressed: isOpening ? null : onOpen,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 18,
                    ),
                    tooltip: 'Delete note',
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisChip extends StatelessWidget {
  final AnalysisDisplayStatus status;

  const _AnalysisChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AnalysisDisplayStatus.current => ('Analyzed', const Color(0xFF2E7D32)),
      AnalysisDisplayStatus.stale => ('Stale analysis', const Color(0xFFC9A24B)),
      AnalysisDisplayStatus.needsAnalysis => ('Needs analysis', const Color(0xFFB3261E)),
      AnalysisDisplayStatus.off => ('Analysis off', const Color(0xFF757575)),
      AnalysisDisplayStatus.unknown => ('Unknown', const Color(0xFF9E9E9E)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
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