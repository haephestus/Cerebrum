import 'package:cerebrum/common/keyboard_nav/keyboard_nav.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/common/widgets/settings/drop_down.dart';
import 'package:cerebrum/common/widgets/settings/toggle_option.dart';
import 'package:cerebrum/common/themes/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/features/settings/connection_settings.dart';
import 'package:cerebrum/features/settings/ollama_settings.dart';
import 'package:cerebrum/common/widgets/settings/debug_reset_button.dart';
import 'package:cerebrum/common/widgets/floating_modal.dart';
import 'package:provider/provider.dart';

class SettingPage extends StatefulWidget {
  /// Pass this when SettingPage is embedded directly (e.g. as a selected
  /// sidebar page body) rather than shown via showDialog -- in that case
  /// there's no pushed route for the close button's default
  /// Navigator.pop(context) to pop, so it would silently no-op or error.
  final VoidCallback? onClose;

  const SettingPage({super.key, this.onClose});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int selectedPage = 0;
  int _navIndex = 0;
  final FocusNode _navFocusNode = FocusNode(debugLabel: 'settings-nav');

  @override
  void dispose() {
    _navFocusNode.dispose();
    super.dispose();
  }

  void changePage(int page) {
    setState(() {
      selectedPage = page;
      _navIndex = page;
    });
  }

  Widget _buildPage(ThemeProvider theme) {
    if (selectedPage == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("User settings go here"),
          SizedBox(height: 24),
          SwitchSettingItem(
            value: theme.darkMode,
            onChanged: (v) => theme.setDarkMode(v),
            label: "Toggle Dark mode",
          ),
          DropDownSettingItem(
            label: "Select A Theme",
            onSelected: (v) => theme.setSelectedTheme(v),
            initialSelection: theme.selectedThemeId,
            dropdownMenuEntries: [
              for (final family in theme.families)
                DropdownMenuEntry(value: family.id, label: family.label),
            ],
          ),
          SizedBox(height: 24),
          Divider(),
          SizedBox(height: 12),
          DebugResetOnboardingButton(),
        ],
      );
    } else if (selectedPage == 1) {
      return const OllamaSettings();
    } else if (selectedPage == 2) {
      return const ConnectionSettings();
    }
    return const Center(child: Text('Unknown Page'));
  }

  Widget _navItem(String label, int index) {
    final focused = _navFocusNode.hasFocus && _navIndex == index;
    final selected = selectedPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color:
            focused
                ? context.cerebrum.brand.accent.withValues(alpha: 0.18)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextButton(
        onPressed: () => changePage(index),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor:
              selected
                  ? context.cerebrum.text.strong
                  : context.cerebrum.text.muted,
        ),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return FloatingModal(
      title: 'Settings',
      onClose: widget.onClose,
      child: KeyboardNavScope(
        focusNode: _navFocusNode,
        autofocus: true,
        onUp:
            () => setState(() {
              if (_navIndex > 0) _navIndex--;
            }),
        onDown:
            () => setState(() {
              if (_navIndex < 2) _navIndex++;
            }),
        onActivate: () => changePage(_navIndex),
        onBack: widget.onClose ?? () => Navigator.of(context).maybePop(),
        onTop: () => setState(() => _navIndex = 0),
        onBottom: () => setState(() => _navIndex = 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SIDEBAR
            Container(
              width: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cerebrum.surface.overlay,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _navItem("My account", 0),
                  const SizedBox(height: 12),
                  _navItem("Ollama", 1),
                  const SizedBox(height: 12),
                  _navItem("Connection", 2),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // MAIN CONTENT
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  color: context.cerebrum.surface.sunken,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(child: _buildPage(theme)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
