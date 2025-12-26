import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

class KnowledgebaseApi {
  static const baseUrl = "http://localhost:8000";
  static const knowledgebaseEndpoint =
      "$baseUrl/knowledgebase"; // Match FastAPI route

  // Show files in the registry
  static Future<List<Map<String, dynamic>>> showFiles() async {
    final response = await http.get(Uri.parse("$knowledgebaseEndpoint/show"));
    if (response.statusCode == 200) {
      final List<dynamic> decoded = jsonDecode(response.body);
      return decoded.cast<Map<String, dynamic>>();
    }
    throw Exception("Failed to fetch files");
  }

  // Pick a file (returns null if cancelled)
  static Future<PlatformFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false, // For desktop, we use file path instead
      withReadStream: false,
    );
    return result?.files.single;
  }

  // Upload a specific file
  static Future<Map<String, dynamic>> uploadFile(PlatformFile file) async {
    final uri = Uri.parse("$knowledgebaseEndpoint/upload");
    final request = http.MultipartRequest("POST", uri);

    // Desktop platforms (Linux, macOS, Windows) use file paths
    if (file.path != null) {
      print("Uploading from path: ${file.path}");
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ),
      );
    }
    // Web/mobile might use bytes
    else if (file.bytes != null) {
      print("Uploading from bytes");
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else {
      throw Exception("No file path or bytes available");
    }

    print("Sending request to: $uri");
    final response = await request.send();
    final body = await response.stream.bytesToString();

    print("Response status: ${response.statusCode}");
    print("Response body: $body");

    if (response.statusCode == 200) {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        throw Exception("Unexpected response format: $decoded");
      }
    }

    throw Exception("Upload failed (${response.statusCode}): $body");
  }

  // Trigger markdown conversion
  static Future<Map<String, dynamic>> convertMarkdown() async {
    final response = await http.post(
      Uri.parse("$knowledgebaseEndpoint/markdowninator"),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Conversion failed");
  }

  // Trigger embedding
  static Future<Map<String, dynamic>> embedFiles() async {
    final response = await http.post(
      Uri.parse("$knowledgebaseEndpoint/embeddinator"),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Embedding failed");
  }
}
