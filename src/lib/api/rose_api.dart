import 'dart:convert';
import 'package:http/http.dart' as http;

Future<String> askRose(String question) async {
  final url = Uri.parse("http://localhost:8000/chat/");
  final response = await http.post(
    url,
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"text": question}),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data["reply"] ?? "No reply provided.";
  } else {
    throw Exception("Failed to get hint from Rose.");
  }
}
