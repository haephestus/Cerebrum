import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cerebrum/services/user_session.dart';
import 'package:cerebrum/ui/app_entry.dart';

// Drop this anywhere in SettingPage (or any debug menu). Only renders
/// in debug builds -- kDebugMode is false in a release/profile build,
/// so this compiles to nothing shippable and you don't have to remember
/// to remove it later.
///
/// Usage inside SettingPage's build method:
///   const DebugResetOnboardingButton(),
class DebugResetOnboardingButton extends StatelessWidget {
  const DebugResetOnboardingButton({super.key});

  Future<void> _reset(BuildContext context) async {
    await UserSession.resetAll();
    if (!context.mounted) return;

    // Replace the entire navigation stack with a fresh AppEntryPoint so
    // it re-resolves the startup route (will land on OnboardingScreen).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntryPoint()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => _reset(context),
      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
      icon: const Icon(Icons.restart_alt),
      label: const Text('DEBUG: Reset onboarding + login'),
    );
  }
}
