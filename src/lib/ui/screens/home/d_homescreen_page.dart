import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/user_session.dart';
import 'package:cerebrum/ui/screens/editor/editor_scaffold.dart';
import 'package:cerebrum/ui/screens/home/dashboard_pulse_strip.dart';
import 'package:cerebrum/ui/screens/home/file_library_launcher.dart';
import 'package:cerebrum/ui/screens/home/gap_findings_carousel.dart';
import 'package:cerebrum/ui/screens/home/gap_models.dart';
import 'package:cerebrum/ui/screens/home/priority_gap_card.dart';
import 'package:cerebrum/ui/screens/home/quickview.dart';
import 'package:cerebrum/ui/screens/home/study_bubbles_summary.dart';
import 'package:cerebrum/ui/screens/home/upcoming_engrams.dart';
import 'package:flutter/material.dart';

/// Dashboard layout (top to bottom):
///   1. Pulse strip        -- real counts only, "where do things stand?"
///   2. Upcoming engrams    -- unchanged component; self-hides when empty
///   3. Continue + attention row:
///        left  = Quickview        -- the STRONG widget: resume a note
///                                     and/or continue a suggested reading
///        right = PriorityGapCard  -- compact "needs attention" notice
///                StudyBubblesSummaryCard -- beneath it
///   4. Gap reports & findings -- paged carousel, one bubble per page
///   5. File library launcher  -- opens the full library in a dialog
///
/// Two features from the redesign brief are NOT implemented below because
/// building them would mean guessing at APIs/data this codebase doesn't
/// show me. Both are left as comments here (not this file's own local
/// comments buried in some other widget) so they're easy to find in one
/// place.
///
/// TODO(agent) #1 -- Engram performance & results report.
/// Ask: a widget summarizing how the person is doing on engrams over time
/// (accuracy trends, completion rate, per-type breakdowns). State (verified
/// 2026-09-10): the DAEMON already persists every raw datum the report needs —
/// `engram_attempts` plus the per-type response tables (`mcq_responses`,
/// `flashcard_responses`, short/long responses) with score, `is_correct`,
/// `attempted_at`, `grader` — but exposes NO results endpoint; the only
/// engram call on this client is `LearningCenterApi.listEngrams` (the
/// upcoming/scheduled queue). So this is blocked on a daemon route, not on
/// data. Tracked: daemon-side `engram-performance-api` spec + client-side
/// [[.steward/features/engram-performance-report]] (Phase 2). Slot the card
/// here, between the gap carousel and the file library launcher, once the
/// endpoint exists.
///
/// TODO(agent) #2 -- Surface unaddressed notes (open gaps + untouched
/// reading) to the forefront.
/// Ask: bring notes forward whose gaps are still open AND whose suggested
/// reading hasn't been opened. State (verified 2026-09-10): `GapItem` still
/// has no resolved/dismissed flag and `GapEvidence` has no reading-opened
/// marker (gap_models.dart), and the DAEMON persists neither — gap data
/// derives from each analysis run, and `suggested_readings` records
/// candidate/accept/dismiss but no `opened_at`. Those two state pieces are
/// daemon work (note-analysis + suggested-reading follow-ons), tracked in the
/// Cerebrum-Daemon vault; the client display is then a filtered rollup over
/// GapRepository (resolved == false AND reading.openedAt == null) — no new
/// architecture, just the two fields threaded through gap_models.dart and
/// gap_extract.dart. Own spec:
/// [[.steward/features/unaddressed-notes-surface]].
///
/// TODO(agent) #3 -- Syncfusion PDF viewer for suggested reading.
/// Ask: opening a suggested-reading gap (Quickview's "Continue reading" and
/// wherever else a reading gets opened) should launch the Syncfusion PDF
/// viewer (`syncfusion_flutter_pdfviewer`), fetching the source's page data
/// and chunk data so it can scroll/highlight directly to the section the
/// gap finding referenced. Blocked on: the package isn't in this project's
/// pubspec as far as any file shown to me indicates, and I don't have the
/// API shape for fetching a suggested source's page/chunk data (no such
/// call appears in learning_center_api.dart or knowledgebase_api.dart in
/// what was uploaded). Once both exist, Quickview._openReading() is the
/// single place to wire it -- it currently just shows an honest "not wired
/// up yet" message instead of pretending to open something.
class DHomescreen extends StatefulWidget {
  /// Same bubble-open contract DesktopUI wires for DStudyBubbleHome: opening a
  /// bubble from the summary card routes into the full Study Bubble page.
  final void Function(Map<String, dynamic> bubble) onOpenBubble;

  /// "View all" on the bubbles summary hands off to the Study Bubbles page.
  final VoidCallback onOpenStudyBubbles;

  const DHomescreen({
    super.key,
    required this.onOpenBubble,
    required this.onOpenStudyBubbles,
  });

  @override
  State<DHomescreen> createState() => _DHomescreenState();
}

class _DHomescreenState extends State<DHomescreen> {
  String? _username;

  static const double _wideBreakpoint = 720;
  static const double _mainColumnHeight = 460;

  @override
  void initState() {
    super.initState();
    // The app bar greets a real identity, never the hardcoded "User".
    UserSession.getUsername().then((name) {
      if (mounted) setState(() => _username = name);
    });
  }

  /// Opens the note behind a gap's evidence, same resume flow Quickview
  /// uses. A gap with no note evidence (shouldn't happen -- every gap is
  /// grounded per the homepage spec) is a no-op rather than a crash.
  ///
  /// When the gap's evidence names blocks (chunk-sourced fallback gaps:
  /// [GapEvidence.blockIds]/[GapEvidence.pageId]), the editor opens directly
  /// in analysis-review mode on that chunk so the user lands on the gap
  /// itself instead of the note's first line.
  Future<void> _handleReviewGap(GapItem item) async {
    final evidence = item.evidence.isNotEmpty ? item.evidence.first : null;
    final bubbleId = evidence?.bubbleId;
    if (evidence == null || bubbleId == null) return;
    final note = await NoteStore.readNote(bubbleId, evidence.noteId);
    if (note == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => EditorScaffold(
              note: note,
              startBlockIds: evidence.blockIds,
              startPageId: evidence.pageId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _username == null ? 'Welcome back' : 'Welcome back, $_username',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Layer 2: untouched -- same component, same show/hide rule.
              const UpcomingEngramsSection(),

              const SizedBox(height: 16),

              // Layer 3: continuity (strong) beside attention (compact),
              // reflowing to a stack below the width breakpoint.
              LayoutBuilder(
                builder: (context, constraints) {
                  final quickview = const SizedBox(
                    height: _mainColumnHeight,
                    child: Quickview(),
                  );
                  final sideColumn = SizedBox(
                    height: _mainColumnHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Layer 1: real counts only, no fabricated streak/mastery.
                        const DashboardPulseStrip(),
                        const SizedBox(height: 16),
                        PriorityGapCard(onReview: _handleReviewGap),
                        const SizedBox(height: 16),
                        // Label moved here from the card
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              //better label? idk?
                              'Your favorite study bubbles',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1526),
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onOpenStudyBubbles,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'View all',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6C4FCE),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        //TODO: (agent)show the most active bubbles here(filter by most
                        // edited)
                        Expanded(
                          child: StudyBubblesSummaryCard(
                            onOpenBubble: widget.onOpenBubble,
                            onViewAll: widget.onOpenStudyBubbles,
                          ),
                        ),
                      ],
                    ),
                  );

                  if (constraints.maxWidth >= _wideBreakpoint) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: quickview),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: sideColumn),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      quickview,
                      const SizedBox(height: 16),
                      sideColumn,
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // Layer 4: paged gap findings, most-recently-analyzed bubble
              // first (proxy recency -- see gap_findings_carousel.dart).
              const GapFindingsCarousel(),

              const SizedBox(height: 16),

              // --- TODO(agent) #1: Engram performance & results report ---
              // See the detailed note at the top of this file. Slot a new
              // card here once a performance-history API exists.

              // --- TODO(agent) #2: Unaddressed notes surfaced here ---
              // See the detailed note at the top of this file. Needs a
              // resolved-flag + reading-opened marker before this can be
              // more than a re-display of the same gap data shown above.

              // Layer 5: file library is its own thing now -- a launcher,
              // not embedded dashboard real estate.
              const FileLibraryLauncher(),
            ],
          ),
        ),
      ),
    );
  }
}
