import 'package:flutter/material.dart';

class SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onPressed,
  });

  @override
  State<SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<SidebarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 92, // fixed sidebar width
        child: Row(
          children: [
            // Left indicator bar
            Container(
              width: 4,
              height: 66, // match button height roughly
              color: widget.selected ? Colors.blue : Colors.transparent,
            ),
            const SizedBox(width: 4), // spacing between bar and button
            Expanded(
              child: TextButton(
                // Hover effect
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: widget.onPressed,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 40, color: Colors.blue),
                    const SizedBox(height: 8),
                    if (_hovering)
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        offset: Offset(0, 0),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: 1,
                          child: Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
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

