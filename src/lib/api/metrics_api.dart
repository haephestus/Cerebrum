import 'package:cerebrum/models/performance_metrics.dart';

/// TODO(backend): wire this up once GET /learn/metrics/summary (or
/// equivalent) exists. Until then this throws, and
/// DLearningCenterPage._fetchMetrics catches that and treats it as "no
/// data yet" (PerformancePanel then shows "--" instead of a made-up
/// number) -- the same degrade-gracefully pattern already used for
/// bubbleNames/noteTitles in _fetchEngramsView.
class MetricsApi {
  static Future<PerformanceMetrics> getSummary({required String userId}) {
    throw UnimplementedError(
      'MetricsApi.getSummary needs a backend endpoint -- '
      'see performance_metrics.dart for the response shape this expects.',
    );
  }
}
