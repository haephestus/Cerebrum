import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../../api/api_config.dart';

// ══ CROSS-REPO CONTRACT: chat ⇄ daemon routes_chat.py ══════════════════════
// `POST /chat/{bubble_id}` body `{text, history_limit}` -> `{answer, sources,
// user_message_id, message_id, compaction}`. `POST /chat/notes/{note_id}`
// takes the same body and returns the same shape, with `kind: note|kb` on
// sources. The bubble id is a path segment and the request field is `text`,
// not `query`; either change silently 404s/422s the editor chat.
//
// History lives in `study_bubbles/<bubble_id>/chat/history.db` on the daemon.
// `GET /chat/notes/{note_id}/history` (or `/chat/{bubble_id}/history`) returns
// `{messages, compactions}`.
class ChatApi {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Daemon route: `POST /chat/{bubble_id}` (`routes_chat.py`). The bubble id
  /// is the path segment; ownership is checked server-side before retrieval.
  static String chatApi(String bubbleId) {
    return "$baseUrl/chat/$bubbleId";
  }

  /// Daemon route: `POST /chat/notes/{note_id}`. Note-scoped retrieval is
  /// grounded on the note plus the sources its analysis used.
  static String noteChatApi(String noteId) {
    return "$baseUrl/chat/notes/$noteId";
  }

  static String noteHistoryApi(String noteId) {
    return "$baseUrl/chat/notes/$noteId/history";
  }

  static String bubbleHistoryApi(String bubbleId, {String? noteId}) {
    final uri = Uri.parse("$baseUrl/chat/$bubbleId/history");
    if (noteId == null || noteId.isEmpty) return uri.toString();
    return uri.replace(queryParameters: {"note_id": noteId}).toString();
  }

  /// Send a chat query to the LLM for this bubble or note.
  ///
  /// The request body is `{text, history_limit}` (not `{query}`): the
  /// daemon's `ChatRequest` model names the field `text`, and a mismatch is a
  /// 422, not a no-op. `noteId` switches to the note-scoped route; without it
  /// the bubble-wide thread is used.
  static Future<Map<String, dynamic>> sendMessage({
    required String bubbleId,
    String? noteId,
    required String message,
    int historyLimit = 10,
  }) async {
    final body = {"text": message, "history_limit": historyLimit};
    final url =
        (noteId != null && noteId.isNotEmpty)
            ? noteChatApi(noteId)
            : chatApi(bubbleId);

    final response = await http.post(
      Uri.parse(url),
      headers: await ApiConfig.headers(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception(
      "Chat request failed (${response.statusCode}): ${response.body}",
    );
  }

  /// Load the persisted transcript for a note (or the bubble-wide thread).
  static Future<Map<String, dynamic>> history({
    String? bubbleId,
    String? noteId,
    int limit = 200,
  }) async {
    final String url;
    if (noteId != null && noteId.isNotEmpty) {
      url = noteHistoryApi(noteId);
    } else if (bubbleId != null && bubbleId.isNotEmpty) {
      url = bubbleHistoryApi(bubbleId);
    } else {
      throw ArgumentError("history requires bubbleId or noteId");
    }

    final uri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        'limit': limit.toString(),
      },
    );
    final response = await http.get(uri, headers: await ApiConfig.headers());

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception(
      "Chat history failed (${response.statusCode}): ${response.body}",
    );
  }

  /// Delete a note's thread (or the bubble-wide thread).
  static Future<int> clearHistory({String? bubbleId, String? noteId}) async {
    final String url;
    if (noteId != null && noteId.isNotEmpty) {
      url = noteHistoryApi(noteId);
    } else if (bubbleId != null && bubbleId.isNotEmpty) {
      url = bubbleHistoryApi(bubbleId);
    } else {
      throw ArgumentError("clearHistory requires bubbleId or noteId");
    }

    final response = await http.delete(
      Uri.parse(url),
      headers: await ApiConfig.headers(),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body["deleted"] as num?)?.toInt() ?? 0;
    }

    throw Exception(
      "Chat history clear failed (${response.statusCode}): ${response.body}",
    );
  }
}
