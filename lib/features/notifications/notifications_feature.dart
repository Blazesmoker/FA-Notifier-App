import 'package:FANotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:FANotifier/features/notifications/data/fa_notifications_repository_impl.dart';
import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:FANotifier/features/notifications/data/notification_settings_service.dart';
import 'package:FANotifier/features/notifications/data/notification_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/pending_navigation_store.dart';
import 'package:FANotifier/features/notifications/data/shared_preferences_notification_settings_repository.dart';
import 'package:FANotifier/features/notifications/domain/notification_refresh_port.dart';
import 'package:FANotifier/features/notifications/domain/pending_navigation_repository.dart';
import 'package:FANotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/presentation/notification_settings_provider.dart';
import 'package:FANotifier/features/notifications/domain/notification_platform_settings_repository.dart';

class NotificationsFeature {
  const NotificationsFeature._();

  static NotificationSettingsProvider createSettingsProvider() {
    return NotificationSettingsProvider(
      repository: const SharedPreferencesNotificationSettingsRepository(),
      onSettingsChanged: NotificationService().updateNotificationChannels,
    );
  }

  static FANotificationService createNotificationService() {
    return FANotificationService(
      repository: FaNotificationsRepositoryImpl(),
    );
  }

  static NotificationRefreshPort get refreshPort =>
      NotificationRefreshService();

  static LocalNotificationGateway get localNotificationGateway =>
      NotificationService();

  static PendingNavigationRepository createPendingNavigationRepository() {
    return const PendingNavigationStore();
  }

  static NotificationPlatformSettingsRepository
      createPlatformSettingsRepository() {
    return NotificationSettingsService();
  }
}
