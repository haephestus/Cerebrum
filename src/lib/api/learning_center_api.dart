import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_store.dart';
import 'api_config.dart';

class LearningCenterApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get learningCenterEndpoint => "$baseUrl/learn";

  /// Fetch whatever analysis is cached (chunk_diagnostics + note_overview),
  /// regardless of whether it matches the note's current version. Pass
  /// currentVersion to also get an is_current flag back so the caller can
  /// show a staleness notice instead of silently serving old content.
  static Future<Map<String, dynamic>?> getFullCachedAnalysis({
    required String bubbleId,
    required String noteId,
    double? currentVersion,
  }) async {
    final uri = Uri.parse(
      "$learningCenterEndpoint/fetch/analysis/full",
    ).replace(
      queryParameters: {
        "bubble_id": bubbleId,
        "note_id": noteId,
        if (currentVersion != null)
          "current_version": currentVersion.toString(),
      },
    );
    final response = await http.get(
      uri,
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body == null ? null : body as Map<String, dynamic>;
    }

    throw Exception("Failed to fetch full analysis: ${response.statusCode}");
  }

  // ══ CROSS-REPO CONTRACT: engram submit ⇄ daemon routes_learning_center.py ══
  // Paired with daemon `POST /learn/engrams/{type}/{engram_id}/submit` and its
  // Pydantic bodies (MCQSubmission / FlashcardSubmission / ShortQuestionSubmission
  // / LongQuestionSubmission).
  //
  // Shaped by / breaks if:
  //  • Body FIELD NAMES must match the daemon models exactly. Short-question
  //    items are {question_index:int, raw_answer:str} — `question_index` is
  //    matched server-side against each question's `question_number`
  //    (ai_grading.questions_by_index); a wrong name/type or a 0-based index →
  //    answers silently dropped (scored 0), no error. See engram_models.dart.
  //  • `attempt_id` (nanoid, 32-hex — see id.dart) + `attempted_at` are
  //    CLIENT-OWNED. The daemon uses them verbatim and dedupes a replay on the id
  //    (create_attempt = INSERT OR IGNORE; short/long won't re-enqueue a grading
  //    job). Change the id shape/uniqueness → duplicate attempts + double LLM
  //    grading on offline replay. `attempted_at` drives daemon
  //    get_recent_attempt_scores ordering (mastery priority) — drop it and the
  //    student's real answer time is lost.
  //  • mcq/flashcard respond synchronously ({attempt_id, is_correct?,
  //    mastery_state}); short/long respond {attempt_id, job_id, status} and are
  //    graded async — see fetchGradingJob below. EngramSyncService keys on the
  //    presence of `job_id` to decide sync vs async.
  // ════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> submitMcq({
    required String engramId,
    required String userId,
    required String selectedOption,
    int targetCognitiveLevel = 1,
    String? attemptId,
    String? attemptedAt,
  }) async {
    final uri = Uri.parse(
      '$learningCenterEndpoint/engrams/mcq/$engramId/submit',
    );
    final response = await http.post(
      uri,
      headers: await ApiConfig.headers(userId: userId),
      body: jsonEncode({
        'selected_option': selectedOption,
        'target_cognitive_level': targetCognitiveLevel,
        if (attemptId != null) 'attempt_id': attemptId,
        if (attemptedAt != null) 'attempted_at': attemptedAt,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to submit MCQ (${response.statusCode}): ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> submitFlashcard({
    required String engramId,
    required String userId,
    required String selfRating, // "again" | "hard" | "good" | "easy"
    int targetCognitiveLevel = 1,
    String? attemptId,
    String? attemptedAt,
  }) async {
    final uri = Uri.parse(
      '$learningCenterEndpoint/engrams/flashcard/$engramId/submit',
    );
    final response = await http.post(
      uri,
      headers: await ApiConfig.headers(userId: userId),
      body: jsonEncode({
        'self_rating': selfRating,
        'target_cognitive_level': targetCognitiveLevel,
        if (attemptId != null) 'attempt_id': attemptId,
        if (attemptedAt != null) 'attempted_at': attemptedAt,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to submit flashcard (${response.statusCode}): ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> submitShortQuestion({
    required String engramId,
    required String userId,
    // Daemon contract: [{question_index: int, raw_answer: str}].
    required List<Map<String, dynamic>> responses,
    int targetCognitiveLevel = 1,
    String? attemptId,
    String? attemptedAt,
  }) async {
    final uri = Uri.parse(
      '$learningCenterEndpoint/engrams/short_question/$engramId/submit',
    );
    final response = await http.post(
      uri,
      headers: await ApiConfig.headers(userId: userId),
      body: jsonEncode({
        'responses': responses,
        'target_cognitive_level': targetCognitiveLevel,
        if (attemptId != null) 'attempt_id': attemptId,
        if (attemptedAt != null) 'attempted_at': attemptedAt,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to submit short question (${response.statusCode}): ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> submitLongQuestion({
    required String engramId,
    required String userId,
    required String rawAnswer,
    int targetCognitiveLevel = 1,
    String? attemptId,
    String? attemptedAt,
  }) async {
    final uri = Uri.parse(
      '$learningCenterEndpoint/engrams/long_question/$engramId/submit',
    );
    final response = await http.post(
      uri,
      headers: await ApiConfig.headers(userId: userId),
      body: jsonEncode({
        'raw_answer': rawAnswer,
        'target_cognitive_level': targetCognitiveLevel,
        if (attemptId != null) 'attempt_id': attemptId,
        if (attemptedAt != null) 'attempted_at': attemptedAt,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to submit long question (${response.statusCode}): ${response.body}',
    );
  }

  /// Poll an async grading job (short/long submits return a `job_id`) via the
  /// daemon's `GET /learn/engrams/grading/jobs/{job_id}`. Returns the job map
  /// (`{status, error, [score, grader], ...}`) once it's **terminal** (`done` or
  /// `failed`); null while still `pending`/`processing` (or 404/unknown); throws
  /// only on a real HTTP error (so the caller can tell "keep waiting" from
  /// "offline").
  ///
  /// CROSS-REPO CONTRACT ⇄ daemon `get_grading_job_status`: the PATH
  /// (`/engrams/grading/jobs/{id}`, NOT `/grading_result/…`) and the STATUS
  /// vocabulary (`pending|processing|done|failed`) are the daemon's. Change
  /// either and grades never resolve (poll forever / 404). `done` carries
  /// `score`+`grader`; no per-question feedback here (that's on the responses).
  static Future<Map<String, dynamic>?> fetchGradingJob(String jobId) async {
    final uri = Uri.parse(
      '$learningCenterEndpoint/engrams/grading/jobs/$jobId',
    );
    final response = await http.get(
      uri,
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) {
      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as String?;
      // Terminal states carry the outcome; done also has score + grader.
      if (status == 'done' || status == 'failed') return job;
      return null; // pending / processing → keep waiting
    }
    // 404 = unknown/unowned job → nothing to wait for.
    if (response.statusCode == 404) return null;
    throw Exception('Failed to fetch grading job (${response.statusCode})');
  }

  static Future<EngramListResponse> listEngrams({
    required String userId,
    String? bubbleId,
    String? noteId,
    String? state,
    // Fetch answer-bearing fields (correct_option / expected_answer /
    // mark_scheme) so they can be cached for offline self-comparison. The client
    // reveals them only AFTER the student submits (client-gated reveal).
    bool includeAnswers = true,
  }) async {
    // ══ CROSS-REPO CONTRACT: listEngrams ⇄ daemon `list_engrams` ═════════════
    // • `include_answers=true` flips the daemon from `_sanitize_for_presentation`
    //   (answers stripped, anti-scrape) to `asdict(e)` (full engram incl.
    //   correct_option/expected_answer/mark_scheme AND bubble_id). Offline
    //   comparison + offline MCQ grading DEPEND on this; the reveal-after-answer
    //   gate is enforced CLIENT-SIDE (see completion screens). If the daemon ever
    //   role-gates include_answers, offline compare/MCQ-grade break.
    // • Scoping mirrors the daemon: none→all, bubble_id→bubble, bubble_id+note_id
    //   →note. Query nulls MUST be omitted (not sent empty) — see the note below.
    // • EngramStore caches the raw payload here; offline reads rebuild via
    //   Engram.fromJson, so the cached JSON shape must stay fromJson-compatible.
    // ════════════════════════════════════════════════════════════════════════
    // IMPORTANT: every one of these must be conditional. Uri.replace
    // treats a null query value as "include this key with no value"
    // (e.g. `?bubble_id`), NOT "omit the key" -- so an unconditional
    // 'bubble_id': bubbleId sends bubble_id="" to the backend when
    // bubbleId is null. FastAPI then sees bubble_id as an empty STRING,
    // not None, and the router's `elif bubble_id is not None` branch
    // fires with an empty id that matches nothing -- silently returning
    // zero engrams instead of falling through to get_all_engrams. This
    // was the bug behind the global dashboard showing "No engrams yet."
    // even though the same request via curl (bubble_id omitted
    // entirely) returned real data.
    final uri = Uri.parse('$learningCenterEndpoint/engrams/list').replace(
      queryParameters: {
        if (bubbleId != null) 'bubble_id': bubbleId,
        if (noteId != null) 'note_id': noteId,
        if (state != null) 'state': state,
        if (includeAnswers) 'include_answers': 'true',
      },
    );

    // Local-first: cache the fetched engrams (with answers) for cold-start
    // offline quizzing; on any network failure serve the local cache so a quiz
    // can still be opened offline.
    try {
      final response = await http.get(
        uri,
        headers: await ApiConfig.headers(json: false, userId: userId),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final rawEngrams =
            ((json['engrams'] as List?) ?? const [])
                .cast<Map<String, dynamic>>();
        await EngramStore.cacheRaw(
          userId: userId,
          bubbleId: bubbleId,
          engrams: rawEngrams,
        );
        return EngramListResponse.fromJson(json);
      }
      throw Exception('Failed to fetch engrams (${response.statusCode})');
    } catch (_) {
      return EngramStore.cachedResponse(
        userId: userId,
        bubbleId: bubbleId,
        noteId: noteId,
      );
    }
  }

  static Future<String?> runActiveAnalysis({
    required String bubbleId,
    required String filename,
  }) async {
    final uri = Uri.parse(
      "$learningCenterEndpoint/active_analysis/$bubbleId/$filename",
    );

    final response = await http.post(
      uri,
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      final body = response.body;
      if (body.isEmpty || body == 'null') return null;

      try {
        final decoded = jsonDecode(body);
        return decoded as String?;
      } catch (_) {
        return body;
      }
    }

    throw Exception(
      "Failed to run active analysis. Status: ${response.statusCode}, Body: ${response.body}",
    );
  }

  static Future<Map<String, dynamic>?> getAnalysisStatus({
    required String bubbleId,
    required String filename,
  }) async {
    final response = await http.get(
      Uri.parse("$learningCenterEndpoint/analysis_status/$bubbleId/$filename"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) return null;

    throw Exception("Failed to fetch analysis status: ${response.statusCode}");
  }
}
