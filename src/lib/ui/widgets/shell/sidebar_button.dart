import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

class SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onPressed;

  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.collapsed = false,
    required this.onPressed,
  });

  @override
  State<SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<SidebarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // Selected items get a highlight color; others use the normal on-dark color.
    final Color iconColor =
        widget.selected
            ? context.cerebrum.text.strong
            : context.cerebrum.text.faint;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 92, // fixed sidebar button width
        child: Row(
          children: [
            const SizedBox(width: 8), // left padding where the bar used to be
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: iconColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  overlayColor: Colors.transparent,
                ),
                onPressed: widget.onPressed,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 26, color: iconColor),
                    // Only reserve space for / show the label when expanded
                    if (!widget.collapsed) ...[
                      const SizedBox(height: 8),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _hovering ? 1 : 0,
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
