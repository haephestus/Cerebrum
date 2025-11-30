import 'dart:convert';
import 'package:http/http.dart' as http;

class ProjectsApi {
  static const baseUrl = "http://localhost:8000";
  static const String projectsEndpoint = "$baseUrl/projects";

  // List all projects
  static Future<List<dynamic>> fetchProjects() async {
    final response = await http.get(Uri.parse("$projectsEndpoint/"));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Failed to fetch projects");
  }

  // Fetch a project
  static Future<Map<String, dynamic>> fetchProjectById(String projectId) async {
    final response = await http.get(Uri.parse("$projectsEndpoint/$projectId"));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("Project not found");
  }

  // Create a new project
  static Future<Map<String, dynamic>> createProject({
    required String name,
    required String description,
    required List<String> domains,
    required List<String> userGoals,
  }) async {
    final project = {
      "name": name,
      "description": description,
      "domains": domains,
      "user_goals": userGoals,
    };

    final response = await http.post(
      Uri.parse("$projectsEndpoint/create"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(project),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }

    throw Exception("Failed to create project ${response.statusCode}");
  }

  // Delete a project
  static Future<void> deleteProject(String projectId) async {
    final response = await http.delete(
      Uri.parse("$projectsEndpoint/$projectId"),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 202) {
      throw Exception("Failed to delete project");
    }
  }
}

class ProjectNotesApi {
  static const baseUrl = "http://localhost:8000";

  static String notesEndpoint(String projectId) =>
      "$baseUrl/projects/$projectId";

  // List all notes
  static Future<List<Map<String, dynamic>>> fetchNotes(String projectId) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(projectId)}/notes"),
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);

      return body.map((e) => e as Map<String, dynamic>).map((note) {
        // Convert project_id → projectId
        if (note.containsKey('project_id')) {
          note['projectId'] = note['project_id'];
          note.remove('project_id');
        } else {
          note['projectId'] = projectId;
        }
        return note;
      }).toList();
    }

    throw Exception("Failed to fetch notes (${response.statusCode})");
  }

  // Fetch a single note
  static Future<Map<String, dynamic>> fetchNoteByFileName(
    String projectId,
    String filename,
  ) async {
    final response = await http.get(
      Uri.parse("${notesEndpoint(projectId)}/notes/get/$filename"),
    );

    if (response.statusCode == 200) {
      final note = jsonDecode(response.body) as Map<String, dynamic>;

      if (note.containsKey('project_id')) {
        note['projectId'] = note['project_id'];
        note.remove('project_id');
      } else {
        note['projectId'] = projectId;
      }

      return note;
    }

    throw Exception("Note not found: ${response.statusCode}");
  }

  // Create a new note
  static Future<Map<String, dynamic>> createNote({
    required String projectId,
    required String title,
    required Map<String, dynamic> content,
    List<Map<String, dynamic>>? ink,
  }) async {
    // Ensure document key exists
    if (!content.containsKey('document')) {
      content = {'document': content};
    }

    final note = {"title": title, "content": content, "ink": ink ?? []};

    final response = await http.post(
      Uri.parse("${notesEndpoint(projectId)}/create/notes"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(note),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final result = jsonDecode(response.body);

      // Convert project_id → projectId
      if (result.containsKey('project_id')) {
        result['projectId'] = result['project_id'];
        result.remove('project_id');
      } else {
        result['projectId'] = projectId;
      }

      return result;
    }

    throw Exception("Failed to create note (${response.statusCode})");
  }

  // Update a note
  static Future<Map<String, dynamic>> updateNote({
    required String projectId,
    required String filename,
    required String title,
    required Map<String, dynamic> content,
    List<Map<String, dynamic>>? ink,
  }) async {
    // Ensure document key exists
    if (!content.containsKey('document')) {
      content = {'document': content};
    }

    final note = {"title": title, "content": content, "ink": ink ?? []};

    final response = await http.put(
      Uri.parse("${notesEndpoint(projectId)}/notes/update/$filename"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(note),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);

      if (result.containsKey('project_id')) {
        result['projectId'] = result['project_id'];
        result.remove('project_id');
      } else {
        result['projectId'] = projectId;
      }

      return result;
    }

    throw Exception("Failed to update note (${response.statusCode})");
  }

  // Delete a note
  static Future<void> deleteNote(String projectId, String filename) async {
    final response = await http.delete(
      Uri.parse("${notesEndpoint(projectId)}/notes/delete/$filename"),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 202) {
      throw Exception("Failed to delete note (${response.statusCode})");
    }
  }
}

class ProjectChatApi {
  static const baseUrl = "http://localhost:8000";

  static String chatApi(String projectId) {
    return "$baseUrl/projects/$projectId/chat";
  }

  // Send chat message
  static Future<Map<String, dynamic>> sendMessage({
    required String projectId,
    required String message,
  }) async {
    final body = {"query": message};

    final response = await http.post(
      Uri.parse(chatApi(projectId)),
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

  // Fetch chat history
  static Future<List<dynamic>> fetchChatHistory(String projectId) async {
    final response = await http.get(Uri.parse("${chatApi(projectId)}/history"));

    if (response.statusCode == 200) return jsonDecode(response.body);

    throw Exception("Failed to fetch chat history (${response.statusCode})");
  }

  // Clear chat history
  static Future<void> clearChatHistory(String projectId) async {
    final response = await http.delete(
      Uri.parse("${chatApi(projectId)}/clear"),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 202) {
      throw Exception("Failed to clear chat history (${response.statusCode})");
    }
  }
}
