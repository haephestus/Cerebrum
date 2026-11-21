import 'package:cerebrum/features/reader/reader.dart';
import 'package:cerebrum/common/widgets/floating_window.dart';
import 'package:flutter/material.dart';

/// A draggable, resizable window that hosts [Reader] on top of the editor.
///
/// Must be a DIRECT child of a [Stack] (it returns a `Positioned.fill`).
/// Chrome (drag/resize/collapse/maximize/focus ring/state persistence) comes
/// from [FloatingWindow]; this widget only supplies the Reader body and the
/// reader-specific "open a different document" action.
///
/// Changing [fileFingerprint] swaps the Reader (keyed on the fingerprint).
class FloatingReaderWindow extends StatelessWidget {
  final String fileFingerprint;
  final int? page;
  final bool visible;
  final VoidCallback onClose;
  final VoidCallback onChangeFile;

  /// Focus node of the Reader's vim keys. The host (editor scaffold) keeps it so
  /// `r` / Ctrl+w can move focus here; clicking in the window also takes it.
  final FocusNode? readerFocusNode;

  /// Esc in the idle Reader: the host should hand focus back to the editor.
  final VoidCallback? onReleaseFocus;

  const FloatingReaderWindow({
    super.key,
    required this.fileFingerprint,
    required this.visible,
    required this.onClose,
    required this.onChangeFile,
    this.page,
    this.readerFocusNode,
    this.onReleaseFocus,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingWindow(
      visible: visible,
      title: 'Reader',
      leadingIcon: Icons.menu_book,
      focusNode: readerFocusNode,
      onClose: onClose,
      minSize: const Size(360, 320),
      actions: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Open a different document',
          icon: const Icon(Icons.swap_horiz, size: 18),
          onPressed: onChangeFile,
        ),
      ],
      child: Reader(
        key: ValueKey(fileFingerprint),
        fileFingerprint: fileFingerprint,
        page: page,
        focusNode: readerFocusNode,
        onReleaseFocus: onReleaseFocus,
        // Embedded in editor scaffold: back should go to the file picker, not
        // pop the editor route.
        onBack: onChangeFile,
      ),
    );
  }
}
