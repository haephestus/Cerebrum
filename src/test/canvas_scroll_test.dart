import 'package:appflowy_editor/appflowy_editor.dart'
    show Selection, Position, SelectionUpdateReason;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_block_component.dart'
    show kSheetVerticalMargin;
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';

/// Regression guard for the Strategy-B zoomable canvas's pointer handling,
/// caret-follow and wheel routing.
///
/// Under `kUseSingleDocumentPagination = true` there is no scrollable in the
/// tree at all — the zoomable canvas is the viewport. These tests pin what a
/// real scrollable gives for free, and what this canvas was missing:
///
///   * wheel pans CLAMP at the content edges (content never leaves the
///     viewport, where the wheel hit-test would miss it forever — that is the
///     "scroll is swallowed at some point" report);
///   * trackpad two-finger pan works (localPanDelta → canvas pan);
///   * the view follows the caret when selection leaves the viewport.
///
/// The wheel events are dispatched at the viewport center WITHOUT a
/// preceding pointer-down, exactly how `tester.sendEventToBinding` delivers
/// them on desktop.
class _Harness {
  _Harness(this.controller, this.tc);

  final PagedNoteController controller;
  final TransformationController tc;
}

Map<String, dynamic> _para(String text) => {
      'type': 'paragraph',
      'data': {
        'delta': [{'insert': text}],
      },
    };

Map<String, dynamic> _heading(String text) => {
      'type': 'heading',
      'data': {
        'delta': [{'insert': text}],
        'level': 1,
      },
    };

/// One page of dense multi-line text: certainly taller than one sheet.
List<Map<String, dynamic>> _pageContent(String prefix, int n) => [
      _heading('Sheet $prefix'),
      for (var i = 0; i < n; i++)
        _para('$prefix block $i ${'lorem ' * 60}'),
    ];

Future<_Harness> _pumpSettled(WidgetTester tester) async {
  final c = PagedNoteController.fromNote(pages: [
    {
      'page_id': 'p1',
      'page_index': 0,
      'document': {
        'type': 'page',
        'children': _pageContent('a', 45),
      },
    },
  ]);
  addTearDown(c.dispose);
  final tc = TransformationController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PagedEditor(
          controller: c,
          analysisForBlock: null,
          zoomController: tc,
        ),
      ),
    ),
  );

  // Settle the flow executor (push overflow to new sheets and vice versa)
  // exactly as the convergence probe does: pump until the pageId partition
  // of the document stops changing.
  String stamps() =>
      (c.pages[0].controller.documentJson['children'] as List? ?? const [])
          .map((e) => ((e as Map)['data'] as Map?)?['pageId'])
          .join(',');
  var last = stamps();
  var stable = 0;
  for (var i = 0; i < 200 && stable < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
    final now = stamps();
    if (now == last) {
      stable++;
    } else {
      stable = 0;
      last = now;
    }
  }
  await tester.pump();

  return _Harness(c, tc);
}

/// Total logical document height as the editor computes it:
/// runs of consecutive same-pageId blocks, each one sheet tall plus margins.
double _contentHeight(List<dynamic> children) {
  var runs = 0;
  String? prev;
  for (final c in children) {
    final id = ((c as Map?)?['data'] as Map?)?['pageId'] as String? ?? 'main';
    if (id != prev) {
      runs++;
      prev = id;
    }
  }
  return runs *
      ((kDocSheetWidth / kPageAspectRatio) + 2 * kSheetVerticalMargin);
}

const _viewport = Size(800 - 2 * 12, 600 - 2 * 12); // Padding(12) from itemAt
const _wheelDown = Offset(0, 160); // per wheel "click"

Future<void> _wheel(WidgetTester tester, int clicks) async {
  for (var i = 0; i < clicks; i++) {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(_viewport.width / 2 + 12, _viewport.height / 2 + 12),
        scrollDelta: _wheelDown,
      ),
    );
    await tester.pump(Duration.zero);
  }
}

Future<void> _wheelUp(WidgetTester tester, int clicks) async {
  for (var i = 0; i < clicks; i++) {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(_viewport.width / 2 + 12, _viewport.height / 2 + 12),
        scrollDelta: -_wheelDown,
      ),
    );
    await tester.pump(Duration.zero);
  }
}

void main() {
  testWidgets(
    'wheel-down clamps: content bottom never leaves the viewport',
    (tester) async {
      final h = await _pumpSettled(tester);
      final children =
          (h.controller.pages[0].controller.documentJson['children'] as List);
      final scale = h.tc.value.getMaxScaleOnAxis();
      final scaledHeight = _contentHeight(children) * scale;
      // Content taller than viewport is a precondition of this test.
      expect(scaledHeight, greaterThan(_viewport.height));

      // Wheel far more than the content height — the pre-fix matrix kept
      // translating until the sheets were scrolled entirely off-screen.
      await _wheel(tester, 60); // 9600 px of wheel down

      final ty = h.tc.value.storage[13];
      final clampedMin = _viewport.height - scaledHeight;
      expect(
        ty,
        closeTo(clampedMin, 0.5),
        reason: 'wheel must stop at the content bottom edge',
      );
      // And the content must still cover the bottom of the viewport, so the
      // wheel hit-test passes through it again:
      expect(scaledHeight + ty, greaterThanOrEqualTo(_viewport.height - 1));
    },
  );

  testWidgets('wheel-up clamps at the content top (translation never > 0)',
      (tester) async {
    final h = await _pumpSettled(tester);
    await _wheel(tester, 3);
    await _wheelUp(tester, 30);
    final ty = h.tc.value.storage[13];
    expect(ty, closeTo(0.0, 0.5),
        reason: 'wheel up must stop when the content top is on screen');
  });

  testWidgets('trackpad two-finger pan pans the canvas', (tester) async {
    final h = await _pumpSettled(tester);
    final center = Offset(_viewport.width / 2 + 12, _viewport.height / 2 + 12);
    final gesture = await tester.startGesture(center, kind: PointerDeviceKind.trackpad);
    await gesture.panZoomUpdate(center, pan: const Offset(0, 320));
    await gesture.panZoomEnd();
    await tester.pump(Duration.zero);

    final ty = h.tc.value.storage[13];
    expect(
      ty,
      lessThan(-100),
      reason: 'pan is the only way to inspect the off-screen sheets',
    );
  });

  testWidgets('selection below the viewport scrolls it into view',
      (tester) async {
    final h = await _pumpSettled(tester);
    final children =
        (h.controller.pages[0].controller.documentJson['children'] as List);
    final driver =
        h.controller.pages[0].controller.driver as AppFlowyTextDriver;
    driver.editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: [children.length - 1], offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));

    // The editor shows the document from the top (translation 0), so a caret
    // near the bottom of a multi-sheet document MUST move the view down.
    expect(
      h.tc.value.storage[13],
      lessThan(0),
      reason: 'follow must pan the canvas down to bring the caret into view',
    );
  });

  // Content and sheets constants used for sanity in debugging runs only.
  test('sheet geometry consts are the documented A4 proportions', () {
    expect(kSheetVerticalMargin, 12);
    expect(kPageAspectRatio, lessThan(1));
    expect(kDocSheetWidth, 700);
  });
}
