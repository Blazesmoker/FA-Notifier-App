import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';

class FaNotificationsPageSnapshot {
  FaNotificationsPageSnapshot({
    required Map<String, int> messageBarCounts,
    required this.latestCounts,
    required this.latestTopBarNotifications,
    required this.currentUsername,
    required List<NotificationSection> sections,
    required this.linkUsername,
    required this.displayName,
  })  : messageBarCounts = Map.unmodifiable(messageBarCounts),
        sections = List.unmodifiable(sections);

  final Map<String, int> messageBarCounts;
  final NotificationCounts latestCounts;
  final Notifications latestTopBarNotifications;
  final String currentUsername;
  final List<NotificationSection> sections;
  final String? linkUsername;
  final String? displayName;
}
