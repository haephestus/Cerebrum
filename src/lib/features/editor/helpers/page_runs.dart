import 'package:appflowy_editor/appflowy_editor.dart';

/// The Strategy-B document-structure rule, stated once.
///
/// A single-document page block's top-level children each carry a `pageId`
/// attribute; blocks sharing a pageId form one "run" = one rendered paper
/// sheet. Child ORDER decides sheet order; a missing `pageId` defaults to
/// the first page. BOTH the renderer (page_block_component.dart) and the
/// flow executor (flow_executor.dart) group through this function — a
/// private duplicate in either file is how the two views of "which block
/// is on which sheet" drift apart.
typedef PageRun = ({String pageId, int start, List<Node> nodes});

/// Group [children] into consecutive runs by their `pageId` attribute.
/// [start] is each run's index in [children] (the GLOBAL top-level index —
/// the currency overflow reports and FlowPlans are addressed by).
List<PageRun> groupRunsByPageId(
  Iterable<Node> children, {
  String defaultPageId = 'sheet-1',
}) {
  final runs = <PageRun>[];
  String? currentId; // null until the first child seeds the run id
  var runStart = 0;
  var run = <Node>[];
  var index = 0;
  for (final child in children) {
    final pageId = child.attributes['pageId']?.toString() ?? defaultPageId;
    if (currentId == null) {
      // First child opens the first run; later children compare to IT, not
      // to the [defaultPageId] — a freshly tagged doc ('p1', 'p1', ...) must
      // NOT decompose into singleton runs because the default id differs.
      currentId = pageId;
    } else if (pageId != currentId && run.isNotEmpty) {
      runs.add((pageId: currentId, start: runStart, nodes: run));
      run = <Node>[];
      runStart = index;
      currentId = pageId;
    }
    run.add(child);
    index++;
  }
  if (run.isNotEmpty) {
    runs.add((pageId: currentId!, start: runStart, nodes: run));
  }
  return runs;
}
