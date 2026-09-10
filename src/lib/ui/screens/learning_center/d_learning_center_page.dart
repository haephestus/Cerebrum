import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/api/planner_api.dart';
import 'package:cerebrum/ui/screens/learning_center/study_plan_detail_page.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/mcq.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/flashcard.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/short_question.dart';
import 'package:cerebrum/ui/screens/learning_center/engrams/completion/long_questions.dart';
import 'package:cerebrum/ui/widgets/floating_modal.dart';
import 'package:cerebrum/ui/widgets/plan_portfolio_gantt.dart';

/// Learning Center — ONE page. Portfolio timeline on top (approved-plan
/// gantt with an upcoming-draft staging pane left), per-bubble engrams
/// beneath. No tabs — spec [[features/study-plan-annual-view]].
///
/// Backed by GET /study_plan/user/all (every status; drafts feed the
/// staging pane) and GET /learn/engrams/list.
class DLearningCenterPage extends StatefulWidget {
  final String userId;

  const DLearningCenterPage({super.key, required this.userId});

  @override
  State<DLearningCenterPage> createState() => _DLearningCenterPageState();
}

class _DLearningCenterPageState extends State<DLearningCenterPage> {
  late Future<EngramListResponse> _engramsFuture;
  late Future<List<Map<String, dynamic>>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _loadEngrams();
    _loadPlans();
  }

  void _loadEngrams() {
    _engramsFuture = LearningCenterApi.listEngrams(userId: widget.userId);
  }

  void _loadPlans() {
    _plansFuture = PlannerApi.getPlans(userId: widget.userId);
  }

  void _refreshEngrams() => setState(_loadEngrams);
  void _refreshPlans() => setState(_loadPlans);

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
      builder: (_) => _CreateStudyPlanDialog(userId: widget.userId),
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

  String _typeLabel(EngramType t) => switch (t) {
    EngramType.mcq => 'Multiple Choice',
    EngramType.flashcard => 'Flashcards',
    EngramType.shortQuestion => 'Short Questions',
    EngramType.longQuestion => 'Long Questions',
    EngramType.unknown => 'Other',
  };

  IconData _typeIcon(EngramType t) => switch (t) {
    EngramType.mcq => Icons.quiz_outlined,
    EngramType.flashcard => Icons.style_outlined,
    EngramType.shortQuestion => Icons.short_text,
    EngramType.longQuestion => Icons.article_outlined,
    EngramType.unknown => Icons.help_outline,
  };

  String _previewText(Engram e) {
    switch (e.type) {
      case EngramType.mcq:
        return (e.content as McqContent).stem;
      case EngramType.flashcard:
        return (e.content as FlashcardContent).front;
      case EngramType.shortQuestion:
        final c = e.content as ShortQuestionContent;
        return c.questions.isNotEmpty
            ? c.questions.first.stem
            : 'Short question set';
      case EngramType.longQuestion:
        return (e.content as LongQuestionContent).questionStem;
      case EngramType.unknown:
        return 'Untitled item';
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildGlobalOverview();
  }

  /// ONE rolling page — portfolio timeline on top (approved-plan gantt with
  /// an upcoming-draft staging pane), per-bubble engrams beneath.
  Widget _buildGlobalOverview() {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning Center')),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [_buildPlansSection(), _buildEngramsSection()],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePlanDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Plan'),
      ),
    );
  }

  Future<void> _refreshAll() async {
    _refreshPlans();
    _refreshEngrams();
    await Future.wait([_plansFuture, _engramsFuture]);
  }

  /// Portfolio timeline section: divider between the upcoming-draft staging
  /// pane (left, flat list — NO kanban columns) and the approved-plan gantt
  /// (right, calendar bars with predicted start dates).
  Widget _buildPlansSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${snapshot.error}'),
          );
        }
        final allPlans = snapshot.data ?? const <Map<String, dynamic>>[];
        return _buildPortfolioPane(allPlans);
      },
    );
  }

  Widget _buildPortfolioPane(List<Map<String, dynamic>> allPlans) {
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
      width: 240,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                    child: Text(
                      'Upcoming',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '${drafts.length} draft(s) awaiting approval',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: drafts.length,
                      itemBuilder: (context, i) {
                        final plan = drafts[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              plan['target_role']?.toString() ??
                                  'Untitled plan',
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'draft · v${plan['version'] ?? 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => _openPlan(plan),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }

  /// Per-bubble engrams section beneath the timeline.
  Widget _buildEngramsSection() {
    return FutureBuilder<EngramListResponse>(
      future: _engramsFuture,
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text(
                'Engrams',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snapshot.error}'),
              )
            else
              _buildEngramsList(context, snapshot.data!),
          ],
        );
      },
    );
  }

  /// Grouped-by-type engrams list. Embedded into the page ListView, so it
  /// never scrolls itself.
  Widget _buildEngramsList(BuildContext context, EngramListResponse response) {
    final engrams = response.engrams;
    if (engrams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('No engrams yet.'),
      );
    }

    // Grouped by TYPE only, for now. Grouping by upcoming/new/old
    // (due date) needs engram_mastery.state / next_due_at added to
    // the /engrams/list response first -- _sanitize_for_presentation
    // on the backend currently strips down to content/tags/level,
    // no mastery info at all.
    final grouped = <EngramType, List<Engram>>{};
    for (final e in engrams) {
      grouped.putIfAbsent(e.type, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children:
          grouped.entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: Icon(_typeIcon(entry.key)),
                title: Text(_typeLabel(entry.key)),
                subtitle: Text('${entry.value.length} item(s)'),
                children:
                    entry.value.map((e) {
                      return ListTile(
                        title: Text(_previewText(e)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openEngram(e),
                      );
                    }).toList(),
              ),
            );
          }).toList(),
    );
  }
}

/// Form dialog for POST /study_plan/generate. `user_profile` and
/// `target_role` are required by the backend's StudyPlanRequest --
/// `context` and a free-text profile note are optional. I don't have
/// visibility into what shape user_profile is actually expected to be
/// (study_planner_inator.generate_study_plan takes it as a raw dict), so
/// this sends a minimal {"notes": "..."} or {} rather than guessing at
/// specific keys. If generate_study_plan expects particular fields
/// (e.g. current_level, hours_per_week, prior_experience), tell me and
/// I'll turn "Profile notes" into proper structured fields instead.
class _CreateStudyPlanDialog extends StatefulWidget {
  final String userId;
  const _CreateStudyPlanDialog({required this.userId});

  @override
  State<_CreateStudyPlanDialog> createState() => _CreateStudyPlanDialogState();
}

class _CreateStudyPlanDialogState extends State<_CreateStudyPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _targetRoleController = TextEditingController();
  final _contextController = TextEditingController();
  final _profileNotesController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _targetRoleController.dispose();
    _contextController.dispose();
    _profileNotesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // PlannerApi.generatePlan takes positional args and expects
      // userProfile as Map<String, Map<dynamic, dynamic>> — nesting the
      // free-text note under a single key to satisfy that shape. If
      // generate_study_plan on the backend actually expects specific
      // structured keys (current_level, hours_per_week, etc.) rather
      // than a single nested note, swap this for those fields instead.
      // historicalPlanId is required with no null option in the current
      // signature — passing '' for a brand-new plan; if the backend
      // needs to distinguish "no history" from "history id is empty
      // string", that param should become nullable instead.
      await PlannerApi.generatePlan(
        widget.userId,
        {
          'notes': {'text': _profileNotesController.text.trim()},
        },
        _targetRoleController.text.trim(),
        _contextController.text.trim(),
        '',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not start plan generation: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingModal(
      title: 'New Study Plan',
      widthFactor: 0.8,
      heightFactor: 0.8,
      onClose: _submitting ? null : () => Navigator.of(context).pop(false),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child:
              _submitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Create'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _targetRoleController,
              decoration: const InputDecoration(
                labelText: 'Target role / goal',
                hintText: 'e.g. "Backend Engineer" or "MCAT prep"',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Target role is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Expanded so Context and Profile notes share the remaining
            // vertical space evenly, instead of collapsing to their
            // maxLines minimum -- this is the actual fix for "give the
            // user room to see what they're typing".
            Expanded(
              child: TextFormField(
                controller: _contextController,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Context (optional)',
                  hintText: 'Anything the planner should know up front',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextFormField(
                controller: _profileNotesController,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Profile notes (optional)',
                  hintText: 'Current level, hours/week available, etc.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
