// lib/providers/notification_settings_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class NotificationSettingsProvider with ChangeNotifier {

  bool _watchersEnabled = true;
  bool _journalsEnabled = true;
  bool _commentsEnabled = true;
  bool _favoritesEnabled = true;
  bool _shoutsEnabled = true;

  bool get watchersEnabled => _watchersEnabled;
  bool get journalsEnabled => _journalsEnabled;
  bool get commentsEnabled => _commentsEnabled;
  bool get favoritesEnabled => _favoritesEnabled;
  bool get shoutsEnabled => _shoutsEnabled;


  Future<void> setWatchersEnabled(bool value) async {
    _watchersEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_watchers_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setJournalsEnabled(bool value) async {
    _journalsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_journals_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setCommentsEnabled(bool value) async {
    _commentsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_comments_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setFavoritesEnabled(bool value) async {
    _favoritesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_favorites_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setShoutsEnabled(bool value) async {
    _shoutsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_shouts_enabled', value);
    await NotificationService().updateNotificationChannels();
  }


  bool _drawerSubmissionsEnabled = true;
  bool _drawerWatchesEnabled = true;
  bool _drawerCommentsEnabled = true;
  bool _drawerFavoritesEnabled = true;
  bool _drawerJournalsEnabled = true;
  bool _drawerNotesEnabled = true;

  bool get drawerSubmissionsEnabled => _drawerSubmissionsEnabled;
  bool get drawerWatchesEnabled => _drawerWatchesEnabled;
  bool get drawerCommentsEnabled => _drawerCommentsEnabled;
  bool get drawerFavoritesEnabled => _drawerFavoritesEnabled;
  bool get drawerJournalsEnabled => _drawerJournalsEnabled;
  bool get drawerNotesEnabled => _drawerNotesEnabled;

  NotificationSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();


    _watchersEnabled = prefs.getBool('notif_watchers_enabled') ?? true;
    _journalsEnabled = prefs.getBool('notif_journals_enabled') ?? true;
    _commentsEnabled = prefs.getBool('notif_comments_enabled') ?? true;
    _favoritesEnabled = prefs.getBool('notif_favorites_enabled') ?? true;
    _shoutsEnabled = prefs.getBool('notif_shouts_enabled') ?? true;


    _drawerSubmissionsEnabled =
        prefs.getBool('drawer_notif_submissions_enabled') ?? true;
    _drawerWatchesEnabled =
        prefs.getBool('drawer_notif_watches_enabled') ?? true;
    _drawerCommentsEnabled =
        prefs.getBool('drawer_notif_comments_enabled') ?? true;
    _drawerFavoritesEnabled =
        prefs.getBool('drawer_notif_favorites_enabled') ?? true;
    _drawerJournalsEnabled =
        prefs.getBool('drawer_notif_journals_enabled') ?? true;
    _drawerNotesEnabled =
        prefs.getBool('drawer_notif_notes_enabled') ?? true;


    _soundNewSubmissionsEnabled =
        prefs.getBool('sound_new_submissions_enabled') ?? true;
    _vibrationNewSubmissionsEnabled =
        prefs.getBool('vibration_new_submissions_enabled') ?? true;
    _soundNewWatchesEnabled =
        prefs.getBool('sound_new_watches_enabled') ?? true;
    _vibrationNewWatchesEnabled =
        prefs.getBool('vibration_new_watches_enabled') ?? true;
    _soundNewCommentsEnabled =
        prefs.getBool('sound_new_comments_enabled') ?? true;
    _vibrationNewCommentsEnabled =
        prefs.getBool('vibration_new_comments_enabled') ?? true;
    _soundNewFavoritesEnabled =
        prefs.getBool('sound_new_favorites_enabled') ?? true;
    _vibrationNewFavoritesEnabled =
        prefs.getBool('vibration_new_favorites_enabled') ?? true;
    _soundNewJournalsEnabled =
        prefs.getBool('sound_new_journals_enabled') ?? true;
    _vibrationNewJournalsEnabled =
        prefs.getBool('vibration_new_journals_enabled') ?? true;
    _soundNewNotesEnabled =
        prefs.getBool('sound_new_notes_enabled') ?? true;
    _vibrationNewNotesEnabled =
        prefs.getBool('vibration_new_notes_enabled') ?? true;


    _soundNewActivitiesEnabled =
        prefs.getBool('sound_new_activities_enabled') ?? true;
    _vibrationNewActivitiesEnabled =
        prefs.getBool('vibration_new_activities_enabled') ?? true;

    notifyListeners();
  }


  Future<void> setDrawerSubmissionsEnabled(bool value) async {
    _drawerSubmissionsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_submissions_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setDrawerWatchesEnabled(bool value) async {
    _drawerWatchesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_watches_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setDrawerCommentsEnabled(bool value) async {
    _drawerCommentsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_comments_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setDrawerFavoritesEnabled(bool value) async {
    _drawerFavoritesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_favorites_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setDrawerJournalsEnabled(bool value) async {
    _drawerJournalsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_journals_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setDrawerNotesEnabled(bool value) async {
    _drawerNotesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawer_notif_notes_enabled', value);
    await NotificationService().updateNotificationChannels();
  }


  bool _soundNewSubmissionsEnabled = true;
  bool _vibrationNewSubmissionsEnabled = true;
  bool _soundNewWatchesEnabled = true;
  bool _vibrationNewWatchesEnabled = true;
  bool _soundNewCommentsEnabled = true;
  bool _vibrationNewCommentsEnabled = true;
  bool _soundNewFavoritesEnabled = true;
  bool _vibrationNewFavoritesEnabled = true;
  bool _soundNewJournalsEnabled = true;
  bool _vibrationNewJournalsEnabled = true;
  bool _soundNewNotesEnabled = true;
  bool _vibrationNewNotesEnabled = true;


  bool _soundNewActivitiesEnabled = true;
  bool _vibrationNewActivitiesEnabled = true;

  // Getters
  bool get soundNewSubmissionsEnabled => _soundNewSubmissionsEnabled;
  bool get vibrationNewSubmissionsEnabled => _vibrationNewSubmissionsEnabled;
  bool get soundNewWatchesEnabled => _soundNewWatchesEnabled;
  bool get vibrationNewWatchesEnabled => _vibrationNewWatchesEnabled;
  bool get soundNewCommentsEnabled => _soundNewCommentsEnabled;
  bool get vibrationNewCommentsEnabled => _vibrationNewCommentsEnabled;
  bool get soundNewFavoritesEnabled => _soundNewFavoritesEnabled;
  bool get vibrationNewFavoritesEnabled => _vibrationNewFavoritesEnabled;
  bool get soundNewJournalsEnabled => _soundNewJournalsEnabled;
  bool get vibrationNewJournalsEnabled => _vibrationNewJournalsEnabled;
  bool get soundNewNotesEnabled => _soundNewNotesEnabled;
  bool get vibrationNewNotesEnabled => _vibrationNewNotesEnabled;


  bool get soundNewActivitiesEnabled => _soundNewActivitiesEnabled;
  bool get vibrationNewActivitiesEnabled => _vibrationNewActivitiesEnabled;


  Future<void> setSoundNewSubmissionsEnabled(bool value) async {
    _soundNewSubmissionsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_submissions_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewSubmissionsEnabled(bool value) async {
    _vibrationNewSubmissionsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_submissions_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setSoundNewWatchesEnabled(bool value) async {
    _soundNewWatchesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_watches_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewWatchesEnabled(bool value) async {
    _vibrationNewWatchesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_watches_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setSoundNewCommentsEnabled(bool value) async {
    _soundNewCommentsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_comments_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewCommentsEnabled(bool value) async {
    _vibrationNewCommentsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_comments_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setSoundNewFavoritesEnabled(bool value) async {
    _soundNewFavoritesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_favorites_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewFavoritesEnabled(bool value) async {
    _vibrationNewFavoritesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_favorites_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setSoundNewJournalsEnabled(bool value) async {
    _soundNewJournalsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_journals_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewJournalsEnabled(bool value) async {
    _vibrationNewJournalsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_journals_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setSoundNewNotesEnabled(bool value) async {
    _soundNewNotesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_notes_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewNotesEnabled(bool value) async {
    _vibrationNewNotesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_notes_enabled', value);
    await NotificationService().updateNotificationChannels();
  }


  Future<void> setSoundNewActivitiesEnabled(bool value) async {
    _soundNewActivitiesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_new_activities_enabled', value);
    await NotificationService().updateNotificationChannels();
  }

  Future<void> setVibrationNewActivitiesEnabled(bool value) async {
    _vibrationNewActivitiesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_new_activities_enabled', value);
    await NotificationService().updateNotificationChannels();
  }
}
