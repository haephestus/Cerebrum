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
}
