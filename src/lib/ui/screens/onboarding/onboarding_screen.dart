import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';

/// Shown once, on first launch (gated by UserSession.hasSeenOnboarding()).
/// Wrapped in a maxWidth Center so it doesn't look stretched on a wide
/// desktop window -- the package's default layout assumes phone widths.
class OnboardingScreen extends StatelessWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  Widget _page(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 120, color: context.cerebrum.text.strong),
            const SizedBox(height: 32),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: context.cerebrum.text.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      globalBackgroundColor: context.cerebrum.surface.canvas,
      pages: [
        PageViewModel(
          title: '',
          bodyWidget: _page(
            context,
            icon: Icons.bubble_chart,
            title: 'Welcome to Cerebrum',
            body:
                'Organize what you study into bubbles you can revisit anytime.',
          ),
        ),
        PageViewModel(
          title: '',
          bodyWidget: _page(
            context,
            icon: Icons.folder,
            title: 'Your Learning Center',
            body:
                'Keep notes, resources, and progress in one searchable place.',
          ),
        ),
        PageViewModel(
          title: '',
          bodyWidget: _page(
            context,
            icon: Icons.rocket_launch,
            title: 'Ready to start?',
            body: 'Create your account and jump straight into studying.',
          ),
        ),
      ],
      showSkipButton: true,
      skip: const Text('Skip'),
      next: const Icon(Icons.arrow_forward),
      done: const Text(
        'Get Started',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      onDone: onDone,
      onSkip: onDone,
      dotsDecorator: DotsDecorator(
        activeColor: context.cerebrum.text.strong,
        color: context.cerebrum.text.disabled,
      ),
    );
  }
}
