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
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else {
      throw Exception("No file path or bytes available");
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();

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

  static Future<dynamic> processFile(String fileFingerprint) async {
    final response = await http.post(
      Uri.parse("$knowledgebaseEndpoint/process-file/$fileFingerprint"),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to delete");
    }
  }

  static Future<dynamic> deleteFiles(
    String filename,
    String filepath,
    String fileFingerprint,
  ) async {
    //delete from file and from registry
    final response = await http.delete(
      Uri.parse("$knowledgebaseEndpoint/delete/"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'filename': filename,
        'filepath': filepath,
        'file_fingerprint': fileFingerprint,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to delete");
    }
  }
}
