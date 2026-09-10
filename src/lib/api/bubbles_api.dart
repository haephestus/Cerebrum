import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

// ══ CROSS-REPO CONTRACT: notes/bubbles API ⇄ daemon routes_bubble.py ════════
// Every method here is paired with a route in the daemon's routes_bubble.py.
// The offline-first client (NoteStore + SyncService) is built ON these shapes:
//
//  • createBubble → POST /bubbles/create?bubble_id=…  — bubble_id is a REQUIRED
//    query param (client mints md5(name), matching the daemon's own fallback
//    `hashlib.md5(name).hexdigest()`); omit it and the daemon 422s. Identity is
//    derived from the DEPENDENCY user, not the body — never put user_id in the
//    body (CreateStudyBubble must not require it).  [daemon: create_study_bubble]
//  • createNote → POST /{bubble_id}/create/notes  — pass note_id (client ULID);
//    the daemon uses it verbatim so the server filename is `<note_id>.json`,
//    aligning the on-device folder key with the server filename. Drop it and
//    identity churns.  [daemon: create_note]
//  • updateNote → PUT /{bubble_id}/notes/update/{filename}  — sends the WHOLE
//    page set; the daemon reconciles per `page_id` (edit/add/DELETE) with LWW.
//    Sending a partial set deletes the omitted pages. `page_id`s must be stable
//    (see paged_note_controller — they are NOT ULIDs on purpose; the daemon's
//    per-page analysis keys on them).  [daemon: update_note]
//  • fetchNotes → GET /{bubble_id}/notes  — returns 404 for an empty bubble;
//    the client maps 404 → [] (empty state, not an error). List responses carry
//    `ink: []` deliberately — never build the editor straight from a list entry.
//  • uploadNoteImage → POST /{bubble_id}/notes/{filename}/images  — returns an
//    ABSOLUTE url. The client does NOT embed that url; it stores bytes locally +
//    a `cerebrum-image://` ref (see note_image_resolver). Changing the ref
//    scheme or the daemon's image route breaks offline image render.
// ════════════════════════════════════════════════════════════════════════════

class BubblesApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get bubblesEndpoint => "$baseUrl/bubbles";

  // List all bubbles
  static Future<List<dynamic>> fetchBubbles() async {
    final response = await http.get(
      Uri.parse("$bubblesEndpoint/"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Failed to fetch bubbles");
  }

  // Fetch a bubble
  static Future<Map<String, dynamic>> fetchBubbleById(String bubbleId) async {
    final response = await http.get(
      Uri.parse("$bubblesEndpoint/$bubbleId"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Bubble not found");
  }

  // Update a bubble (name/description/domains/user_goals). Omitted fields
  // keep their daemon-side values; id/user_id/created_at are immutable.
  // CROSS-REPO CONTRACT ⇄ daemon routes_bubble.update_study_bubble.
  static Future<Map<String, dynamic>> updateBubble({
    required String bubbleId,
    String? name,
    String? description,
    List<String>? domains,
    List<String>? userGoals,
  }) async {
    final body = {
      if (name != null) "name": name,
      if (description != null) "description": description,
      if (domains != null) "domains": domains,
      if (userGoals != null) "user_goals": userGoals,
    };

    final response = await http.put(
      Uri.parse("$bubblesEndpoint/$bubbleId"),
      headers: await ApiConfig.headers(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      "Failed to update bubble: ${response.statusCode} - ${response.body}",
    );
  }

  // Create bubble  (matches CreateStudyBubble model). [bubbleId] is a
  // client-minted id sent as the `bubble_id` query param the daemon expects — it
  // names the bubble folder that note-id folders live under, so the client owns
  // bubble identity too (and it can be created with a stable id offline).
  static Future<Map<String, dynamic>> createBubble({
    required String name,
    required String description,
    required List<String> domains,
    required List<String> userGoals,
    required String bubbleId,
  }) async {
    final bubbleData = {
      "name": name,
      "description": description,
      "domains": domains,
      "user_goals": userGoals,
    };

    final response = await http.post(
      Uri.parse("$bubblesEndpoint/create").replace(
        queryParameters: {"bubble_id": bubbleId},
      ),
      headers: await ApiConfig.headers(),
      body: jsonEncode(bubbleData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception(
      "Failed to create bubble: ${response.statusCode} - ${response.body}",
    );
  }

  // Delete bubble
  static Future<void> deleteBubble(String bubbleId) async {
    final response = await http.delete(
      Uri.parse("$bubblesEndpoint/$bubbleId"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to delete bubble");
    }
  }
}

class BubbleNotesApi {
  static String get baseUrl => ApiConfig.baseUrl;

  static String notesEndpoint(String bubbleId) => "$baseUrl/bubbles/$bubbleId";

  /// Upload an image into a note's own `images/` folder and return an ABSOLUTE
  /// URL to embed in the editor's image block. The daemon returns a relative
  /// path; we prepend the current base URL so `Image.network` can load it. The
  /// note must already exist on the server (it needs a folder to store into).
  static Future<String> uploadNoteImage({
    required String bubbleId,
    required String filename,
    required List<int> bytes,
    required String imageFilename,
  }) async {
    final uri = Uri.parse("${notesEndpoint(bubbleId)}/notes/$filename/images");
    final request = http.MultipartRequest('POST', uri);
    // Multipart body → no JSON content-type; keep the auth headers (daemon key /
    // bearer / user id).
    request.headers.addAll(await ApiConfig.headers(json: false));
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: imageFilename),
    );

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return "$baseUrl${data['url']}";
    }
    throw Exception(
      "Failed to upload image: ${response.statusCode} - ${response.body}",
    );
  }

  // List all notes
  static Future<List<Map<String, dynamic>>> fetchNotes(String bubbleId) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(bubbleId)}/notes"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => e as Map<String, dynamic>).map((note) {
        // Ensure bubble_id exists
        note['bubble_id'] ??= bubbleId;
        return note;
      }).toList();
    }

    // A bubble with no notes yet (empty / missing notes dir) returns 404 — that's
    // "no notes", not a failure. Return an empty list so the notes screen shows
    // its empty state instead of an error.
    if (response.statusCode == 404) return [];

    throw Exception("Failed to fetch notes: ${response.statusCode}");
  }

  // Get a single note
  static Future<Map<String, dynamic>> fetchNoteByFileName(
    String bubbleId,
    String filename,
  ) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/get/$filename"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      final note = jsonDecode(response.body) as Map<String, dynamic>;
      // Ensure bubble_id exists
      note['bubble_id'] ??= bubbleId;
      return note;
    }

    throw Exception("Note not found: ${response.statusCode}");
  }

  // Inside your BubbleNotesApi class
  static Future<Map<String, dynamic>> toggleNoteAnalysis(
    String bubbleId,
    String filename,
  ) async {
    final response = await http.post(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/toggle_analysis/$filename"),
      headers: await ApiConfig.headers(json: false),
    );

    // Guard Clause: Handle failures immediately
    if (response.statusCode != 200) {
      throw Exception("Failed to toggle note analysis: ${response.statusCode}");
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // Create note. Pass [noteId] to hand the daemon a client-minted id — it uses
  // it verbatim (filename becomes `<noteId>.json`), so the client owns identity
  // end-to-end and the local folder / server filename stay aligned. Omit it and
  // the daemon mints its own ULID.
  static Future<Map<String, dynamic>> createNote({
    required String bubbleId,
    required String title,
    required Map<String, dynamic> content,
    List<Map<String, dynamic>>? ink,
    String? noteId,
  }) async {
    final note = {
      "title": title,
      "content": content,
      "ink": ink ?? [],
      if (noteId != null) "note_id": noteId,
    };

    final response = await http.post(
      Uri.parse("${notesEndpoint(bubbleId)}/create/notes"),
      headers: await ApiConfig.headers(),
      body: jsonEncode(note),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      // Ensure bubble_id exists
      result['bubble_id'] ??= bubbleId;
      return result;
    }

    throw Exception(
      "Failed to create note: ${response.statusCode} - ${response.body}",
    );
  }

  // Update note — sends the WHOLE page set. The daemon's /update endpoint
  // reconciles per page_id (edits + adds + deletes), so page merges/removals
  // persist. (The old sync/push path did an additive version-vector merge that
  // dropped edits and couldn't delete pages.)
  static Future<Map<String, dynamic>> updateNote({
    required String bubbleId,
    required String filename,
    required String title,
    required List<Map<String, dynamic>> pages,
    String? noteId,
  }) async {
    final id = noteId ??
        (filename.endsWith('.json')
            ? filename.substring(0, filename.length - 5)
            : filename);

    final note = {
      "title": title,
      "note_id": id,
      "bubble_id": bubbleId,
      "pages": pages,
    };

    final response = await http.put(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/update/$filename"),
      headers: await ApiConfig.headers(),
      body: jsonEncode(note),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      // Ensure bubble_id exists
      result['bubble_id'] ??= bubbleId;
      return result;
    }

    throw Exception("Failed to update note: ${response.statusCode}");
  }

  // Rename note
  static Future<void> renameNote(
    String bubbleId,
    String oldFilename,
    String newFilename,
  ) async {
    final response = await http.put(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/rename/$oldFilename"),
      headers: await ApiConfig.headers(),
      body: jsonEncode({"title": newFilename}),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to rename note: ${response.body}");
    }
  }

  // Delete note
  static Future<void> deleteNote(String bubbleId, String filename) async {
    final response = await http.delete(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/delete/$filename"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete note: ${response.statusCode}");
    }
  }
}

class BubbleChatApi {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Helper to build the base project chat endpoint
  static String chatApi(String bubbleId) {
    return "$baseUrl/project/$bubbleId/chat";
  }

  /// Send a chat query to the LLM for this project
  static Future<Map<String, dynamic>> sendMessage({
    required String bubbleId,
    required String message,
  }) async {
    final body = {"query": message};

    final response = await http.post(
      Uri.parse(chatApi(bubbleId)),
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

  /// Retrieve past chat history for a project
  static Future<List<dynamic>> fetchChatHistory(String bubbleId) async {
    final response = await http.get(
      Uri.parse("${chatApi(bubbleId)}/history"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception("Failed to fetch chat history (${response.statusCode})");
  }

  /// Clear the chat history for a project
  static Future<void> clearChatHistory(String bubbleId) async {
    final response = await http.delete(
      Uri.parse("${chatApi(bubbleId)}/clear"),
      headers: await ApiConfig.headers(json: false),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 202) {
      throw Exception("Failed to clear chat history (${response.statusCode})");
    }
  }
}
