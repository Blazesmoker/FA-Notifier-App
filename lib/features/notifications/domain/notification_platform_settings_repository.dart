import 'package:fanotifier/features/notifications/domain/notification_permission_state.dart';

abstract interface class NotificationPlatformSettingsRepository {
  Future<bool> loadUseAdaptiveNotificationIcon();

  Future<void> setUseAdaptiveNotificationIcon(bool value);

  Future<void> refreshNotificationChannels();

  Future<NotificationPermissionState> getNotificationPermissionState();

  Future<bool> openNotificationSettings();
}
