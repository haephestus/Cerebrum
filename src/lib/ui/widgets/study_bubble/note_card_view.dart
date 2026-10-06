import 'dart:io';

import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

/// Whether a note's analysis is up to date, stale, missing, turned off, or
/// unverifiable right now. Each state is a real daemon/cached fact — `unknown`
/// means "we could not verify", never an invented label.
enum AnalysisDisplayStatus { current, stale, needsAnalysis, off, unknown }

/// What kind of body preview a card should render. Decided by the page from
/// the note's actual first-page content — never guessed here.
enum NotePreviewKind { text, checklist, image, drawing, table }

/// One checklist row for [NotePreviewKind.checklist].
class NoteChecklistItem {
  final String text;
  final bool checked;
  const NoteChecklistItem({required this.text, required this.checked});
}

/// One row of a [NotePreviewKind.table] preview — just the first few cells
/// as plain strings, enough for a compact teaser grid. Not the real table
/// layout; just a hint that "this note has a table".
class NoteTablePreviewRow {
  final List<String> cells;
  const NoteTablePreviewRow(this.cells);
}

/// The card's body preview: exactly one of these is populated, matching
/// [kind]. Built by the page (from the note's document/pages), never inferred
/// inside the card widget.
class NotePreview {
  final NotePreviewKind kind;
  final String? text; // kind == text
  final List<NoteChecklistItem> checklistItems; // kind == checklist
  final int checklistOverflowCount; // items beyond what's shown, 0 if none
  final String? imagePath; // kind == image (local file path or resolved URL)
  final List<String> tableHeaders; // kind == table
  final List<NoteTablePreviewRow> tableRows; // kind == table
  final int tableOverflowRowCount; // rows beyond what's shown, 0 if none

  const NotePreview.text(String value)
    : kind = NotePreviewKind.text,
      text = value,
      checklistItems = const [],
      checklistOverflowCount = 0,
      imagePath = null,
      tableHeaders = const [],
      tableRows = const [],
      tableOverflowRowCount = 0;

  const NotePreview.checklist(
    this.checklistItems, {
    this.checklistOverflowCount = 0,
  }) : kind = NotePreviewKind.checklist,
       text = null,
       imagePath = null,
       tableHeaders = const [],
       tableRows = const [],
       tableOverflowRowCount = 0;

  const NotePreview.image(String path)
    : kind = NotePreviewKind.image,
      text = null,
      checklistItems = const [],
      checklistOverflowCount = 0,
      imagePath = path,
      tableHeaders = const [],
      tableRows = const [],
      tableOverflowRowCount = 0;

  const NotePreview.drawing()
    : kind = NotePreviewKind.drawing,
      text = null,
      checklistItems = const [],
      checklistOverflowCount = 0,
      imagePath = null,
      tableHeaders = const [],
      tableRows = const [],
      tableOverflowRowCount = 0;

  const NotePreview.table({
    required this.tableHeaders,
    required this.tableRows,
    this.tableOverflowRowCount = 0,
  }) : kind = NotePreviewKind.table,
       text = null,
       checklistItems = const [],
       checklistOverflowCount = 0,
       imagePath = null;

  static const empty = NotePreview.text('');
}

/// A note card in the bubble notes list.
///
/// Cards carry the daemon-derived analysis state (see
/// [AnalysisDisplayStatus]), the cached gap rollup count, and local facts
/// (snippet, last edit, unsynced dirty state). Everything shown is passed in
/// by the page; this widget never guesses a status itself.
class NoteCardView extends StatelessWidget {
  final Map<String, dynamic> data;
  final NotePreview preview;
  final AnalysisDisplayStatus analysis;
  final int? gapCount;
  final String? lastEdited;
  final bool isSelected;
  final bool isOpening;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const NoteCardView({
    super.key,
    required this.data,
    this.preview = NotePreview.empty,
    required this.analysis,
    required this.gapCount,
    required this.lastEdited,
    required this.isSelected,
    required this.isOpening,
    required this.accentColor,
    required this.onTap,
    required this.onDoubleTap,
    required this.onOpen,
    required this.onDelete,
  });

  String get _title =>
      (data['title'] as String?)?.trim().isNotEmpty == true
          ? data['title'].toString().trim()
          : 'Untitled';

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
    // Image/drawing previews get a thumbnail alongside the text column
    // instead of inline text, so the row layout branches on preview kind.
    final hasVisualThumb =
        preview.kind == NotePreviewKind.image ||
        preview.kind == NotePreviewKind.drawing;

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color:
              isSelected
                  ? context.cerebrum.surface.cardSurfaceSelected
                  : context.cerebrum.surface.cardSurface,
          borderRadius: BorderRadius.circular(14),
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
                          style: TextStyle(
                            color: context.cerebrum.text.onDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildBodyPreview(context),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _AnalysisChip(status: analysis),
                            if (_dirty)
                              const _MetaChip(
                                icon: Icons.cloud_upload_outlined,
                                label: 'Unsynced',
                              ),
                            if (gapCount != null)
                              _MetaChip(
                                icon: Icons.insights,
                                label:
                                    '$gapCount ${gapCount == 1 ? 'gap' : 'gaps'}',
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
                  if (hasVisualThumb) ...[
                    const SizedBox(width: 8),
                    _ThumbnailBox(preview: preview),
                  ],
                  IconButton(
                    icon:
                        isOpening
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Icon(
                              Icons.open_in_new,
                              color: context.cerebrum.text.onDark.withValues(
                                alpha: 0.7,
                              ),
                              size: 18,
                            ),
                    tooltip: 'Open note',
                    onPressed: isOpening ? null : onOpen,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: context.cerebrum.text.onDark.withValues(
                        alpha: 0.5,
                      ),
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

  /// The body preview under the title. Branches on [preview.kind]: plain
  /// text (unchanged from before), a mini checklist, a compact table teaser,
  /// or — for image/drawing, where the real preview is the thumbnail
  /// rendered beside the text column — a short type label instead of trying
  /// to cram a snippet in.
  Widget _buildBodyPreview(BuildContext context) {
    switch (preview.kind) {
      case NotePreviewKind.text:
        final text = preview.text ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.cerebrum.text.onDark.withValues(alpha: 0.6),
            fontSize: 12,
            height: 1.3,
          ),
        );

      case NotePreviewKind.checklist:
        final items = preview.checklistItems;
        if (items.isEmpty) return const SizedBox.shrink();
        // Cap the rows shown so a 20-item list doesn't blow out card height;
        // the rest is folded into a "+N more" line.
        const maxShown = 3;
        final shown = items.take(maxShown).toList();
        final remaining =
            (items.length - maxShown).clamp(0, items.length) +
            preview.checklistOverflowCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in shown) _ChecklistRow(item: item),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text(
                  '+$remaining more',
                  style: TextStyle(
                    color: context.cerebrum.text.onDark.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        );

      case NotePreviewKind.table:
        final headers = preview.tableHeaders;
        final rows = preview.tableRows;
        if (headers.isEmpty && rows.isEmpty) return const SizedBox.shrink();
        // Compact teaser grid: header row + up to a couple of data rows,
        // each cell truncated to one line. This is NOT the real table
        // widget — just enough to signal "this note has a table" at a
        // glance.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headers.isNotEmpty)
              _TablePreviewRow(cells: headers, bold: true),
            for (final row in rows) _TablePreviewRow(cells: row.cells),
            if (preview.tableOverflowRowCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${preview.tableOverflowRowCount} more rows',
                  style: TextStyle(
                    color: context.cerebrum.text.onDark.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        );

      case NotePreviewKind.image:
        return Text(
          'Photo',
          style: TextStyle(
            color: context.cerebrum.text.onDark.withValues(alpha: 0.5),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        );

      case NotePreviewKind.drawing:
        return Text(
          'Drawing',
          style: TextStyle(
            color: context.cerebrum.text.onDark.withValues(alpha: 0.5),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        );
    }
  }
}

/// One checklist line: a small static checkbox glyph (not interactive — this
/// is a preview, not the editor) plus strikethrough text when checked.
class _ChecklistRow extends StatelessWidget {
  final NoteChecklistItem item;

  const _ChecklistRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final onDark = context.cerebrum.text.onDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 14,
            color: onDark.withValues(alpha: item.checked ? 0.4 : 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onDark.withValues(alpha: item.checked ? 0.4 : 0.75),
                fontSize: 12,
                decoration: item.checked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the compact table teaser: a fixed number of cells rendered
/// side by side, each truncated to a single line. Column count/widths here
/// are a rough approximation, not a real table layout — this is a card
/// preview, not the editor's table.
///
/// AGENT TODO: this renders every cell in the row via equal `Expanded`
/// slices. If real tables in this app tend to have many columns (the
/// "Data Structures" example note has 5), consider capping to the first
/// 2-3 columns instead so cells don't get squeezed unreadably thin on a
/// narrow card. Not done here since the right cap depends on how wide
/// cards actually render at runtime — check on a real device/window size.
class _TablePreviewRow extends StatelessWidget {
  final List<String> cells;
  final bool bold;

  const _TablePreviewRow({required this.cells, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final onDark = context.cerebrum.text.onDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          for (final cell in cells)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  cell,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onDark.withValues(alpha: bold ? 0.8 : 0.6),
                    fontSize: 11,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small square thumbnail for image/drawing previews, shown beside the text
/// column. Image notes render the actual file; drawing notes render a
/// placeholder icon until ink thumbnails are available from the list payload
/// (see loadNotes — list responses omit ink to stay cheap).
class _ThumbnailBox extends StatelessWidget {
  final NotePreview preview;

  const _ThumbnailBox({required this.preview});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: context.cerebrum.text.onDark.withValues(alpha: 0.08),
        child:
            preview.kind == NotePreviewKind.image && preview.imagePath != null
                ? _imageThumb(preview.imagePath!)
                : Icon(
                  Icons.brush,
                  size: 22,
                  color: context.cerebrum.text.onDark.withValues(alpha: 0.4),
                ),
      ),
    );
  }

  Widget _imageThumb(String path) {
    // Local cache paths and remote URLs both come through here (see
    // NoteImageResolver.resolve on the page); Image.network handles http(s),
    // Image.file handles anything else.
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
    );
  }
}

class _AnalysisChip extends StatelessWidget {
  final AnalysisDisplayStatus status;

  const _AnalysisChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AnalysisDisplayStatus.current => (
        'Analyzed',
        context.cerebrum.status.success,
      ),
      AnalysisDisplayStatus.stale => (
        'Stale analysis',
        context.cerebrum.brand.accent,
      ),
      AnalysisDisplayStatus.needsAnalysis => (
        'Needs analysis',
        context.cerebrum.status.danger,
      ),
      AnalysisDisplayStatus.off => (
        'Analysis off',
        context.cerebrum.status.neutral,
      ),
      AnalysisDisplayStatus.unknown => (
        'Unknown',
        context.cerebrum.status.neutral,
      ),
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
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
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
        color: context.cerebrum.text.onDark.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: context.cerebrum.text.onDark.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: context.cerebrum.text.onDark.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
