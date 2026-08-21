# real-notifications

> Replace scaffolding with actual OS notifications and app-icon badge.

## Status
CANDIDATE — Phase 2

## Goals
- OS-native notifications when a grade lands
- App-icon badge shows unseen graded count
- Notification tap opens the relevant engram

## Scope
- **In:** Replace LoggingNotificationSink with real plugin, wire OS app-icon badge, surface badgeCount on Learning Center tab
- **Out:** Push notifications (no cloud), notification groups

## Dependencies
- `notifications.dart` (current scaffolding)
- `EngramSyncService` (fires notification on grade)
- OS notification plugin (TBD)

## Schedule
| Phase | Work |
|-------|------|
| Phase 2 | Real notification plugin + badge wiring |

## Notes
- Current: `LoggingNotificationSink` + `Notifications.badgeCount` ValueNotifier
- Badge already refreshes on app start and after grade lands
- Just needs the real plugin swap
