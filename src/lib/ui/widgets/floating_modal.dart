import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

/// Shared "floating window" chrome: a centered, rounded card sized as a
/// percentage of the available screen rather than fixed pixels, so it
/// scales with window size instead of overflowing on small screens or
/// looking tiny on large ones.
///
/// Width is a true percentage of screen width. Height is a CEILING
/// (up to heightFactor of screen height) that the content can shrink
/// below -- a small form (like a create-plan dialog) shouldn't be forced
/// to fill 80% of the screen just because a sidebar-heavy settings page
/// needs that much room. Both end up feeling "spacious" for their own
/// content instead of sharing one rigid size.
///
/// Works both embedded directly in a widget tree (e.g. a selected sidebar
/// page) and shown via showDialog -- it doesn't assume a barrier/route
/// context, it's just the visual card. Pass onClose to control what the
/// close button does; defaults to Navigator.pop(context), which is only
/// correct when there's actually a route to pop (i.e. when shown via
/// showDialog/Navigator.push). If you embed this directly as a page body
/// with no pushed route, pass an explicit onClose instead or omit
/// showCloseButton.
class FloatingModal extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double widthFactor;
  final double heightFactor;
  final VoidCallback? onClose;
  final bool showCloseButton;

  const FloatingModal({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.widthFactor = 0.8,
    this.heightFactor = 0.8,
    this.onClose,
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenSize.width * widthFactor,
          maxHeight: screenSize.height * heightFactor,
        ),
        child: Material(
          color: context.cerebrum.surface.raised,
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          shadowColor: context.cerebrum.text.strong.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // HEADER
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (showCloseButton)
                      IconButton(
                        onPressed: onClose ?? () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // BODY -- Flexible so it shrinks to content instead of
                // always claiming the full heightFactor ceiling.
                Flexible(child: child),

                // ACTIONS (optional bottom row, e.g. Cancel/Create)
                if (actions != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
