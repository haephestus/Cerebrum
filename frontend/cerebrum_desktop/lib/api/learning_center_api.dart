import 'dart:convert';
import 'package:http/http.dart' as http;

class LearningCenterApi {
  static const baseUrl = "http://localhost:8000";
  static const String learningCenterEndpoint = "$baseUrl/learn";

  static Future<String?> getNoteAnalysis({
    required String bubbleId,
    required String noteId,
    int version = 0,
  }) async {
    // Build URL with query parameters
    final uri = Uri.parse("$learningCenterEndpoint/fetch/analysis").replace(
      queryParameters: {
        'bubble_id': bubbleId,
        'note_id': noteId,
        'version': version.toString(),
      },
    );

    print('DEBUG API: Fetching from $uri');

    try {
      final response = await http.get(uri);

      print('DEBUG API: Response status: ${response.statusCode}');
      print('DEBUG API: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final body = response.body;

        // Handle empty or null response
        if (body.isEmpty || body == 'null') {
          print('DEBUG API: Empty or null response');
          return null;
        }

        // Try to decode as JSON first
        try {
          final decoded = jsonDecode(body);
          print('DEBUG API: JSON decoded successfully: $decoded');
          return decoded as String?;
        } catch (e) {
          // If JSON decode fails, assume it's a plain string
          print('DEBUG API: Not JSON, returning as plain string');
          return body;
        }
      } else if (response.statusCode == 404) {
        print('DEBUG API: Analysis not found (404)');
        return null;
      } else {
        throw Exception(
          "Failed to fetch analysis. Status: ${response.statusCode}, Body: ${response.body}",
        );
      }
    } catch (e) {
      print('DEBUG API: Exception caught: $e');
      rethrow;
    }
  }
}
