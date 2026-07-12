import 'package:FANotifier/shared/fa/domain/notification_counts.dart';
import 'package:FANotifier/shared/fa/domain/notifications.dart';

class FaNotificationsPageParserState {
  FaNotificationsPageParserState({
    this.linkUsername,
    this.displayName,
  });

  String? linkUsername;
  String? displayName;
  NotificationCounts? latestCounts;
  Notifications? latestTopBarNotifications;
  String? currentUsername;
  bool hasValidLatestCountsSnapshot = false;
  bool hasParsedCurrentUsername = false;
}
