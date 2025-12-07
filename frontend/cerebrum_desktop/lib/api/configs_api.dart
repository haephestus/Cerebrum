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

  static Future<List<dynamic>> fetchInstalledChatModels() async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/models/chat/installed"),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      // Ensure correct extraction with fallback
      return decoded["installed_chat_models"] ?? [];
    } else {
      throw Exception("Failed to fetch chat models");
    }
  }

  static Future<Map<String, dynamic>> fetchInstalledEmbeddingModels() async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/models/embedding/installed"),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      return decoded;
    } else {
      throw Exception("Failed to fetch embedding models");
    }
  }

  static Future<Map<String, dynamic>> fetchOllamaStatus() async {
    final response = await http.get(
      Uri.parse("$configsEndpoint/models/embedding/installed"),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      return decoded;
    } else {
      throw Exception("Failed to fetch embedding models");
    }
  }
}
