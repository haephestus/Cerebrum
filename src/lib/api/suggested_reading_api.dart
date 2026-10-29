import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_exception.dart';

/// One suggested reading from the daemon's `/suggested-reading` surface.
///
/// For KB-backed rows (`inKb == true`) the daemon's knowledge-base source
/// resolves the document by content similarity, so [fileFingerprint] is the
/// durable identity (never a filename guess) and [page] is the 1-indexed PDF
/// page of the best-matching chunk — what the reader should open at.
class SuggestedReading {
  final String title;
  final String source;
  final String? url;
  final String? fileFingerprint;
  final bool inKb;
  final int? page;
  final double score;
  final String snippet;
  final String reason;

  const SuggestedReading({
    required this.title,
    required this.source,
    this.url,
    this.fileFingerprint,
    this.inKb = false,
    this.page,
    this.score = 0.0,
    this.snippet = '',
    this.reason = '',
  });

  factory SuggestedReading.fromJson(Map<String, dynamic> json) =>
      SuggestedReading(
        title: json['title']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        url: json['url'] as String?,
        fileFingerprint: json['file_fingerprint'] as String?,
        inKb: json['in_kb'] == true,
        page: (json['page'] as num?)?.toInt(),
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        snippet: json['snippet']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class SuggestedReadingApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get suggestedReadingEndpoint => "$baseUrl/suggested-reading";

  // ══ CROSS-REPO CONTRACT: readings ⇄ daemon routes_suggested_reading.py ══
  // Paired with daemon `GET /suggested-reading/note/{bubble_id}/{note_id}`
  // (routes_suggested_reading.suggest_for_note → suggested_reading_inator
  //  .suggest → KB source rows persisted in suggested_readings).
  //
  // Shaped by / breaks if:
  //  • Response field names change (`suggestions[].file_fingerprint` /
  //    `in_kb` / `page` / `score` / `title`) — the client picks the first
  //    `in_kb` row with a fingerprint and opens the reader there; a rename
  //    silently degrades to "not in your knowledge base".
  //  • `page` semantics change — it is the 1-indexed PDF page of the best
  //    chunk hit (chunk metadata `pdf_page_start`, confirmed 1-indexed),
  //    fed to the reader's `initialPageNumber`. Off-by-one → opens one page
  //    off; 0-indexed → page 0 is invalid and the jump fails.
  //  • The endpoint's side effects change: candidates are persisted
  //    (replace_candidate_suggestions) ONLY when the search actually runs —
  //    the note was re-analysed (seed hash changed), or the caller passed
  //    refresh=true / include_external=true. A plain tap whose cached
  //    candidates still match the note's overview is a pure read (one SELECT,
  //    no search). The client never needs refresh=true (its taps should
  //    serve the cache); the daemon handles invalidation after analysis.
  // ════════════════════════════════════════════════════════════════════════

  /// Daemon-ranked readings for a note, seeded from its cached analysis
  /// (topic + weak areas + knowledge gaps). KB-first and offline-safe by
  /// default. Read-through: the daemon serves persisted candidates when
  /// they still match the note's current overview; it re-runs the search
  /// (and re-persists) only after a re-analysis or refresh=true.
  ///
  /// Returns [] when the note has no analysis yet (daemon answers with a
  /// message + empty list — not an error).
  static Future<List<SuggestedReading>> forNote({
    required String bubbleId,
    required String noteId,
  }) async {
    final uri = Uri.parse("$suggestedReadingEndpoint/note/$bubbleId/$noteId");
    final response = await http.get(
      uri,
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final suggestions = body is Map ? body['suggestions'] : null;
      if (suggestions is! List) return const [];
      return suggestions
          .whereType<Map>()
          .map((s) => SuggestedReading.fromJson(Map<String, dynamic>.from(s)))
          .toList();
    }

    throw ApiException(
      response.statusCode,
      'Failed to fetch suggested readings '
      '(${response.statusCode}): ${response.body}',
      body: response.body,
    );
  }
}
