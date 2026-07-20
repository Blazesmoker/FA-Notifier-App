import 'package:fanotifier/features/notifications/presentation/notification_settings_provider.dart';

class NotificationCounterSettingsController {
  const NotificationCounterSettingsController(this._settings);

  final NotificationSettingsProvider _settings;

  bool get watchersEnabled => _settings.watchersEnabled;
  bool get journalsEnabled => _settings.journalsEnabled;
  bool get commentsEnabled => _settings.commentsEnabled;
  bool get favoritesEnabled => _settings.favoritesEnabled;
  bool get shoutsEnabled => _settings.shoutsEnabled;

  Future<void> setWatchersEnabled(bool value) {
    return _settings.setWatchersEnabled(value);
  }

  Future<void> setJournalsEnabled(bool value) {
    return _settings.setJournalsEnabled(value);
  }

  Future<void> setCommentsEnabled(bool value) {
    return _settings.setCommentsEnabled(value);
  }

  Future<void> setFavoritesEnabled(bool value) {
    return _settings.setFavoritesEnabled(value);
  }

  Future<void> setShoutsEnabled(bool value) {
    return _settings.setShoutsEnabled(value);
  }
}
