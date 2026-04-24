import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigsApi {
  static const baseUrl = "http://localhost:8000";
  static const String configsEndpoint = "$baseUrl/user";

  static Future<Map<String, dynamic>> fetchConfigs() async {
    final response = await http.get(Uri.parse("$configsEndpoint/config"));
    if (response.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      return decoded;
    } else {
      throw Exception("Failed to fetch configs");
    }
  }

  // Fixed: Return Map instead of List to match usage in ollama_settings.dart
  static Future<Map<String, dynamic>> fetchInstalledChatModels() async {
    final resp = await http.get(
      Uri.parse("$configsEndpoint/models/chat/installed"),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    } else {
      throw Exception("Failed to fetch installed chat models");
    }
  }

  // Fixed: Return Map instead of List to match usage in ollama_settings.dart
  static Future<Map<String, dynamic>> fetchInstalledEmbeddingModels() async {
    final resp = await http.get(
      Uri.parse("$configsEndpoint/models/embedding/installed"),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    } else {
      throw Exception("Failed to fetch installed embedding models");
    }
  }

  // Fixed: Correct success/failure logic and send proper query parameter
  static Future<Map<String, dynamic>> updateChatModel(String model) async {
    final response = await http.post(
      Uri.parse("$configsEndpoint/config/models/chat?chat_model=$model"),
      headers: {"Content-Type": "application/json"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to update chat model: ${response.body}");
    }
  }

  // Fixed: Correct success/failure logic and send proper query parameter
  static Future<Map<String, dynamic>> updateEmbeddingModel(String model) async {
    final response = await http.post(
      Uri.parse(
        "$configsEndpoint/config/models/embedding?embedding_model=$model",
      ),
      headers: {"Content-Type": "application/json"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to update embedding model: ${response.body}");
    }
  }

  // Fixed: Use correct endpoint for Ollama status
  static Future<Map<String, dynamic>> fetchOllamaStatus() async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/ollama/status"),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      return decoded;
    } else {
      throw Exception("Failed to fetch Ollama status");
    }
  }

  // Fetch available online models
  static Future<Map<String, dynamic>> fetchOnlineModels() async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/models/online"),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch online models");
    }
  }

  // Download a model
  static Future<Map<String, dynamic>> downloadModel(String modelName) async {
    final response = await http.post(
      Uri.parse("$configsEndpoint/models/download/$modelName"),
      headers: {"Content-Type": "application/json"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to download model: ${response.body}");
    }
  }

  // Fetch model details (description and available tags/versions)
  static Future<Map<String, dynamic>> fetchModelDetails(
    String modelName,
  ) async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/models/$modelName/details"),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch model details: ${response.body}");
    }
  }
}
