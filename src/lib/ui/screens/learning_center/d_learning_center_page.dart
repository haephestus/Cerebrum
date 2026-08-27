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

/// Two modes, one widget:
///   - bubbleId/noteId BOTH null  -> global dashboard: every study plan
///     (any status) + every engram across all bubbles/notes. This is what
///     the sidebar entry point should use.
///   - bubbleId/noteId provided   -> scoped view for one note, same
///     behavior as before this change.
///
/// Matches how the backend's GET /learn/engrams/list already scopes by
/// presence/absence of bubble_id/note_id -- this widget just mirrors
/// that at the UI layer instead of forcing a separate "dashboard" screen.
///
/// Plans tab: fetches ALL plans regardless of status in one call
/// (GET /study_plan/user/all) and filters client-side via a status
/// chip row -- see _statusFilter. Previously this only ever loaded
/// status == 'active' plans (GET /study_plan/user/active), which is
/// why draft/completed/archived plans never showed up here.
class DLearningCenterPage extends StatefulWidget {
  final String? bubbleId;
  final String? noteId;
  final String userId;

  const DLearningCenterPage({
    super.key,
    this.bubbleId,
    this.noteId,
    required this.userId,
  });

  bool get isGlobal => bubbleId == null && noteId == null;

  @override
  State<DLearningCenterPage> createState() => _DLearningCenterPageState();
}

class _DLearningCenterPageState extends State<DLearningCenterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<EngramListResponse> _engramsFuture;
  late Future<List<Map<String, dynamic>>> _plansFuture;

  /// 'all' or a specific status string ('active', 'draft', 'completed',
  /// 'archived', ...). Chips are built dynamically from whatever statuses
  /// are actually present in the fetched plans, so this isn't a fixed enum.
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEngrams();
    _loadPlans();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadEngrams() {
    _engramsFuture = LearningCenterApi.listEngrams(
      userId: widget.userId,
      bubbleId: widget.bubbleId,
      noteId: widget.noteId,
    );
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

  Color _statusColor(String status, BuildContext context) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'draft':
        return Colors.blueGrey;
      case 'completed':
        return Colors.blue;
      case 'archived':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isGlobal ? 'Learning Center' : 'Note Engrams'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Study Plans'), Tab(text: 'Engrams')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildPlansTab(), _buildEngramsTab()],
        ),
        // Only meaningful on the Plans tab -- hidden while on Engrams.
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            if (_tabController.index != 0) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: _showCreatePlanDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Plan'),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlansTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allPlans = snapshot.data!;

        if (allPlans.isEmpty) {
          return const Center(child: Text('No study plans yet.'));
        }

        // Build the chip set from whatever statuses are actually present,
        // so we never show an empty "Archived" chip for a user who has
        // never archived anything, and we never miss a status someone
        // adds on the backend later without a client update.
        final presentStatuses =
            <String>{
                for (final p in allPlans) (p['status'] as String?) ?? 'active',
              }.toList()
              ..sort();
        final chipOptions = ['all', ...presentStatuses];

        // If a previously-selected filter no longer has any matching
        // plans (e.g. last archived plan got deleted), fall back to 'all'
        // instead of silently showing an empty list forever.
        if (_statusFilter != 'all' &&
            !presentStatuses.contains(_statusFilter)) {
          _statusFilter = 'all';
        }

        final visible =
            _statusFilter == 'all'
                ? allPlans
                : allPlans
                    .where(
                      (p) =>
                          ((p['status'] as String?) ?? 'active') ==
                          _statusFilter,
                    )
                    .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      chipOptions.map((s) {
                        final selected = s == _statusFilter;
                        final count =
                            s == 'all'
                                ? allPlans.length
                                : allPlans
                                    .where(
                                      (p) =>
                                          ((p['status'] as String?) ??
                                              'active') ==
                                          s,
                                    )
                                    .length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${s == 'all' ? 'All' : _capitalize(s)} ($count)',
                            ),
                            selected: selected,
                            onSelected:
                                (_) => setState(() => _statusFilter = s),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
            Expanded(
              child:
                  visible.isEmpty
                      ? Center(
                        child: Text(
                          'No ${_statusFilter == 'all' ? '' : '$_statusFilter '}plans.',
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: () async => _refreshPlans(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final plan = visible[i];
                            final status =
                                (plan['status'] as String?) ?? 'active';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: const Icon(Icons.map_outlined),
                                title: Text(
                                  plan['target_role']?.toString() ??
                                      'Untitled plan',
                                ),
                                subtitle: Text(
                                  '${plan['total_duration_months'] ?? '?'} months · v${plan['version'] ?? 1}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(
                                          status,
                                          context,
                                        ).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _capitalize(status),
                                        style: TextStyle(
                                          color: _statusColor(status, context),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _openPlan(plan),
                              ),
                            );
                          },
                        ),
                      ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEngramsTab() {
    return FutureBuilder<EngramListResponse>(
      future: _engramsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final engrams = snapshot.data!.engrams;
        if (engrams.isEmpty) {
          return const Center(child: Text('No engrams yet.'));
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

        return RefreshIndicator(
          onRefresh: () async => _refreshEngrams(),
          child: ListView(
            padding: const EdgeInsets.all(16),
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
          ),
        );
      },
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
