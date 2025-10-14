// lib/services/notes_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../custom_drawer/drawer_user_controller.dart';

// Import the main notifications service with an alias to avoid naming clashes
import 'notification_service.dart' as core;

/// Thin helper for sending "notes" notifications.
/// All initialization, tap handling, channels, etc. are owned by core.NotificationService.
class NotesNotificationService {
  static final NotesNotificationService _instance =
  NotesNotificationService._internal();
  factory NotesNotificationService() => _instance;
  NotesNotificationService._internal();

  final GlobalKey<DrawerUserControllerState> drawerKey =
  GlobalKey<DrawerUserControllerState>();

  /// Optional helper if you still read this preference elsewhere.
  Future<String?> getNotificationIconBasedOnPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final useAdaptiveNotify =
        prefs.getBool('useAdaptiveNotificationIcon') ??
            prefs.getBool('useAdaptiveIcon') ??
            false;
    return useAdaptiveNotify ? 'ic_stat_notify' : null;
  }

  /// Show a Notes notification by delegating to the main service.
  /// No plugin initialization or tap handling here.
  Future<void> showNotesNotification(
      int id,
      String title,
      String body,
      String payload,
      ) async {
    // Reuse the core service (this sets the proper channel & icon internally).
    await core.NotificationService().showNotification(
      id,
      title,
      body,
      payload,
      'notes',
    );
  }
}
