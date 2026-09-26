import 'package:flutter/foundation.dart';

/// A place to send a user-facing notification. Kept as an interface so a real
/// OS-level notifier (e.g. `flutter_local_notifications`) can be dropped in
/// later without touching callers — assign [Notifications.sink] once at startup.
abstract class NotificationSink {
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  });
}

/// Default no-op sink: just logs. Replace with a real plugin-backed sink when
/// you wire actual push/local notifications.
class LoggingNotificationSink implements NotificationSink {
  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint(
      '[Notification] $title — $body${payload == null ? '' : ' ($payload)'}',
    );
  }
}

/// App-wide notification + badge hub (scaffolding).
///
/// - [badgeCount] is a [ValueNotifier] the UI watches to render an unread badge
///   (e.g. on the Learning Center tab). Drive it from a source of truth like
///   `EngramAttemptStore.unseenGradedCount()` via [refreshBadge].
/// - [notify] sends a notification through the pluggable [sink].
///
/// Nothing here depends on a specific plugin, so it compiles and runs today
/// (logging), and becomes real by swapping [sink] + wiring [refreshBadge] to a
/// platform badge API.
class Notifications {
  Notifications._();

  /// Unread/new-result count for a badge. Watch with a [ValueListenableBuilder].
  static final ValueNotifier<int> badgeCount = ValueNotifier<int>(0);

  /// Swap this for a real notifier at startup; defaults to logging.
  static NotificationSink sink = LoggingNotificationSink();

  static Future<void> notify({
    required String title,
    required String body,
    String? payload,
  }) => sink.show(title: title, body: body, payload: payload);

  /// Set the badge from an authoritative count (e.g. unseen graded attempts).
  static Future<void> setBadge(int count) async {
    badgeCount.value = count;
    // A real impl would also set the OS app-icon badge here.
  }

  /// Refresh the badge from a count supplier (kept generic to avoid a hard
  /// dependency on any one store).
  static Future<void> refreshBadge(Future<int> Function() count) async {
    await setBadge(await count());
  }
}
