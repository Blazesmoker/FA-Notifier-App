// lib/services/notification_service.dart
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../custom_drawer/drawer_user_controller.dart';
import '../enums/drawer_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../providers/NotificationNavigationProvider.dart';

/// Manages notification channels and displays notifications.
class NotificationService {

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  final GlobalKey<DrawerUserControllerState> drawerKey = GlobalKey<DrawerUserControllerState>();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();


  static const List<String> notificationTypes = [
    'submissions',
    'watches',
    'comments',
    'favorites',
    'journals',
    'notes',
    'activities',
  ];

  NotificationService._internal();

  /// Initializes the notification service and creates channels.
  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/fathemednotif');

    // iOS
    const DarwinInitializationSettings initializationSettingsDarwin =
    DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,

    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );


    if (!Platform.isAndroid) {
      await _requestIOSPermissions();
    }

    await _createNotificationChannels();
  }


  Future<void> _requestIOSPermissions() async {
    final implementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (implementation != null) {
      final result = await implementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('iOS plugin-based permission: $result');
    }
  }

  /// Creates notification channels based on user settings.
  Future<void> _createNotificationChannels() async {
    final prefs = await SharedPreferences.getInstance();

    for (String type in notificationTypes) {
      bool soundEnabled = false;
      bool vibrationEnabled = false;

      // Map notification type to sound and vibration settings
      switch (type) {
        case 'submissions':
          soundEnabled = prefs.getBool('sound_new_submissions_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_submissions_enabled') ?? true;
          break;
        case 'watches':
          soundEnabled = prefs.getBool('sound_new_watches_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_watches_enabled') ?? true;
          break;
        case 'comments':
          soundEnabled = prefs.getBool('sound_new_comments_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_comments_enabled') ?? true;
          break;
        case 'favorites':
          soundEnabled = prefs.getBool('sound_new_favorites_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_favorites_enabled') ?? true;
          break;
        case 'journals':
          soundEnabled = prefs.getBool('sound_new_journals_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_journals_enabled') ?? true;
          break;
        case 'notes':
          soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_notes_enabled') ?? true;
          break;
        case 'activities':
          soundEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
          vibrationEnabled =
              prefs.getBool('vibration_new_activities_enabled') ?? true;
          break;
        default:
          soundEnabled = true;
          vibrationEnabled = true;
      }

      // Define channel ID with both sound and vibration settings
      String channelId =
          '${type}_sound_${soundEnabled ? "on" : "off"}_vibration_${vibrationEnabled ? "on" : "off"}';


      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        '${_capitalize(type)} Notifications',
        description:
        'Notifications for $type with sound and vibration settings',
        importance: Importance.high,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        sound: soundEnabled
            ? null // default sound
            : RawResourceAndroidNotificationSound('silent'), // silent sound
      );


      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Handles notification tap events.
  void onDidReceiveNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    final context = navigatorKey.currentContext;

    if (context == null) {
      debugPrint("Navigator context is null. Cannot navigate right now.");
      return;
    }

    if (payload != null) {
      debugPrint("Notification tapped with payload: $payload");

      final navProvider = Provider.of<NotificationNavigationProvider>(
        context,
        listen: false,
      );

      if (payload.startsWith('note_')) {
        // Go to the Notes section
        navProvider.setTargetIndex(4);
      } else if (payload.startsWith('activity_')) {
        // Go to the "Activity/Notifications" section
        navProvider.setTargetIndex(3);
      }

      // Ensure the app navigates back to HomeScreen and updates UI
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Capitalizes the first letter of a string.
  String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

  /// Displays a notification.
  Future<void> showNotification(
      int id,
      String title,
      String body,
      String payload,
      String type,
      ) async {
    debugPrint(
        'NotificationService.showNotification called with id=$id, title=$title, type=$type');

    final prefs = await SharedPreferences.getInstance();
    bool soundEnabled = false;
    bool vibrationEnabled = false;

    // Determine which channel to use based on type and current settings
    switch (type) {
      case 'notes':
        soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
        vibrationEnabled =
            prefs.getBool('vibration_new_notes_enabled') ?? true;
        break;
      case 'activities':
        soundEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
        vibrationEnabled =
            prefs.getBool('vibration_new_activities_enabled') ?? true;
        break;

      default:
        soundEnabled = true;
        vibrationEnabled = true;
    }

    // Construct the channel ID
    String channelId =
        '${type}_sound_${soundEnabled ? "on" : "off"}_vibration_${vibrationEnabled ? "on" : "off"}';
    final icon = await getNotificationIconBasedOnPreference();
    // Android Notification Details
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      channelId,
      '${_capitalize(type)} Notifications',
      channelDescription: soundEnabled
          ? 'Notifications for $type with sound enabled'
          : 'Notifications for $type with sound disabled',
      importance: Importance.high,
      priority: Priority.high,
      icon: icon, // adaptive-aware icon
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );

    // iOS Notification Details
    final DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );

    debugPrint('flutterLocalNotificationsPlugin.show completed');
  }

  /// Updates notification channels based on updated user preferences.
  Future<void> updateNotificationChannels() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();


    if (androidPlugin != null) {
      for (String type in notificationTypes) {

        List<String> possibleChannelIds = [
          '${type}_sound_on_vibration_on',
          '${type}_sound_on_vibration_off',
          '${type}_sound_off_vibration_on',
          '${type}_sound_off_vibration_off',
        ];

        for (String channelId in possibleChannelIds) {
          await androidPlugin.deleteNotificationChannel(channelId);
        }
      }
    }

    // Recreate channels based on updated settings
    await _createNotificationChannels();
  }

  Future<String?> getNotificationIconBasedOnPreference() async {
    final prefs = await SharedPreferences.getInstance();

    // First it checks for the notifications‐specific toggle, if unset, fall back to the global one.
    final useAdaptiveNotify = prefs.getBool('useAdaptiveNotificationIcon')
        ?? prefs.getBool('useAdaptiveIcon')
        ?? false;

    return useAdaptiveNotify ? 'ic_stat_notify' : null;
  }

}