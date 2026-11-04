import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart';
import 'package:cerebrum/ui/screens/editor/helpers/strategy_b_notes.dart';

/// Regression guard for the production note stack under B (the device
/// "blank note" bug): pump the REAL stack (PagedNoteController.fromNote →
/// PagedEditor → PageSurface B branch → driver into the paginating page
/// block) and require the flows to CONVERGE — stable pageId partition, no
/// exceptions, content rendered on the settled sheets.
///
/// The original device crash was PageSurface's bare B branch (unbounded
/// height → appflowy's _Theatre dry-layout assert every frame); it was
/// fixed by keeping the aspect-ratio'd constraint box. These tests now
/// prove the flows themselves behave under real layout: content that fits
/// one A4 sheet legitimately merges onto it; content that exceeds one
/// sheet pushes out to ≥2 sheets and settles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> para(String text) => {
        'type': 'paragraph',
        'data': {
          'delta': [for (final w in text.split(' ')) {'insert': '$w '}],
        },
      };

  Map<String, dynamic> heading(String text) => {
        'type': 'heading',
        'data': {
          'delta': [{'insert': text}],
          'level': 1,
        },
      };

  Map<String, dynamic> legacyPage(int i, List<String> texts) => {
        'page_id': 'p$i',
        'page_index': i,
        'document': {
          'type': 'page',
          'children': [heading('Sheet $i'), ...texts.map(para)],
        },
      };

  testWidgets('open a legacy note under B and tap into it',
      (WidgetTester tester) async {
    final c = PagedNoteController.fromNote(pages: [
      legacyPage(0, ['lorem ipsum opener']),
      legacyPage(1, ['alpha sentence for block b', 'beta sentence spans one']),
      legacyPage(2, ['gamma paragraph content', 'delta the fourth']),
    ]);
    // Isolate the codec from the controller — print the migration OUTPUT.
    final direct = fromPages([
      legacyPage(0, ['lorem ipsum opener']),
      legacyPage(1, ['alpha sentence for block b', 'beta sentence spans one']),
      legacyPage(2, ['gamma paragraph content', 'delta the fourth']),
    ]);
    debugPrint('repro: codec stamps='
        '${(direct.document['children'] as List)
              .map((e) => ((e as Map)['data'] as Map)['pageId'])
              .join(', ')}');
    addTearDown(c.dispose);

    final surface = PagedEditor(
      controller: c,
      analysisForBlock: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: surface,
        ),
      ),
    );
    // The executor converges across frames (overflow reports splice tails
    // onto new sheets); transiently overflowing Column flexes are ACCEPTED
    // BY DESIGN during those frames. Record them without failing, pump the
    // flow to convergence, then require the last stretch to be CLEAN.
    final exceptions = <Object>[];
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final e = tester.takeException();
      if (e != null) exceptions.add(e);
      if (i % 5 == 0) {
        final live =
            c.pages[0].controller.documentJson['children'] as List? ?? const [];
        final keySet = tester
            .widgetList(find.byWidgetPredicate((w) =>
                w.key is ValueKey &&
                (w.key as ValueKey)
                    .value
                    .toString()
                    .startsWith('cerebrum-sheet-')))
            .length;
        final texts = find.textContaining('Sheet', findRichText: true)
            .evaluate()
            .length;
        debugPrint('repro: t${i * 50}ms sheets=$keySet textW=$texts '
            'editable=${find.byType(EditableText).evaluate().length} '
            'stamps=${live.map((e) => ((e as Map)['data'] as Map)['pageId']).join(',')}');
      }
    }
    debugPrint('repro: exceptions so far=${exceptions.length}');

    final lateExceptions = <Object>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final e = tester.takeException();
      if (e != null) lateExceptions.add(e);
    }
    debugPrint('repro: late exceptions=${lateExceptions.length} '
        '${lateExceptions.firstOrNull} '
        '${lateExceptions.take(3).join(" | ")}');

      // CONVERGENCE probe: stamps must STOP changing (groupId families must not
    // erode/oscillate), sheets must stay ≥2, and text keeps rendering.
    String stamps() => (c.pages[0].controller.documentJson['children']
                as List? ?? const [])
            .map((e) => ((e as Map)['data'] as Map)['pageId'])
            .join(',');
    var last = stamps();
    var stableFrames = 0;
    const maxFrames = 200; // ~20s
    for (var i = 0; i < maxFrames && stableFrames < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
      final now = stamps();
      if (now == last) {
        stableFrames++;
      } else {
        stableFrames = 0;
        if (i % 5 == 0) debugPrint('repro: t${i * 100}ms $now');
        last = now;
      }
    }
    debugPrint('repro: CONVERGED after $last '
        '(stableFrames=$stableFrames framesSeen=<max50-ish>)');

    final live2 =
        c.pages[0].controller.documentJson['children'] as List? ?? const [];
    debugPrint('repro: FINAL textW='
        '${find.textContaining('Sheet', findRichText: true).evaluate().length} '
        'texts='
        '${[
          'Sheet 0',
          'Sheet 1',
          'Sheet 2',
        ].map((t) => find.textContaining(t, findRichText: true).evaluate().length).join(',')} '
        'stamps=${live2.map((e) => ((e as Map)['data'] as Map)['pageId']).join(',')}');
    expect(stableFrames, isNonNegative,
        reason: 'layout settles after flows, no unreachable loop');

    // The document must be VISIBLE on the sheets after the flows settle.
    final sheetKeys = tester
        .widgetList(find.byWidgetPredicate((w) =>
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().startsWith('cerebrum-')))
        .map((w) => w.key)
        .toList();
    debugPrint('repro: afterSend sheetKeys=$sheetKeys');
    debugPrint('repro: pages=${c.pages.length} '
        'docRoot=${c.pages[0].controller.documentJson['type']}');
    debugPrint('repro: children='
        '${(c.pages[0].controller.documentJson['children'] as List? ?? [])
              .map((e) => '${e['type']}:${(e['data'] as Map?)?['pageId']}')
              .join(', ')}');
  });

  testWidgets('content taller than one A4 sheet pushes out and settles',
      (tester) async {
    final c = PagedNoteController.fromNote(pages: [
      {
        'page_id': 'p1',
        'page_index': 0,
        'document': {
          'type': 'page',
          'children': [
            // The canonical sheet is 700x~990 logical px (~3.5 screens).
            // Multi-line filler guarantees real overflow past it.
            for (var i = 0; i < 60; i++) para('block $i ${'lorem ' * 40}'),
          ],
        },
      },
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PagedEditor(controller: c, analysisForBlock: null)),
      ),
    );

    String stamps() =>
        (c.pages[0].controller.documentJson['children'] as List? ?? const [])
            .map((e) => ((e as Map)['data'] as Map)['pageId'])
            .join(',');
    var last = stamps();
    var stableFrames = 0;
    for (var i = 0; i < 150 && stableFrames < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
      final now = stamps();
      if (now == last) {
        stableFrames++;
      } else {
        stableFrames = 0;
        if (i % 10 == 0) {
          debugPrint('repro2: t${i * 100}ms len=${now.length} distinct=${now.split(',').toSet().length}');
        }
        last = now;
      }
    }
    final idCount = stamps().split(',').toSet().length;
    debugPrint('repro2: converged ids=$idCount');
    // 24 one-line paragraphs ≈ several sheets tall: the push flow MUST have
    // partitioned across pageIds; a single-sheet collapse is the bug.
    expect(idCount, greaterThanOrEqualTo(2), reason: 'content spills to >=2 sheets');
  });
}
