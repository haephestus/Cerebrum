// =============================================================================
// PageAnnotation storage contract (annotations.dart header "STORAGE" block):
//   - key `ink:<fingerprint>` holds a JSON ARRAY of tagged objects,
//   - entries without a `t` tag are legacy ink and decode as ink,
//   - unknown `t` kinds round-trip verbatim (forward compat),
//   - only ink is derived from a Sketch; highlight/note live only in the
//     decoded raw list so a save can't drop them.
// Plus the notify contract: sketch edits must NOT broadcast on the store
// (annotations.dart item 9) — they only debounce a save.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble/scribble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cerebrum/ui/screens/readings/annotations.dart';

Map<String, dynamic> roundTripJson(PageAnnotation a) =>
    jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Any store dispose() flushes a pending save; give those writes somewhere to
  // land (setMockInitialValues also resets SharedPreferences's cached
  // instance, so each test below re-reads its own data).
  SharedPreferences.setMockInitialValues({});

  group('PageAnnotation JSON', () {
    test('legacy blob (no t) decodes as ink and re-emits with t', () {
      final legacy = <String, dynamic>{
        'p': 3,
        'c': 0xFF112233,
        'w': 0.012,
        'h': true,
        'pts': <double>[0.1, 0.2, 0.3, 0.4],
      };
      final decoded = PageAnnotation.fromJson(legacy);

      expect(decoded, isA<InkAnnotation>());
      final ink = decoded as InkAnnotation;
      expect(ink.page, 3);
      expect(ink.highlighter, isTrue);
      expect(ink.color, const Color(0xFF112233));
      expect(ink.width, 0.012);
      expect(ink.points, const [Offset(0.1, 0.2), Offset(0.3, 0.4)]);

      final out = roundTripJson(ink);
      expect(out['t'], 'ink');
      expect(out['p'], 3);
      expect(out['h'], isTrue);
      expect(out['pts'], <double>[0.1, 0.2, 0.3, 0.4]);
      expect(out['w'], 0.012);
    });

    test('ink round-trips through the wire unchanged', () {
      final ink = InkAnnotation(
        page: 7,
        points: const [Offset(0.25, 0.5), Offset(0.5, 0.75)],
        color: const Color(0xFF00FF00),
        width: 0.01,
        highlighter: false,
      );
      final back = PageAnnotation.fromJson(roundTripJson(ink)) as InkAnnotation;
      expect(back.page, 7);
      expect(back.points, ink.points);
      expect(back.color.toARGB32(), ink.color.toARGB32());
      expect(back.width, 0.01);
      expect(back.highlighter, isFalse);
    });

    test('highlight round-trips (quads, colour, captured text)', () {
      final hl = HighlightAnnotation(
        page: 2,
        quads: const [
          Rect.fromLTWH(0.1, 0.2, 0.5, 0.03),
          Rect.fromLTWH(0.1, 0.25, 0.3, 0.03),
        ],
        color: const Color(0x66FF0000),
        text: 'hello world',
      );
      final back = PageAnnotation.fromJson(roundTripJson(hl));
      expect(back, isA<HighlightAnnotation>());
      final h = back as HighlightAnnotation;
      expect(h.page, 2);
      expect(h.quads, hl.quads);
      expect(h.color.toARGB32(), hl.color.toARGB32());
      expect(h.text, 'hello world');
      expect(back.kind, 'hl');
    });

    test('note round-trips (position, quads, text, createdAt epoch ms)', () {
      final note = NoteAnnotation(
        page: 4,
        position: const Offset(0.4, 0.6),
        quads: const [Rect.fromLTWH(0.4, 0.6, 0.05, 0.05)],
        text: 'a note',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1728000000000),
      );
      final back = PageAnnotation.fromJson(roundTripJson(note));
      expect(back, isA<NoteAnnotation>());
      final n = back as NoteAnnotation;
      expect(n.page, 4);
      expect(n.position, const Offset(0.4, 0.6));
      expect(n.quads, note.quads);
      expect(n.text, 'a note');
      expect(n.createdAt.millisecondsSinceEpoch, 1728000000000);
      expect(back.kind, 'note');
    });

    test('unknown kind round-trips verbatim', () {
      final raw = <String, dynamic>{
        't': 'future',
        'p': 7,
        'zzz': [1, 2, 3],
      };
      final decoded = PageAnnotation.fromJson(raw);
      expect(decoded.kind, 'future');
      expect(decoded.page, 7);
      expect(decoded.toJson(), raw);
    });

    test('unparseable entry degrades instead of nuking the whole file', () {
      final bad = <String, dynamic>{
        't': 'hl', // no `p`, no `q` — unparseable as a HighlightAnnotation
      };
      final good = <String, dynamic>{
        't': 'ink',
        'p': 1,
        'c': 0xFF000000,
        'w': 0.01,
        'h': false,
        'pts': <double>[0.1, 0.1, 0.2, 0.2],
      };
      final decoded = [
        for (final e in [bad, good]) PageAnnotation.fromJson(e),
      ];

      expect(
        decoded,
        hasLength(2),
        reason: 'one bad entry must not abort load',
      );
      expect(decoded.first, isNot(isA<HighlightAnnotation>()));
      expect(decoded.first.kind, 'hl');
      expect(
        decoded.first.toJson(),
        bad,
        reason: 'degraded entries round-trip verbatim — no silent deletion',
      );
      expect(decoded.last, isA<InkAnnotation>());
    });
  });

  group('Sketch <-> PageAnnotation', () {
    const pageSize = Size(600, 800);

    test('ink denormalises into the sketch and normalises back', () {
      final ink = InkAnnotation(
        page: 1,
        points: const [Offset(0.25, 0.5), Offset(0.5, 0.75)],
        color: const Color(0xFF00FF00),
        width: 0.01,
        highlighter: false,
      );
      final sketch = sketchFromAnnotations([ink], pageSize);
      expect(sketch.lines, hasLength(1));
      final line = sketch.lines.first;
      expect(line.points.first.x, closeTo(0.25 * 600, 1e-9));
      expect(line.points.first.y, closeTo(0.5 * 800, 1e-9));
      expect(line.width, closeTo(0.01 * 600, 1e-9));
      expect(line.color, 0xFF00FF00);

      final back = annotationsFromSketch(sketch, 1, pageSize);
      expect(back, hasLength(1));
      final a = back.single as InkAnnotation;
      expect(a.page, 1);
      expect(a.highlighter, isFalse);
      expect(a.color.toARGB32(), 0xFF00FF00);
      for (var i = 0; i < ink.points.length; i++) {
        expect(a.points[i].dx, closeTo(ink.points[i].dx, 1e-9));
        expect(a.points[i].dy, closeTo(ink.points[i].dy, 1e-9));
      }
      expect(a.width, closeTo(0.01, 1e-9));
    });

    test('highlighter lines keep the flag and store opaque colour', () {
      // The dial bakes 0.4 alpha into highlight strokes.
      final baked = Color(0xFFFF0000).withValues(alpha: 0.4);
      expect(baked.toARGB32(), 0x66FF0000);
      final sketch = Sketch(
        lines: [
          SketchLine(
            points: const [Point(60, 200), Point(360, 220)],
            color: baked.toARGB32(),
            width: 40,
          ),
        ],
      );

      final back = annotationsFromSketch(sketch, 2, pageSize);
      final ink = back.single as InkAnnotation;
      expect(ink.highlighter, isTrue);
      // Invariant: stored full-alpha colour + flag, on EVERY save — not only
      // the one right after the stroke was drawn.
      expect(ink.color.toARGB32(), 0xFFFF0000);

      // Round trip is stable: re-saving the reloaded model changes nothing.
      final again = annotationsFromSketch(
        sketchFromAnnotations([ink], pageSize),
        2,
        pageSize,
      );
      expect(jsonEncode(again.single.toJson()), jsonEncode(ink.toJson()));
    });

    test('highlight/note never enter the sketch, so they survive a save', () {
      final hl = HighlightAnnotation(
        page: 3,
        quads: const [Rect.fromLTWH(0.1, 0.2, 0.5, 0.03)],
        color: const Color(0x66FF0000),
        text: 'hi',
      );
      final note = NoteAnnotation(
        page: 3,
        position: const Offset(0.4, 0.6),
        quads: const [],
        text: 'a note',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1728000000000),
      );
      final ink = InkAnnotation(
        page: 3,
        points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
        color: const Color(0xFF000000),
        width: 0.01,
        highlighter: false,
      );

      final sketch = sketchFromAnnotations([hl, note, ink], pageSize);
      // Only the ink became a line — markup is not materialised into scribble.
      expect(sketch.lines, hasLength(1));
      expect(
        annotationsFromSketch(sketch, 3, pageSize),
        hasLength(1),
        reason:
            'derived list carries ink only; AnnotationStore._saveNow merges it '
            'with the raw list, which still holds hl/note',
      );
    });
  });

  group('AnnotationStore', () {
    test('does not broadcast sketch edits (item 9)', () {
      final store = AnnotationStore('fp-notifier-test');
      var notifies = 0;
      store.addListener(() => notifies++);

      final n = store.notifierFor(1);
      store.setPageSize(1, const Size(600, 800));
      expect(notifies, 0, reason: 'materialise is silent');

      n.setSketch(
        sketch: Sketch(
          lines: [
            SketchLine(
              points: const [Point(60, 200), Point(360, 220)],
              color: 0xFF000000,
              width: 40,
            ),
          ],
        ),
        addToUndoHistory: false,
      );
      expect(notifies, 0, reason: 'a pointer move must not rebuild the viewer');

      expect(store.drawing, isFalse);
      store.toggleDrawingMode();
      expect(notifies, 1);
      expect(store.drawing, isTrue);
      store.toggleDrawingMode();
      expect(store.drawing, isFalse);
      expect(notifies, 2);

      store.dispose(); // flushes the pending debounce
    });

    test('load survives garbage elements (one bad byte ≠ lost file)', () async {
      SharedPreferences.setMockInitialValues({
        'ink:fp-load-garbage': jsonEncode([
          'not an object',
          <String, dynamic>{'t': 'hl'}, // unparseable object
          <String, dynamic>{
            't': 'ink',
            'p': 2,
            'c': 0xFF000000,
            'w': 0.01,
            'h': false,
            'pts': <double>[0.1, 0.1, 0.2, 0.2],
          },
        ]),
      });

      final store = AnnotationStore('fp-load-garbage');
      await store.load(); // must not throw

      expect(store.annotations(2), hasLength(1));
      expect(store.annotations(2).single, isA<InkAnnotation>());
      expect(
        store.annotations(0),
        hasLength(1),
        reason:
            'the bad object is '
            'kept as an opaque entry rather than dropped',
      );

      store.dispose();
    });

    test(
      'markup survives a debounced save (not dropped, ink not duplicated)',
      () async {
        SharedPreferences.setMockInitialValues({
          'ink:fp-save-test': jsonEncode([
            {
              't': 'ink',
              'p': 1,
              'c': 0xFF000000,
              'w': 0.01,
              'h': false,
              'pts': <double>[0.1, 0.1, 0.2, 0.2],
            },
            {
              't': 'hl',
              'p': 1,
              'c': 0x66FF0000,
              'q': [
                [0.1, 0.2, 0.5, 0.25],
              ],
              'tx': 'hi',
            },
          ]),
        });

        final store = AnnotationStore('fp-save-test');
        await store.load();
        expect(store.annotations(1), hasLength(2));
        expect(
          store.annotations(1).whereType<HighlightAnnotation>(),
          hasLength(1),
        );

        // Materialise the ink onto a page (what ReaderInkPage does on build),
        // which schedules the debounce the old code fired per pointer move.
        store.notifierFor(1);
        store.setPageSize(1, const Size(600, 800));
        expect(store.annotations(1), hasLength(2));

        await Future<void>.delayed(const Duration(milliseconds: 750));

        final prefs = await SharedPreferences.getInstance();
        final raw = jsonDecode(prefs.getString('ink:fp-save-test')!) as List;
        expect(
          raw.where((e) => (e as Map)['t'] == 'ink'),
          hasLength(1),
          reason: 'ink left the raw list exactly once and must not duplicate',
        );
        expect(
          raw.where((e) => (e as Map)['t'] == 'hl'),
          hasLength(1),
          reason: 'markup never enters a sketch, so a save cannot drop it',
        );

        store.dispose();
      },
    );
  });
}
