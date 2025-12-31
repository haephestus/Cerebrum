import 'dart:convert';
import 'package:http/http.dart' as http;

class BubblesApi {
  static const baseUrl = "http://localhost:8000";
  static const bubblesEndpoint = "$baseUrl/bubbles";

  // List all bubbles
  static Future<List<dynamic>> fetchBubbles() async {
    final response = await http.get(Uri.parse("$bubblesEndpoint/"));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Failed to fetch bubbles");
  }

  // Fetch a bubble
  static Future<Map<String, dynamic>> fetchBubbleById(String bubbleId) async {
    final response = await http.get(Uri.parse("$bubblesEndpoint/$bubbleId"));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Bubble not found");
  }

  // Create bubble  (matches CreateStudyBubble model)
  static Future<Map<String, dynamic>> createBubble({
    required String name,
    required String description,
    required List<String> domains,
    required List<String> userGoals,
  }) async {
    final bubbleData = {
      "name": name,
      "description": description,
      "domains": domains,
      "user_goals": userGoals,
    };

    final response = await http.post(
      Uri.parse("$bubblesEndpoint/create"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(bubbleData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to create bubble");
  }

  // Delete bubble
  static Future<void> deleteBubble(String bubbleId) async {
    final response = await http.delete(Uri.parse("$bubblesEndpoint/$bubbleId"));
    if (response.statusCode != 200) {
      throw Exception("Failed to delete bubble");
    }
  }
}

class BubbleNotesApi {
  static const baseUrl = "http://localhost:8000";

  static String notesEndpoint(String bubbleId) => "$baseUrl/bubbles/$bubbleId";

  // List all notes
  static Future<List<Map<String, dynamic>>> fetchNotes(String bubbleId) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(bubbleId)}/notes"),
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => e as Map<String, dynamic>).map((note) {
        // Ensure bubble_id exists
        note['bubble_id'] ??= bubbleId;
        return note;
      }).toList();
    }

    throw Exception("Failed to fetch notes: ${response.statusCode}");
  }

  // Get a single note
  static Future<Map<String, dynamic>> fetchNoteByFileName(
    String bubbleId,
    String filename,
  ) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/get/$filename"),
    );

    if (response.statusCode == 200) {
      final note = jsonDecode(response.body) as Map<String, dynamic>;
      // Ensure bubble_id exists
      note['bubble_id'] ??= bubbleId;
      return note;
    }

    throw Exception("Note not found: ${response.statusCode}");
  }

  // Create note
  static Future<Map<String, dynamic>> createNote({
    required String bubbleId,
    required String title,
    required Map<String, dynamic> content,
    List<Map<String, dynamic>>? ink,
  }) async {
    final note = {"title": title, "content": content, "ink": ink ?? []};

    final response = await http.post(
      Uri.parse("${notesEndpoint(bubbleId)}/create/notes"),
      headers: {"Content-Type": "application/json"},
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

  // Update note
  static Future<Map<String, dynamic>> updateNote({
    required String bubbleId,
    required String filename,
    required String title,
    required Map<String, dynamic> content,
    List<Map<String, dynamic>>? ink,
  }) async {
    // Ensure content has document key
    if (!content.containsKey('document')) {
      content = {'document': content};
    }

    final note = {
      "ink": ink ?? [],
      "title": title,
      "content": content,
      "bubble_id": bubbleId,
    };

    final response = await http.put(
      Uri.parse("${notesEndpoint(bubbleId)}/notes/update/$filename"),
      headers: {"Content-Type": "application/json"},
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
      headers: {"Content-Type": "application/json"},
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
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete note: ${response.statusCode}");
    }
  }
}

class BubbleChatApi {
  static const baseUrl = "http://localhost:8000";

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
      headers: {"Content-Type": "application/json"},
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
    final response = await http.get(Uri.parse("${chatApi(bubbleId)}/history"));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception("Failed to fetch chat history (${response.statusCode})");
  }

  /// Clear the chat history for a project
  static Future<void> clearChatHistory(String bubbleId) async {
    final response = await http.delete(Uri.parse("${chatApi(bubbleId)}/clear"));

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 202) {
      throw Exception("Failed to clear chat history (${response.statusCode})");
    }
  }
}
