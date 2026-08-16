import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/notifications/domain/notification_setting.dart';
import 'package:fanotifier/features/notifications/domain/notification_settings_repository.dart';

class NotificationSettingsProvider with ChangeNotifier {
  NotificationSettingsProvider({
    required this._repository,
    required this._onSettingsChanged,
  }) {
    _loadSettings();
  }

  final NotificationSettingsRepository _repository;
  final Future<void> Function() _onSettingsChanged;
  final Map<NotificationSetting, bool> _settings = {
    for (final setting in NotificationSetting.values) setting: true,
  };

  bool get watchersEnabled => _value(NotificationSetting.watchers);
  bool get journalsEnabled => _value(NotificationSetting.journals);
  bool get commentsEnabled => _value(NotificationSetting.comments);
  bool get favoritesEnabled => _value(NotificationSetting.favorites);
  bool get shoutsEnabled => _value(NotificationSetting.shouts);
  bool get drawerSubmissionsEnabled =>
      _value(NotificationSetting.drawerSubmissions);
  bool get drawerWatchesEnabled => _value(NotificationSetting.drawerWatches);
  bool get drawerCommentsEnabled =>
      _value(NotificationSetting.drawerComments);
  bool get drawerFavoritesEnabled =>
      _value(NotificationSetting.drawerFavorites);
  bool get drawerJournalsEnabled =>
      _value(NotificationSetting.drawerJournals);
  bool get drawerNotesEnabled => _value(NotificationSetting.drawerNotes);
  bool get soundNewSubmissionsEnabled =>
      _value(NotificationSetting.soundNewSubmissions);
  bool get vibrationNewSubmissionsEnabled =>
      _value(NotificationSetting.vibrationNewSubmissions);
  bool get soundNewWatchesEnabled =>
      _value(NotificationSetting.soundNewWatches);
  bool get vibrationNewWatchesEnabled =>
      _value(NotificationSetting.vibrationNewWatches);
  bool get soundNewCommentsEnabled =>
      _value(NotificationSetting.soundNewComments);
  bool get vibrationNewCommentsEnabled =>
      _value(NotificationSetting.vibrationNewComments);
  bool get soundNewFavoritesEnabled =>
      _value(NotificationSetting.soundNewFavorites);
  bool get vibrationNewFavoritesEnabled =>
      _value(NotificationSetting.vibrationNewFavorites);
  bool get soundNewJournalsEnabled =>
      _value(NotificationSetting.soundNewJournals);
  bool get vibrationNewJournalsEnabled =>
      _value(NotificationSetting.vibrationNewJournals);
  bool get soundNewNotesEnabled =>
      _value(NotificationSetting.soundNewNotes);
  bool get vibrationNewNotesEnabled =>
      _value(NotificationSetting.vibrationNewNotes);
  bool get soundNewActivitiesEnabled =>
      _value(NotificationSetting.soundNewActivities);
  bool get vibrationNewActivitiesEnabled =>
      _value(NotificationSetting.vibrationNewActivities);

  Future<void> setWatchersEnabled(bool value) =>
      _set(NotificationSetting.watchers, value);
  Future<void> setJournalsEnabled(bool value) =>
      _set(NotificationSetting.journals, value);
  Future<void> setCommentsEnabled(bool value) =>
      _set(NotificationSetting.comments, value);
  Future<void> setFavoritesEnabled(bool value) =>
      _set(NotificationSetting.favorites, value);
  Future<void> setShoutsEnabled(bool value) =>
      _set(NotificationSetting.shouts, value);
  Future<void> setDrawerSubmissionsEnabled(bool value) =>
      _set(NotificationSetting.drawerSubmissions, value);
  Future<void> setDrawerWatchesEnabled(bool value) =>
      _set(NotificationSetting.drawerWatches, value);
  Future<void> setDrawerCommentsEnabled(bool value) =>
      _set(NotificationSetting.drawerComments, value);
  Future<void> setDrawerFavoritesEnabled(bool value) =>
      _set(NotificationSetting.drawerFavorites, value);
  Future<void> setDrawerJournalsEnabled(bool value) =>
      _set(NotificationSetting.drawerJournals, value);
  Future<void> setDrawerNotesEnabled(bool value) =>
      _set(NotificationSetting.drawerNotes, value);
  Future<void> setSoundNewSubmissionsEnabled(bool value) =>
      _set(NotificationSetting.soundNewSubmissions, value);
  Future<void> setVibrationNewSubmissionsEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewSubmissions, value);
  Future<void> setSoundNewWatchesEnabled(bool value) =>
      _set(NotificationSetting.soundNewWatches, value);
  Future<void> setVibrationNewWatchesEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewWatches, value);
  Future<void> setSoundNewCommentsEnabled(bool value) =>
      _set(NotificationSetting.soundNewComments, value);
  Future<void> setVibrationNewCommentsEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewComments, value);
  Future<void> setSoundNewFavoritesEnabled(bool value) =>
      _set(NotificationSetting.soundNewFavorites, value);
  Future<void> setVibrationNewFavoritesEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewFavorites, value);
  Future<void> setSoundNewJournalsEnabled(bool value) =>
      _set(NotificationSetting.soundNewJournals, value);
  Future<void> setVibrationNewJournalsEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewJournals, value);
  Future<void> setSoundNewNotesEnabled(bool value) =>
      _set(NotificationSetting.soundNewNotes, value);
  Future<void> setVibrationNewNotesEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewNotes, value);
  Future<void> setSoundNewActivitiesEnabled(bool value) =>
      _set(NotificationSetting.soundNewActivities, value);
  Future<void> setVibrationNewActivitiesEnabled(bool value) =>
      _set(NotificationSetting.vibrationNewActivities, value);

  bool _value(NotificationSetting setting) => _settings[setting] ?? true;

  Future<void> _loadSettings() async {
    _settings.addAll(await _repository.load());
    notifyListeners();
  }

  Future<void> _set(NotificationSetting setting, bool value) async {
    _settings[setting] = value;
    notifyListeners();
    await _repository.save(setting, value);
    await _onSettingsChanged();
  }
}
