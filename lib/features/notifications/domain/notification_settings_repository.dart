import 'package:fanotifier/features/notifications/domain/notification_setting.dart';

abstract class NotificationSettingsRepository {
  Future<Map<NotificationSetting, bool>> load();

  Future<void> save(NotificationSetting setting, bool value);
}
