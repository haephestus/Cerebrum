import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/settings/connection_settings.dart';
import 'package:cerebrum/ui/screens/settings/ollama_settings.dart';
import 'package:cerebrum/ui/widgets/debug_reset_button.dart';
import 'package:cerebrum/ui/widgets/floating_modal.dart';

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
  void changePage(int page) {
    setState(() {
      selectedPage = page;
    });
  }

  Widget _buildPage() {
    if (selectedPage == 0) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("User settings go here"),
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

  @override
  Widget build(BuildContext context) {
    return FloatingModal(
      title: 'Settings',
      onClose: widget.onClose,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SIDEBAR
          Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => changePage(0),
                  child: const Text("My account"),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => changePage(1),
                  child: const Text("Ollama"),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => changePage(2),
                  child: const Text("Connection"),
                ),
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
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(child: _buildPage()),
            ),
          ),
        ],
      ),
    );
  }
}
