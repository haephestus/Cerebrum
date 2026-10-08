// HitTestPassThrough contract: the armed ink overlay must not become the hit
// test's endpoint.
//
// pdfrx builds one Stack with the InteractiveViewer first and the
// pageOverlaysBuilder overlays last (pdf_viewer.dart); a Stack hit-tests from
// its last child backwards and stops at the first hit. Without the pass-through
// the ink overlay therefore keeps the InteractiveViewer out of the hit path
// while drawing, and the viewer's wheel Listener — registered from its subtree
// — never sees a scroll event: wheel/trackpad scrolling over a page dies. The
// viewer must be hit too, while the overlay still receives the pointers it
// claims (drawing).

import 'package:cerebrum/ui/screens/readings/reader_ink_layer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final log = <String>[];

  // Mirrors pdfrx's tree: pdfrx's own Listener, then one Stack holding the
  // viewer (bottom, hit-tested last) and the ink overlay (top, hit first).
  // Opaque listeners stand in for the parts that make each side hittable:
  // pdfrx's GestureDetector(behavior: opaque) inside the viewer, and scribble's
  // opaque MouseRegion inside the overlay.
  Widget harness({required bool drawing}) {
    return MaterialApp(
      home: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 120,
            height: 120,
            child: Listener(
              onPointerDown: (_) => log.add('pdfrx'),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 120,
                    height: 120,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => log.add('viewer'),
                      onPointerSignal:
                          (event) => GestureBinding
                              .instance
                              .pointerSignalResolver
                              .register(event, (_) => log.add('viewer-wheel')),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 120,
                    height: 120,
                    child: HitTestPassThrough(
                      child: IgnorePointer(
                        ignoring: !drawing,
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) => log.add('ink'),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  setUp(log.clear);

  testWidgets('drawing armed: a press over a page reaches ink AND the viewer', (
    tester,
  ) async {
    await tester.pumpWidget(harness(drawing: true));
    await tester.tapAt(const Offset(30, 30));
    // The overlay is hit first (top of the Stack), but it does not end the hit
    // test, so the viewer and pdfrx's listener are in the path as well.
    expect(log, ['ink', 'viewer', 'pdfrx']);
  });

  testWidgets('drawing armed: a wheel over a page still reaches the viewer', (
    tester,
  ) async {
    await tester.pumpWidget(harness(drawing: true));
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(30, 30),
        scrollDelta: Offset(0, -40),
      ),
    );
    expect(log, ['viewer-wheel']);
  });

  testWidgets('drawing off: the overlay stays out of the hit path entirely', (
    tester,
  ) async {
    await tester.pumpWidget(harness(drawing: false));
    await tester.tapAt(const Offset(30, 30));
    expect(log, ['viewer', 'pdfrx']);
  });
}
