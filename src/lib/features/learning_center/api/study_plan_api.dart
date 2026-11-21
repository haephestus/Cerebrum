import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../api/api_config.dart';

class StudyPlanApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get studyPlanEndpoint => "$baseUrl/study_plan";

  /// GET /study_plan/user/active -- plans with status == 'active' for this user.
  /// NOTE: there's currently no backend route for the user's FULL plan
  /// history (draft/completed/archived too) -- only this active-only
  /// fetcher exists (StudyPlanRegisterInator.fetch_active_plans_inator).
  /// If you want a "past plans" section, that needs a new route + a
  /// registry method that doesn't filter on status='active'.
  static Future<List<Map<String, dynamic>>> getActivePlans({
    required String userId,
  }) async {
    final uri = Uri.parse("$studyPlanEndpoint/user/active");
    final response = await http.get(
      uri,
      headers: await ApiConfig.headers(userId: userId),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['plans'] as List);
    }
    throw Exception("Failed to fetch active plans: ${response.statusCode}");
  }

  /// GET /study_plan/{plan_id} -- full raw_plan_json for one plan.
  static Future<Map<String, dynamic>?> getPlan(String planId) async {
    final response = await http.get(
      Uri.parse("$studyPlanEndpoint/$planId"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) {
      final body = response.body;
      if (body.isEmpty || body == 'null') return null;
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) return null;
    throw Exception("Failed to fetch plan: ${response.statusCode}");
  }

  static Future<Map<String, dynamic>> getIncompletePhases(String planId) async {
    final response = await http.get(
      Uri.parse("$studyPlanEndpoint/$planId/phases/incomplete"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      "Failed to fetch incomplete phases: ${response.statusCode}",
    );
  }

  static Future<Map<String, dynamic>> getUnachievedMetrics(
    String planId,
  ) async {
    final response = await http.get(
      Uri.parse("$studyPlanEndpoint/$planId/metrics/unachieved"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      "Failed to fetch unachieved metrics: ${response.statusCode}",
    );
  }

  static Future<void> completePhase(String planId, int phaseId) async {
    final response = await http.post(
      Uri.parse("$studyPlanEndpoint/$planId/phases/$phaseId/complete"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to complete phase: ${response.statusCode}");
    }
  }

  static Future<void> achieveMetric(int metricRowId) async {
    final response = await http.post(
      Uri.parse("$studyPlanEndpoint/metrics/$metricRowId/achieve"),
      headers: await ApiConfig.headers(json: false),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to mark metric achieved: ${response.statusCode}");
    }
  }

  /// POST /study_plan/generate -- kicks off background generation, returns
  /// immediately with status: "pending". Caller should poll getActivePlans
  /// or getPlan afterwards; there's no push/webhook for completion yet.
  static Future<void> requestPlan({
    required String userId,
    required Map<String, dynamic> userProfile,
    required String targetRole,
    String? context,
    String? historicalPlanId,
  }) async {
    final response = await http.post(
      Uri.parse("$studyPlanEndpoint/generate"),
      headers: await ApiConfig.headers(userId: userId),
      body: jsonEncode({
        "user_profile": userProfile,
        "target_role": targetRole,
        if (context != null) "context": context,
        if (historicalPlanId != null) "historical_plan_id": historicalPlanId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        "Failed to request plan generation: ${response.statusCode}",
      );
    }
  }
}
