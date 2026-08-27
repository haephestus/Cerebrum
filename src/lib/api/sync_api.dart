import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:cerebrum/api/api_config.dart';

/// Client half of the note offline-sync protocol (gap 1 / stream C).
///
/// Talks to the daemon's `/sync` endpoints:
///   * push  — send our version of a note; the server merges it (version-vector:
///             dominates → take newer, concurrent → last-writer-wins per page,
///             ink → stroke-id union) and returns the merged note, the pages
///             that had concurrent conflicts, and the merged version vector.
///   * pull  — the server's current version of a note + its vector.
///   * replicaId — the hub's stable replica id (the peer our cursor keys on).
class SyncApi {
  static String get baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> push(
    String bubbleId,
    String noteId,
    Map<String, dynamic> note,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/sync/push/$bubbleId/$noteId"),
      headers: await ApiConfig.headers(),
      body: jsonEncode(note),
    );
    if (response.statusCode != 200) {
      throw Exception("sync push failed: ${response.statusCode} ${response.body}");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> pull(String bubbleId, String noteId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/sync/pull/$bubbleId/$noteId"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode != 200) {
      throw Exception("sync pull failed: ${response.statusCode}");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<String> replicaId() async {
    final response = await http.get(
      Uri.parse("$baseUrl/sync/replica-id"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode != 200) {
      throw Exception("sync replica-id failed: ${response.statusCode}");
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['replica_id']
        as String;
  }
}
