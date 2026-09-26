import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class PlannerApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get plannerEnpoint => "$baseUrl/study_plan";

  static Future<String> generatePlan(
    String userId,
    Map<String, Map<dynamic, dynamic>> userProfile,
    String targetRole,
    String context,
    String historicalPlanId,
  ) async {
    final planData = {
      "user_id": userId,
      "user_profile": userProfile,
      "target_role": targetRole,
      "context": context,
      "historical_plan_id": historicalPlanId,
    };
    final response = await http.post(
      Uri.parse("$plannerEnpoint/generate"),
      headers: await ApiConfig.headers(),
      body: jsonEncode(planData),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to generate study plan");
  }

  // StudyPlanApi — replace getActivePlans with:
  static Future<List<Map<String, dynamic>>> getPlans({
    required String userId,
  }) async {
    final uri = Uri.parse('$baseUrl/study_plan/user/all');
    final response = await http.get(
      uri,
      headers: await ApiConfig.headers(json: false, userId: userId),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['plans'] as List);
    }
    throw Exception(
      'Failed to fetch plans (${response.statusCode}): ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> getPhaseWeeks(
    planId,
    phaseId,
    userId,
  ) async {
    final response = await http.get(
      Uri.parse("$plannerEnpoint/$planId/weeks/phase/$phaseId"),
      headers: await ApiConfig.headers(userId: userId),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to get Phase Weeks");
  }

  static Future<Map<String, dynamic>> studyPlan(String planId) async {
    final response = await http.get(Uri.parse("$plannerEnpoint/$planId"));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to get studies plans");
  }

  static Future<Map<String, dynamic>> activePlan(String userId) async {
    final response = await http.get(
      Uri.parse("$plannerEnpoint/$userId"),
      headers: await ApiConfig.headers(userId: userId),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to get active study plans");
  }

  static Future<Map<String, dynamic>> getProgress({
    required String planId,
    required String userId,
  }) async {
    final response = await http.get(
      Uri.parse("$plannerEnpoint/$planId/progress"),
      headers: await ApiConfig.headers(json: false, userId: userId),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      "Failed to fetch plan progress (${response.statusCode}): ${response.body}",
    );
  }

  static Future<void> completeTask({
    required int taskId,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse("$plannerEnpoint/tasks/$taskId/complete"),
      headers: await ApiConfig.headers(userId: userId),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to complete task (${response.statusCode})");
    }
  }

  static Future<void> statusUpdate({
    required String planId,
    required String status,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse("$plannerEnpoint/update/$planId/$status"),
      headers: await ApiConfig.headers(userId: userId),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to update status(${response.statusCode})");
    }
  }

  static Future<void> reopenTask({
    required int taskId,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse("$plannerEnpoint/tasks/$taskId/reopen"),
      headers: await ApiConfig.headers(userId: userId),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to reopen task (${response.statusCode})");
    }
  }

  static Future<List<int>> densifyPhase({
    required String planId,
    required int phaseId,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse("$plannerEnpoint/$planId/phases/$phaseId/densify"),
      headers: await ApiConfig.headers(userId: userId),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return List<int>.from(body['week_ids'] as List);
    }
    throw Exception("Failed to densify phase (${response.statusCode})");
  }
}
