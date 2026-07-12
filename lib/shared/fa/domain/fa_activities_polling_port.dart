import 'package:FANotifier/shared/fa/domain/fa_notification_state_port.dart';
import 'package:FANotifier/shared/fa/domain/notification_counts.dart';

abstract interface class FaActivitiesPollingPort {
  void start({required FaNotificationStatePort faNotificationService});

  void stop();

  void resetSchedule();

  void setNotesScreenVisible(bool visible);

  void setSubmissionsScreenVisible(bool visible);

  void setNotificationsScreenVisible(
    bool visible, {
    String? activeSectionTitle,
  });

  void setNotificationsScreenActiveSection(String? sectionTitle);

  Future<void> triggerNow({
    required bool resetTimer,
    required String source,
  });

  Future<void> handleExternalCounts({
    required NotificationCounts currentCounts,
    required bool resetTimer,
    required String source,
  });
}
