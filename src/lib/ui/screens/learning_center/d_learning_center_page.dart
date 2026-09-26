import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/planner_api.dart';
import 'package:cerebrum/api/metrics_api.dart';
import 'package:cerebrum/models/performance_metrics.dart';
import 'package:cerebrum/ui/widgets/learning_center/dash/due_today_strip.dart';
import 'package:cerebrum/ui/widgets/learning_center/dash/performance_panel.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/ui/screens/learning_center/study_plan_detail_page.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/engrams_section.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/mcq.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/flashcard.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/short_question.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/long_questions.dart';
import 'package:cerebrum/ui/widgets/learning_center/create_study_plan_dialog.dart';
import 'package:cerebrum/ui/widgets/learning_center/gantt/plan_portfolio_gantt.dart';

/// Learning Center — ONE page: the dashboard carousel on top, then
/// per-bubble engrams beneath. No tabs — spec
/// [[features/study-plan-annual-view]].
///
/// The dashboard carousel (_buildDashboardCarousel) is a fixed-height,
/// dot-indicated PageView with three swipeable pages —
///   - Due today (DueTodayStrip, ui/widgets/learning_center/due_today_strip.dart):
///     a full carousel page, not a bare strip. Real due filtering: only
///     engrams whose `scheduled_at`/`due_at` has arrived by now, soonest
///     first. Nothing scheduled → the strip's honest "Nothing due today."
///     Never a synthesized due time (Phase 2 dashboard honesty rule).
///   - Performance (PerformancePanel,
///     ui/widgets/learning_center/performance_panel.dart): weak-point
///     concepts come from the real engram tag grouping; mastery/streak
///     come from MetricsApi via _metricsFuture. Until the daemon
///     performance endpoint exists
///     ([[features/engram-performance-report]]),
///     MetricsApi.getSummary throws, _fetchMetrics degrades to null, and
///     the panel shows "--" — never a fabricated number.
///   - Plans: the portfolio timeline — approved plans as calendar-anchored
///     bars (PlanPortfolioGantt,
///     ui/widgets/learning_center/plan_portfolio_gantt.dart) with the
///     upcoming-draft staging pane left (_buildUpcomingPane). This pane
///     owns ALL draft UI on the page; tap a bar or draft to open the full
///     detail page. The carousel is the portfolio's ONLY surface — there
///     is no standalone Plans section below, so the same gantt never
///     renders twice. The phase-level (Focus) gantt is gone; the detail
///     page owns that view now.
///
/// Backed by GET /study_plan/user/all (every status; drafts feed the
/// staging pane), GET /learn/engrams/list, GET /study_plan/{id}/progress
/// (per-plan KPI chips inside the portfolio gantt), and the optional
/// MetricsApi.getSummary.
class DLearningCenterPage extends StatefulWidget {
  final String userId;

  const DLearningCenterPage({super.key, required this.userId});

  @override
  State<DLearningCenterPage> createState() => _DLearningCenterPageState();
}

class _DLearningCenterPageState extends State<DLearningCenterPage> {
  late Future<EngramsViewData> _engramsFuture;
  late Future<List<Map<String, dynamic>>> _plansFuture;
  late Future<PerformanceMetrics?> _metricsFuture;

  final PageController _dashboardPageController = PageController();
  int _dashboardPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadEngrams();
    _loadPlans();
    _loadMetrics();
  }

  void _loadEngrams() {
    _engramsFuture = _fetchEngramsView();
  }

  Future<EngramsViewData> _fetchEngramsView({
    int? cognitiveLevel,
    String? severity,
  }) async {
    final response = await LearningCenterApi.listEngrams(
      userId: widget.userId,
      cognitiveLevel: cognitiveLevel,
      severity: severity,
    );

    // Local-first name resolution. Bubble names come from the daemon; note
    // titles from the local index (no daemon round-trip per note).
    final bubbleNames = <String, String>{};
    try {
      final bubbles = await BubblesApi.fetchBubbles();
      for (final b in bubbles.whereType<Map>()) {
        if (b['id'] != null) {
          final name = b['name'] ?? b['title'];
          bubbleNames['${b['id']}'] =
              name is String && name.trim().isNotEmpty ? name : '${b['id']}';
        }
      }
    } catch (_) {
      // Daemon unreachable — bubble names degrade to raw ids below.
    }

    final noteTitles = <String, Map<String, String>>{};
    try {
      for (final bubbleId in bubbleNames.keys) {
        final notes = await NoteStore.listNotes(bubbleId);
        noteTitles[bubbleId] = {
          for (final n in notes)
            if (n['note_id'] != null)
              '${n['note_id']}': '${n['title'] ?? 'Untitled'}',
        };
      }
    } catch (_) {
      // Note titles degrade to raw note ids below.
    }

    return EngramsViewData(
      response: response,
      bubbleNames: bubbleNames,
      noteTitles: noteTitles,
    );
  }

  Future<void> _statusUpdate(planId, status, userId) async {
    try {
      await PlannerApi.statusUpdate(
        planId: planId,
        status: status,
        userId: userId,
      );
      _refreshPlans();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to approve plan $e")));
      }
    }
  }

  void _loadPlans() {
    _plansFuture = PlannerApi.getPlans(userId: widget.userId);
  }

  void _loadMetrics() {
    _metricsFuture = _fetchMetrics();
  }

  Future<PerformanceMetrics?> _fetchMetrics() async {
    try {
      return await MetricsApi.getSummary(userId: widget.userId);
    } catch (_) {
      // Metrics are optional until the daemon performance endpoint exists.
      return null;
    }
  }

  void _refreshEngrams() => setState(_loadEngrams);
  void _refreshPlans() => setState(_loadPlans);
  void _refreshMetrics() => setState(_loadMetrics);

  void _openEngram(Engram e) async {
    Widget page;
    switch (e.type) {
      case EngramType.mcq:
        page = McqCompletionPage(engram: e, userId: widget.userId);
        break;
      case EngramType.flashcard:
        page = FlashcardCompletionPage(engram: e, userId: widget.userId);
        break;
      case EngramType.shortQuestion:
        page = ShortQuestionCompletionPage(engram: e, userId: widget.userId);
        break;
      case EngramType.longQuestion:
        page = LongQuestionCompletionPage(engram: e, userId: widget.userId);
        break;
      case EngramType.unknown:
        return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _refreshEngrams();
  }

  void _openPlan(Map<String, dynamic> planSummary) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => StudyPlanDetailPage(
              planId: planSummary['plan_id'] as String,
              userId: widget.userId,
            ),
      ),
    );
    _refreshPlans();
  }

  Future<void> _showCreatePlanDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => CreateStudyPlanDialog(userId: widget.userId),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plan generation started — this runs in the background '
            'and may take a bit to finish.',
          ),
        ),
      );
      _refreshPlans();
    }
  }

  @override
  void dispose() {
    _dashboardPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning Center')),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 8),
            _buildDashboardCarousel(),
            EngramsSection(
              future: _engramsFuture,
              refetch: _fetchEngramsView,
              onEngramTap: _openEngram,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshAll() async {
    _refreshPlans();
    _refreshEngrams();
    _refreshMetrics();
    await Future.wait([_plansFuture, _engramsFuture, _metricsFuture]);
  }

  // ---------------------------------------------------------------------
  // Dashboard carousel
  //
  // The three pages answer three different questions:
  //   1. What should I work on?      -> Due today
  //   2. Where do I need attention?  -> Performance
  //   3. Where is my plan at a glance? -> Plans portfolio timeline
  //
  // Keep them as separate swipeable pages rather than stacking the panels.
  // The carousel has a stable height so PageView does not fight Flutter's
  // unbounded vertical constraints. Each page can scroll internally if its
  // content is taller than the viewport.
  // ---------------------------------------------------------------------

  Widget _buildDashboardCarousel() {
    const pages = 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 440,
            child: PageView(
              controller: _dashboardPageController,
              onPageChanged: (index) {
                if (mounted) {
                  setState(() => _dashboardPageIndex = index);
                }
              },
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: _buildPerformancePanel(),
                      ),
                      SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: _buildDueTodayCard(),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: _buildPortfolioCarouselPage(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages, (index) {
              final active = index == _dashboardPageIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      active
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Due-today as a complete carousel page rather than a bare strip.
  Widget _buildDueTodayCard() {
    return FutureBuilder<EngramsViewData>(
      future: _engramsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final due = _dueTodayEngrams(snapshot.data!.response.engrams);

        return DueTodayStrip(
          engrams: due,
          typeIconOf: engramTypeIcon,
          typeLabelOf: engramTypeLabel,
          previewTextOf: engramPreview,
          onTap: _openEngram,
        );
      },
    );
  }

  /// Engrams whose daemon `scheduled_at`/`due_at` has arrived by now,
  /// soonest due first. Absent schedule → the item is not "due" — it is
  /// simply not scheduled yet, and the strip says so honestly.
  List<Engram> _dueTodayEngrams(List<Engram> all) {
    final now = DateTime.now();
    final due =
        all.where((e) {
            final at = e.scheduledAt;
            return at != null && !at.isAfter(now);
          }).toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return due;
  }

  /// Performance summary. Weak points come from real engram tags; optional
  /// mastery/streak metrics come from MetricsApi when that endpoint exists.
  Widget _buildPerformancePanel() {
    return FutureBuilder<EngramsViewData>(
      future: _engramsFuture,
      builder: (context, engramsSnapshot) {
        final weakPoints =
            engramsSnapshot.hasData
                ? engramsSnapshot.data!.response.engrams
                    .where(isWeakPoint)
                    .toList()
                : const <Engram>[];

        return FutureBuilder<PerformanceMetrics?>(
          future: _metricsFuture,
          builder: (context, metricsSnapshot) {
            return PerformancePanel(
              metrics: metricsSnapshot.data,
              weakPointConcepts: _weakPointConceptCounts(weakPoints),
              onConceptTap: (concept) => _openWeakConcept(concept, weakPoints),
            );
          },
        );
      },
    );
  }

  /// The portfolio timeline as a full carousel page — wrapped in the
  /// same surface/border card as the Performance page. Empty / error
  /// states degrade honestly instead of faking a timeline.
  Widget _buildPortfolioCarouselPage() {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }
          final allPlans = snapshot.data ?? const <Map<String, dynamic>>[];
          return _buildPlanPane(allPlans);
        },
      ),
    );
  }

  Map<String, int> _weakPointConceptCounts(List<Engram> weakPoints) {
    final counts = <String, int>{};
    for (final e in weakPoints) {
      final concept = weakPointConcept(e);
      counts[concept] = (counts[concept] ?? 0) + 1;
    }
    return counts;
  }

  void _openWeakConcept(String concept, List<Engram> weakPoints) {
    final match = weakPoints.firstWhere(
      (e) => weakPointConcept(e) == concept,
      orElse: () => weakPoints.first,
    );
    _openEngram(match);
  }

  void _scrollToEngramsSection() {
    // TODO: wire this to an actual scroll position (e.g. give the page's
    // ListView a ScrollController and scroll to the Engrams section's
    // context) once "Browse all engrams" needs to do more than remind you
    // the section already exists further down the page.
  }

  // ---------------------------------------------------------------------
  // Plans portfolio pane (carousel page 2). Approved plans render as
  // calendar bars (PlanPortfolioGantt) with an upcoming-draft staging pane
  // left — UNCHANGED from the annual-view spec; this pane owns ALL draft
  // UI on the page. The carousel is its only surface: there is no
  // standalone Plans section below, so the same gantt never renders twice.
  // The phase-level (Focus) gantt is gone; StudyPlanDetailPage owns that
  // view now.
  // ---------------------------------------------------------------------

  /// Timeline: approved plans as calendar bars, upcoming drafts staged
  /// left. This pane owns ALL draft UI on the page.
  Widget _buildPlanPane(List<Map<String, dynamic>> allPlans) {
    final drafts =
        allPlans
            .where((p) => ((p['status'] as String?) ?? 'active') == 'draft')
            .toList();
    final approved =
        allPlans
            .where((p) => ((p['status'] as String?) ?? 'active') != 'draft')
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Approved plans on the calendar, upcoming drafts staged to the left.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 380,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUpcomingPane(drafts),
              Container(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                child: PlanPortfolioGantt(
                  plans: approved,
                  userId: widget.userId,
                  onPlanTap: _openPlan,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Left staging space: upcoming drafts as a flat card list. Tapping a card
  /// opens the plan detail; the official approve/activate path is the separate
  /// draft-review feature [[features/study-plan-draft-review]].
  Widget _buildUpcomingPane(List<Map<String, dynamic>> drafts) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      width: 240,
      child:
          drafts.isEmpty
              ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upcoming',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming drafts.\nGenerate a plan to start one.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Row(
                      children: [
                        Text(
                          'Upcoming',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Spacer(),
                        // NOTE: Temporary placement
                        IconButton(
                          onPressed: _showCreatePlanDialog,
                          icon: Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      drafts.length == 1
                          ? '${drafts.length} draft awaiting approval'
                          : '${drafts.length} draft(s) awaiting approval',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cerebrum.status.danger,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: drafts.length,
                      itemBuilder: (context, i) {
                        final plan = drafts[i];
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 18),
                          child: GestureDetector(
                            // 1. Change to onSecondaryTapDown to capture cursor details
                            onSecondaryTapDown: (TapDownDetails details) {
                              showMenu(
                                context: context,
                                // 2. Position the menu precisely at the cursor location
                                position: RelativeRect.fromLTRB(
                                  details.globalPosition.dx,
                                  details.globalPosition.dy,
                                  details.globalPosition.dx + 1,
                                  details.globalPosition.dy + 1,
                                ),
                                items: [
                                  PopupMenuItem(
                                    value: 'approve',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check,
                                          color:
                                              context.cerebrum.status.success,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Approve Plan'),
                                      ],
                                    ),
                                  ),
                                ],
                              ).then((selectedValue) {
                                // 3. Handle the selection
                                if (selectedValue == 'approve') {
                                  _statusUpdate(
                                    plan['plan_id'],
                                    'active',
                                    widget.userId,
                                  );
                                }
                              });
                            },
                            child: ListTile(
                              dense: true,
                              title: Text(
                                plan['target_role']?.toString() ??
                                    'Untitled plan',
                                style: const TextStyle(fontSize: 13),
                              ),
                              onTap: () => _openPlan(plan),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
