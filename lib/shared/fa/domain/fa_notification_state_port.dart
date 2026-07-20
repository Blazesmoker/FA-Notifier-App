import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

abstract interface class FaNotificationStatePort {
  bool get hasValidLatestCountsSnapshot;

  NotificationCounts get latestCounts;

  String? get errorMessage;

  void applyTopbarCounts(NotificationCounts counts);

  Future<void> fetchNotifications();
}
