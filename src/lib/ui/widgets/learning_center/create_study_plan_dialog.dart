import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/api/planner_api.dart';
import 'package:cerebrum/ui/widgets/floating_modal.dart';

/// Form dialog for POST /study_plan/generate. `user_profile` and
/// `target_role` are required by the backend's StudyPlanRequest --
/// `context` and a free-text profile note are optional. I don't have
/// visibility into what shape user_profile is actually expected to be
/// (study_planner_inator.generate_study_plan takes it as a raw dict), so
/// this sends a minimal {"notes": "..."} or {} rather than guessing at
/// specific keys. If generate_study_plan expects particular fields
/// (e.g. current_level, hours_per_week, prior_experience), tell me and
/// I'll turn "Profile notes" into proper structured fields instead.
///
/// Used by the Learning Center's "New Plan" action.
class CreateStudyPlanDialog extends StatefulWidget {
  final String userId;
  const CreateStudyPlanDialog({super.key, required this.userId});

  @override
  State<CreateStudyPlanDialog> createState() => _CreateStudyPlanDialogState();
}

class _CreateStudyPlanDialogState extends State<CreateStudyPlanDialog> {
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
                decoration: InputDecoration(
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
                decoration: InputDecoration(
                  labelText: 'Profile notes (optional)',
                  hintText: 'Current level, hours/week available, etc.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: context.cerebrum.status.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
