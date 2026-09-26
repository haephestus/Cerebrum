import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/ui/widgets/learning_center/due_today_strip.dart';

void main() {
  final longStem =
      'Which of the following best describes the encoding pathway that '
      'consolidates declarative memories into long-term storage during '
      'repeated retrieval practice?';

  DueTodayStrip buildStrip() {
    return DueTodayStrip(
      engrams: [
        Engram(
          id: 'e1',
          bubbleId: 'b',
          noteId: 'n',
          type: EngramType.mcq,
          targetCognitiveLevel: 1,
          tags: const [],
          content: McqContent(
            findingIndex: 1,
            questionNumber: 1,
            stem: longStem,
            options: const {'A': 'one', 'B': 'two'},
            severity: 'high',
          ),
        ),
        Engram(
          id: 'e2',
          bubbleId: 'b',
          noteId: 'n',
          type: EngramType.longQuestion,
          targetCognitiveLevel: 2,
          tags: const [],
          content: LongQuestionContent(
            questionStem: longStem,
            parts: const [],
            severity: 'high',
            totalMarks: 10,
          ),
        ),
      ],
      typeIconOf: (t) =>
          t == EngramType.mcq ? Icons.quiz_outlined : Icons.article_outlined,
      typeLabelOf: (t) =>
          t == EngramType.mcq ? 'Multiple Choice' : 'Long Questions',
      previewTextOf: (e) => switch (e.content) {
        McqContent(:final stem) => stem,
        LongQuestionContent(:final questionStem) => questionStem,
        _ => 'Unsupported content',
      },
      onTap: (_) {},
    );
  }

  Future<void> pumpAtScale(WidgetTester tester, double scale) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildStrip())),
    );
    await tester.pump();
  }

  testWidgets('renders due cards with empty and non-empty lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DueTodayStrip(
            engrams: const [],
            typeIconOf: (t) => Icons.quiz_outlined,
            typeLabelOf: (t) => 'x',
            previewTextOf: (e) => 'x',
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nothing due today.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at textScaleFactor 1.5 (real-fonts case)', (
    tester,
  ) async {
    // Live bug: the 2-line preview exceeded the fixed 96px due card with
    // real font metrics even when Ahem-font tests passed.
    await pumpAtScale(tester, 1.5);

    expect(find.text(longStem), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at textScaleFactor 2.0 (real-fonts case)', (
    tester,
  ) async {
    await pumpAtScale(tester, 2.0);

    expect(find.text(longStem), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}