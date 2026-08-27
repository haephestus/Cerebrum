import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'package:cerebrum/services/user_session.dart';

/// Thrown when the backend returns 409 for POST /user/account -- an account
/// already exists with this email (email is UNIQUE in the daemon's users table).
class AccountAlreadyExistsException implements Exception {
  final String email;
  AccountAlreadyExistsException(this.email);

  @override
  String toString() => 'Account already exists: $email';
}

/// Thrown when the backend returns 401 for POST /user/login -- wrong email or
/// password.
class InvalidCredentialsException implements Exception {
  @override
  String toString() => 'Invalid email or password';
}

class UserApi {
  static String get baseUrl => ApiConfig.baseUrl;
  static String get userEndpoint => "$baseUrl/user";

  /// Create a credential-backed account. Email and password are both required
  /// now (the daemon enforces UNIQUE email + a bcrypt password, min length 8).
  /// Does NOT establish a session on its own — the daemon's create response
  /// carries no token; call [login] afterwards (or use [signUp]).
  static Future<Map<String, dynamic>> createAccount(
    String name,
    String email,
    String password, {
    Map<String, dynamic>? settings,
  }) async {
    final response = await http.post(
      Uri.parse("$userEndpoint/account"),
      headers: await ApiConfig.headers(),
      body: jsonEncode({
        "name": name,
        "email": email,
        "password": password,
        if (settings != null) "settings": settings,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 409) {
      throw AccountAlreadyExistsException(email);
    }
    throw Exception(
      "Failed to create user: ${response.statusCode} ${response.body}",
    );
  }

  /// Log in with email + password. On success the daemon returns a bearer
  /// token; we persist it (securely) along with the account, so subsequent
  /// requests authenticate via [ApiConfig.headers].
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$userEndpoint/login"),
      headers: await ApiConfig.headers(),
      body: jsonEncode({"email": email, "password": password}),
    );

    if (response.statusCode == 401) {
      throw InvalidCredentialsException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        "Failed to log in: ${response.statusCode} ${response.body}",
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final id = data['id'] as String?;
    final name = data['name'] as String?;
    final token = data['token'] as String?;
    if (id == null || name == null || token == null) {
      throw Exception(
        "login response missing 'id'/'name'/'token': ${response.body}",
      );
    }

    await UserSession.saveSession(
      id: id,
      username: name,
      token: token,
      email: data['email'] as String?,
    );
    return data;
  }

  /// Convenience for the signup flow: create the account, then log in to
  /// obtain and store the token.
  static Future<Map<String, dynamic>> signUp(
    String name,
    String email,
    String password, {
    Map<String, dynamic>? settings,
  }) async {
    await createAccount(name, email, password, settings: settings);
    return login(email, password);
  }

  /// Permanently deletes the CALLING user's account server-side (notes,
  /// engrams, attempts, mastery -- everything). Identity comes from the auth
  /// headers now, so there's no id in the path. Does NOT clear local session
  /// state -- call UserSession.clear() alongside this.
  static Future<void> deleteAccount() async {
    final response = await http.delete(
      Uri.parse("$userEndpoint/account"),
      headers: await ApiConfig.headers(),
    );

    if (response.statusCode == 200) return;
    if (response.statusCode == 404) return; // already gone -- treat as success

    throw Exception(
      "Failed to delete user: ${response.statusCode} ${response.body}",
    );
  }

  /// Fetches the current user from the backend using the auth headers.
  /// Useful on startup to confirm the saved session is still valid (e.g. the
  /// account wasn't deleted server-side, or the token hasn't expired).
  static Future<Map<String, dynamic>?> fetchCurrentUser() async {
    final response = await http.get(
      Uri.parse("$userEndpoint/account"),
      headers: await ApiConfig.headers(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 401 || response.statusCode == 404) {
      // Token invalid/expired or the account is gone -- clear the stale session.
      await UserSession.clear();
      return null;
    }
    throw Exception(
      "Failed to fetch current user: ${response.statusCode} ${response.body}",
    );
  }
}
