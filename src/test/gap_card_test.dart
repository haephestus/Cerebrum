import 'package:cerebrum/ui/screens/home/gap_card.dart';
import 'package:cerebrum/ui/screens/home/gap_models.dart';
import 'package:cerebrum/ui/screens/home/gap_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements GapRepository {
  final Map<String, BubbleGapSummary> cachedData;
  final Map<String, BubbleGapSummary> refreshData;

  const _FakeRepository({
    this.cachedData = const {},
    this.refreshData = const {},
  });

  @override
  Future<Map<String, BubbleGapSummary>> cached() async => cachedData;

  @override
  Future<Map<String, BubbleGapSummary>> refresh() async => refreshData;
}

BubbleGapSummary sampleSummary() => const BubbleGapSummary(
  bubbleId: 'b1',
  bubbleName: 'Medical Terms',
  items: [
    GapItem(
      kind: GapKind.weakArea,
      title: 'Recursion',
      detail: 'compresses the definition',
      evidence: [
        GapEvidence(
          noteId: 'n1',
          noteTitle: 'Data Structures',
          analysisVersion: 4,
          excerpt: '# Recursion\n\nBase cases are tricky.',
        ),
      ],
    ),
    GapItem(
      kind: GapKind.confusion,
      title: 'Stack vs Queue',
      detail: 'FIFO vs LIFO',
      evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
    ),
    GapItem(
      kind: GapKind.suggestedReading,
      title: 'Algorithms Unlocked',
      detail: 'covers sorting',
      evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
    ),
  ],
);

Future<void> pumpCard(WidgetTester tester, GapRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: GapCard(repository: repository))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders bubble header, count line, gaps and evidence', (
    tester,
  ) async {
    final repo = _FakeRepository(refreshData: {'b1': sampleSummary()});
    await pumpCard(tester, repo);

    expect(find.text('Understanding Gaps'), findsOneWidget);
    expect(find.text('Medical Terms'), findsOneWidget);
    // Rollup line: 1 weak area, 1 confusion, 1 suggested reading.
    expect(
      find.text('1 weak area · 1 confusion · 1 suggested reading'),
      findsOneWidget,
    );
    expect(find.text('Recursion'), findsOneWidget);
    expect(find.text('Stack vs Queue'), findsOneWidget);
    expect(find.text('Algorithms Unlocked'), findsOneWidget);
    // Evidence: note + analysis version, and the excerpt for chunk-sourced.
    expect(find.text('Data Structures · v4'), findsOneWidget);
    expect(find.textContaining('Base cases are tricky.'), findsOneWidget);
  });

  testWidgets('renders the kind labels for every item', (tester) async {
    final repo = _FakeRepository(refreshData: {'b1': sampleSummary()});
    await pumpCard(tester, repo);

    expect(find.text('Weak area'), findsOneWidget);
    expect(find.text('Confusion'), findsOneWidget);
    expect(find.text('Suggested reading'), findsOneWidget);
  });

  testWidgets('silently shrinks when there are no gaps', (tester) async {
    final repo = _FakeRepository();
    await pumpCard(tester, repo);

    expect(find.text('Understanding Gaps'), findsNothing);
    expect(find.byType(GapCard), findsOneWidget);
    expect(
      tester.getSize(find.byType(GapCard)),
      Size.zero, // SizedBox.shrink
    );
  });

  testWidgets('keeps last-known cache when the daemon refresh finds nothing', (
    tester,
  ) async {
    final repo = _FakeRepository(
      cachedData: {'b1': sampleSummary()},
      refreshData: const {},
    );
    await pumpCard(tester, repo);

    // The cache painted first; the empty daemon pass must not blank it.
    expect(find.text('Understanding Gaps'), findsOneWidget);
    expect(find.text('Medical Terms'), findsOneWidget);
  });

  testWidgets('marks stale analysis instead of silently serving it', (
    tester,
  ) async {
    final stale = const BubbleGapSummary(
      bubbleId: 'b1',
      bubbleName: 'Medical Terms',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Recursion',
          evidence: [
            GapEvidence(
              noteId: 'n1',
              noteTitle: 'Data Structures',
              analysisVersion: 2,
              isCurrent: false,
            ),
          ],
        ),
      ],
    );
    final repo = _FakeRepository(refreshData: {'b1': stale});
    await pumpCard(tester, repo);

    expect(find.text('Data Structures · v2 · stale analysis'), findsOneWidget);
  });

  testWidgets('renders a severity chip only when the daemon supplied one', (
    tester,
  ) async {
    final withSeverity = BubbleGapSummary(
      bubbleId: 'b1',
      bubbleName: 'Medical Terms',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Recursion',
          severity: 'high',
          evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
        ),
      ],
    );
    final repo = _FakeRepository(refreshData: {'b1': withSeverity});
    await pumpCard(tester, repo);

    // Chip renders the daemon vocabulary verbatim (uppercased). The single
    // high item is also the priority lead, so its chip appears in the
    // Priority strip AND in the bubble section — both are the same grounded
    // item, no invented second source.
    expect(find.text('HIGH'), findsNWidgets(2));
  });

  testWidgets('Priority lead renders when a real severity exists', (
    tester,
  ) async {
    final severe = BubbleGapSummary(
      bubbleId: 'b1',
      bubbleName: 'Medical Terms',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Recursion',
          severity: 'high',
          evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
        ),
      ],
    );
    final mild = BubbleGapSummary(
      bubbleId: 'b2',
      bubbleName: 'Genetics',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Meiosis',
          severity: 'low',
          evidence: [GapEvidence(noteId: 'n2', noteTitle: 'Genetics Notes')],
        ),
      ],
    );

    final repo = _FakeRepository(refreshData: {'b1': severe, 'b2': mild});
    await pumpCard(tester, repo);

    // The high-severity item leads as the single grounded Priority. Its title
    // appears twice: once in the Priority strip, once in its bubble section.
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Recursion'), findsNWidgets(2));
  });

  testWidgets('no Priority lead without a real severity', (tester) async {
    final noSeverity = BubbleGapSummary(
      bubbleId: 'b1',
      bubbleName: 'Medical Terms',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Recursion',
          evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
        ),
      ],
    );
    final repo = _FakeRepository(refreshData: {'b1': noSeverity});
    await pumpCard(tester, repo);

    // Overview gaps carry no daemon severity → no invented priority lead.
    expect(find.text('Priority'), findsNothing);
  });

  testWidgets('bubbles are attention-ordered, most severe first', (
    tester,
  ) async {
    final low = BubbleGapSummary(
      bubbleId: 'b1',
      bubbleName: 'Genetics',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Meiosis',
          severity: 'low',
          evidence: [GapEvidence(noteId: 'n2', noteTitle: 'Genetics Notes')],
        ),
      ],
    );
    final high = BubbleGapSummary(
      bubbleId: 'b2',
      bubbleName: 'Medical Terms',
      items: [
        GapItem(
          kind: GapKind.weakArea,
          title: 'Recursion',
          severity: 'high',
          evidence: [GapEvidence(noteId: 'n1', noteTitle: 'Data Structures')],
        ),
      ],
    );

    // Refresh data intentionally unordered: the card must order by attention.
    final repo = _FakeRepository(refreshData: {'b1': low, 'b2': high});
    await pumpCard(tester, repo);

    final yHigh = tester.getCenter(find.text('Medical Terms')).dy;
    final yLow = tester.getCenter(find.text('Genetics')).dy;
    expect(yHigh, lessThan(yLow));
  });
}
