/// A non-2xx HTTP response from the daemon.
///
/// Why this exists: [EngramSyncService._advance] used to treat *every* failed
/// submit as "offline — retry later", so a permanent rejection (404 unknown
/// engram, 400 bad payload) was retried every 20 seconds forever, the attempt
/// never left `queued`, and the user never learned why. Carrying the status
/// code lets the caller separate the two cases:
///
///  • **transient** (offline, hub down, 5xx, 408, 429): retrying on a later
///    drain is correct.
///  • **permanent** (other 4xx): the daemon answered and means it — retrying
///    the same request can never succeed. Callers should mark the attempt
///    `failed` and surface it.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;

  /// Raw response body, for logging/debugging (may hold the daemon's detail).
  final String? body;

  /// True when resending this exact request cannot succeed without something
  /// changing client-side (wrong id, rejected shape, auth). 408 (request
  /// timeout) and 429 (too many requests) are the retryable 4xx.
  bool get isPermanent =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() => message;
}
