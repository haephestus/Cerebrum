import 'package:cerebrum/features/editor/helpers/analysis_mode_controller.dart';
import 'package:cerebrum/features/editor/widgets/analysis_findings_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AnalysisChunkRef _chunk(int i, {String? excerpt, int findings = 1}) {
  return AnalysisChunkRef(
    chunkId: 'chunk_$i',
    pageId: 'main',
    blockIds: ['block_$i'],
    chunk: {
      'chunkId': 'chunk_$i',
      'excerpt': excerpt ?? 'Excerpt $i',
      'findings': [
        for (var f = 0; f < findings; f++)
          {
            'severity': 'high',
            'type': 'gap',
            'gap_explanation': 'Gap $f in chunk $i',
          },
      ],
      'pageId': 'main',
      'blockIds': ['block_$i'],
    },
  );
}

Widget _host(
  AnalysisModeController analysis, {
  FocusNode? focusNode,
  VoidCallback? onReleaseFocus,
  VoidCallback? onOpenFullPanel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          AnalysisFindingsWindow(
            visible: true,
            analysis: analysis,
            focusNode: focusNode,
            onReleaseFocus: onReleaseFocus,
            onOpenFullPanel: onOpenFullPanel ?? () {},
            onClose: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('shows the stepped chunk and its findings', (tester) async {
    final analysis =
        AnalysisModeController()..setChunks([_chunk(1), _chunk(2)]);

    await tester.pumpWidget(_host(analysis));

    expect(find.text('Findings · chunk 1 / 2'), findsOneWidget);
    expect(find.text('Excerpt 1'), findsOneWidget);
    expect(find.textContaining('Gap 0 in chunk 1'), findsOneWidget);
  });

  testWidgets('n / N step chunks and keep the controller in sync', (
    tester,
  ) async {
    final analysis =
        AnalysisModeController()..setChunks([_chunk(1), _chunk(2)]);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(_host(analysis, focusNode: focus));
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(analysis.index, 1);
    expect(find.text('Findings · chunk 2 / 2'), findsOneWidget);
    expect(find.text('Excerpt 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(analysis.index, 1, reason: 'stepping past the last chunk clamps');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(analysis.index, 0, reason: 'N walks back one chunk');
    expect(find.text('Findings · chunk 1 / 2'), findsOneWidget);
  });

  testWidgets('Esc/q releases focus; Enter does not open full analysis', (
    tester,
  ) async {
    final analysis = AnalysisModeController()..setChunks([_chunk(1)]);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var released = 0;
    var opened = 0;

    await tester.pumpWidget(
      _host(
        analysis,
        focusNode: focus,
        onReleaseFocus: () => released++,
        onOpenFullPanel: () => opened++,
      ),
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 0, reason: 'Enter must not open the note overview panel');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(released, 1);
  });

  testWidgets('header tile is selectable so g/k reaches the very top', (
    tester,
  ) async {
    final analysis =
        AnalysisModeController()..setChunks([_chunk(1, findings: 2)]);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(_host(analysis, focusNode: focus));
    focus.requestFocus();
    await tester.pump();

    // Starts on the header tile (top).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyJ,
    ); // header -> first finding
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG); // g -> header
    await tester.pump();

    expect(find.text('Excerpt 1'), findsOneWidget);
    expect(analysis.index, 0);
  });
}
