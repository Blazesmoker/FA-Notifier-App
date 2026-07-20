import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/notifications/domain/notification_setting.dart';
import 'package:fanotifier/features/notifications/domain/notification_settings_repository.dart';

class SharedPreferencesNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const SharedPreferencesNotificationSettingsRepository();

  static const Map<NotificationSetting, String> _keys = {
    NotificationSetting.watchers: 'notif_watchers_enabled',
    NotificationSetting.journals: 'notif_journals_enabled',
    NotificationSetting.comments: 'notif_comments_enabled',
    NotificationSetting.favorites: 'notif_favorites_enabled',
    NotificationSetting.shouts: 'notif_shouts_enabled',
    NotificationSetting.drawerSubmissions:
        'drawer_notif_submissions_enabled',
    NotificationSetting.drawerWatches: 'drawer_notif_watches_enabled',
    NotificationSetting.drawerComments: 'drawer_notif_comments_enabled',
    NotificationSetting.drawerFavorites: 'drawer_notif_favorites_enabled',
    NotificationSetting.drawerJournals: 'drawer_notif_journals_enabled',
    NotificationSetting.drawerNotes: 'drawer_notif_notes_enabled',
    NotificationSetting.soundNewSubmissions:
        'sound_new_submissions_enabled',
    NotificationSetting.vibrationNewSubmissions:
        'vibration_new_submissions_enabled',
    NotificationSetting.soundNewWatches: 'sound_new_watches_enabled',
    NotificationSetting.vibrationNewWatches:
        'vibration_new_watches_enabled',
    NotificationSetting.soundNewComments: 'sound_new_comments_enabled',
    NotificationSetting.vibrationNewComments:
        'vibration_new_comments_enabled',
    NotificationSetting.soundNewFavorites: 'sound_new_favorites_enabled',
    NotificationSetting.vibrationNewFavorites:
        'vibration_new_favorites_enabled',
    NotificationSetting.soundNewJournals: 'sound_new_journals_enabled',
    NotificationSetting.vibrationNewJournals:
        'vibration_new_journals_enabled',
    NotificationSetting.soundNewNotes: 'sound_new_notes_enabled',
    NotificationSetting.vibrationNewNotes: 'vibration_new_notes_enabled',
    NotificationSetting.soundNewActivities: 'sound_new_activities_enabled',
    NotificationSetting.vibrationNewActivities:
        'vibration_new_activities_enabled',
  };

  @override
  Future<Map<NotificationSetting, bool>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      for (final entry in _keys.entries)
        entry.key: preferences.getBool(entry.value) ?? true,
    };
  }

  @override
  Future<void> save(NotificationSetting setting, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_keys[setting]!, value);
  }
}
