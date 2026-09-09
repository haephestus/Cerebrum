import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// SCAFFOLD — an "AI feedback" custom block for inline, model-generated notes.
///
/// It is a NON-editable block (no delta): the user inserts it, triggers a
/// generation, and it renders the returned feedback read-only. All state lives
/// in node attributes so it round-trips through save/load like any other block
/// (see AppFlowyTextDriver.documentJson id/attribute handling).
///
/// What's deliberately left as TODO: the actual model call. `_generate` below
/// just writes a placeholder so the update path is proven; wire it to
/// LearningCenterApi (needs bubbleId/noteId/userId — plumb them in via a
/// provider or an injected callback) when the feature is real.
const String kAiBlockType = 'ai_feedback';
const String kAiPromptKey = 'ai_prompt';
const String kAiFeedbackKey = 'ai_feedback';
const String kAiStatusKey = 'ai_status'; // idle | loading | done | error

/// Builds an AI-feedback node. No delta — it isn't editable text.
Node aiBlockNode({String prompt = ''}) => Node(
      type: kAiBlockType,
      attributes: {
        kAiPromptKey: prompt,
        kAiFeedbackKey: '',
        kAiStatusKey: 'idle',
      },
    );

class AiBlockComponentBuilder extends BlockComponentBuilder {
  AiBlockComponentBuilder({super.configuration});

  // No delta requirement — this is a display block (cf. DividerBlockComponent).
  @override
  BlockComponentValidate get validate => (node) => true;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AiBlockComponentWidget(
      key: ValueKey(node),
      node: node,
      configuration: configuration,
    );
  }
}

class AiBlockComponentWidget extends BlockComponentStatefulWidget {
  const AiBlockComponentWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<AiBlockComponentWidget> createState() => _AiBlockComponentWidgetState();
}

class _AiBlockComponentWidgetState extends State<AiBlockComponentWidget> {
  Node get node => widget.node;

  EditorState get editorState =>
      Provider.of<EditorState>(context, listen: false);

  void _update(Map<String, dynamic> patch) {
    final tx = editorState.transaction
      ..updateNode(node, {...node.attributes, ...patch});
    editorState.apply(tx);
  }

  Future<void> _generate() async {
    _update({kAiStatusKey: 'loading'});
    // TODO(ai-block): replace this stub with a real model call
    // (LearningCenterApi) using the note's bubble/note/user ids + the prompt.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _update({
      kAiStatusKey: 'done',
      kAiFeedbackKey:
          'AI feedback will appear here once generation is wired up.',
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: node,
      builder: (context, _) {
        final status = node.attributes[kAiStatusKey] as String? ?? 'idle';
        final feedback = node.attributes[kAiFeedbackKey] as String? ?? '';
        final prompt = node.attributes[kAiPromptKey] as String? ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD8CFF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 16, color: Color(0xFF6C4BD8)),
                  const SizedBox(width: 6),
                  const Text('AI feedback',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B3B7A))),
                  const Spacer(),
                  if (status == 'loading')
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton(
                      onPressed: _generate,
                      child: Text(status == 'done' ? 'Regenerate' : 'Generate'),
                    ),
                ],
              ),
              if (prompt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(prompt,
                      style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.black54)),
                ),
              Text(
                feedback.isEmpty
                    ? 'No feedback yet — press Generate.'
                    : feedback,
                style: TextStyle(
                  fontSize: 13,
                  color: feedback.isEmpty ? Colors.black38 : Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
