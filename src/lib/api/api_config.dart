import 'package:shared_preferences/shared_preferences.dart';
import 'package:cerebrum/services/user_session.dart';

/// Which daemon we're talking to.
///  - local: your own machine / a tunnel. The daemon gates transport with a
///    shared X-Daemon-Key and accepts X-User-Id for identity.
///  - cloud: a hosted, multi-tenant daemon (e.g. Leapcell). No shared key;
///    identity is the per-user bearer token only.
enum DeploymentMode { local, cloud }

class ApiConfig {
  static const _keyMode = 'cerebrum_deployment_mode';
  static const _keyLocalUrl = 'cerebrum_local_url';
  static const _keyCloudUrl = 'cerebrum_cloud_url';

  static const _defaultLocalUrl = 'http://localhost:8000';
  static const _defaultCloudUrl = ''; // set to your Leapcell URL in settings

  /// Current base URL. Kept as a plain synchronous field so the per-service
  /// `get baseUrl => ApiConfig.baseUrl` accessors stay simple; it's hydrated
  /// from storage by [init] at startup and updated by [setMode]/[setBaseUrl].
  static String baseUrl = _defaultLocalUrl;
  static DeploymentMode mode = DeploymentMode.local;

  /// Call once at app startup (before the first request) to load the saved
  /// mode + URLs into [baseUrl].
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    mode = prefs.getString(_keyMode) == 'cloud'
        ? DeploymentMode.cloud
        : DeploymentMode.local;
    baseUrl = _urlFor(prefs, mode);
  }

  static String _urlFor(SharedPreferences prefs, DeploymentMode m) {
    if (m == DeploymentMode.cloud) {
      return prefs.getString(_keyCloudUrl) ?? _defaultCloudUrl;
    }
    return prefs.getString(_keyLocalUrl) ?? _defaultLocalUrl;
  }

  /// The stored (or default) URL for a mode, for display in settings.
  static Future<String> urlFor(DeploymentMode m) async {
    final prefs = await SharedPreferences.getInstance();
    return _urlFor(prefs, m);
  }

  static Future<void> setMode(DeploymentMode m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, m == DeploymentMode.cloud ? 'cloud' : 'local');
    mode = m;
    baseUrl = _urlFor(prefs, m);
  }

  static Future<void> setBaseUrl(DeploymentMode m, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      m == DeploymentMode.cloud ? _keyCloudUrl : _keyLocalUrl,
      url,
    );
    if (m == mode) baseUrl = url;
  }

  /// Auth headers for a daemon request. We attach every credential we hold and
  /// let the daemon use what its mode needs: cloud reads the bearer token;
  /// local reads X-Daemon-Key + X-User-Id. Sending all three is harmless and
  /// means the client doesn't have to branch on mode per request.
  static Future<Map<String, String>> headers({
    bool json = true,
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final daemonKey = await UserSession.getDaemonKey();
    final token = await UserSession.getToken();
    final effectiveUserId = userId ?? prefs.getString('cerebrum_user_id');

    return {
      if (json) 'Content-Type': 'application/json',
      if (daemonKey != null) 'X-Daemon-Key': daemonKey,
      if (token != null) 'Authorization': 'Bearer $token',
      if (effectiveUserId != null) 'X-User-Id': effectiveUserId,
    };
  }
}
