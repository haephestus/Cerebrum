/// TODO(backend): needs a new endpoint, e.g. GET /learn/metrics/summary.
/// Mastery and streak aren't derivable from GET /learn/engrams/list alone
/// -- that call returns the current engram set, not a rolling completion
/// history, so streak in particular needs the backend to track it over
/// time. Until that endpoint exists, MetricsApi.getSummary (see
/// metrics_api.dart) throws, and the dashboard shows "--" rather than a
/// fabricated number.
class PerformanceMetrics {
  final double masteryPercent; // 0-100, backend-defined formula
  final int streakDays;

  const PerformanceMetrics({
    required this.masteryPercent,
    required this.streakDays,
  });

  factory PerformanceMetrics.fromJson(Map<String, dynamic> json) {
    return PerformanceMetrics(
      masteryPercent: (json['mastery_percent'] as num?)?.toDouble() ?? 0,
      streakDays: json['streak_days'] as int? ?? 0,
    );
  }
}
