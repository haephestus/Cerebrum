import 'package:flutter/material.dart';
import 'package:cerebrum/ui/editor/controllers/note_editor_controller.dart';
import 'package:cerebrum/ui/editor/controllers/text_editing_driver.dart';
import 'package:cerebrum/ui/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/editor/screens/drawing_layer.dart';

/// The editor surface: whatever [TextEditingDriver.buildEditor] renders,
/// stacked with the drawing layer. No Scaffold, no AppBar, no save logic,
/// no analysis panel, and — importantly — no knowledge of which engine
/// it's showing. This is the widget you get regardless of whether
/// `controller.driver` is AppFlowy or super_editor.
class EditorSurface extends StatelessWidget {
  const EditorSurface({super.key, required this.controller});

  final NoteEditorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        debugPrint('[SURFACE] outer AnimatedBuilder rebuild');
        final drawingEnabled = controller.drawingEnabled;
        final driver = controller.driver;
        final vimAware = driver is VimModeAware ? driver : null;

        return Stack(
          children: [
            AbsorbPointer(
              absorbing: drawingEnabled,
              child: driver.buildEditor(context),
            ),
            IgnorePointer(
              ignoring: !drawingEnabled,
              child: NoteDrawingLayer(notifier: controller.drawingNotifier),
            ),
            // Only shown for engines that actually have modal editing —
            // super_editor won't hit this until/unless it implements
            // VimModeAware too.
            if (!drawingEnabled && vimAware != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: AnimatedBuilder(
                  // Explicitly cast to 'VimModeAware' if type promotion is failing
                  animation: (vimAware as VimModeAware).vimMode,
                  builder: (context, __) {
                    debugPrint('[SURFACE] badge-only rebuild');
                    return _ModeBadge(
                      mode: (vimAware as VimModeAware).vimMode.value,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final VimMode mode;

  @override
  Widget build(BuildContext context) {
    final isNormal = mode == VimMode.normal;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isNormal ? Colors.blueGrey : Colors.teal,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isNormal ? 'NORMAL' : 'INSERT',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
