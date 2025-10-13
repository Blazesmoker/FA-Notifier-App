// lib/services/notification_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../custom_drawer/drawer_user_controller.dart';
import '../enums/drawer_index.dart';
import '../main.dart';
import '../providers/NotificationNavigationProvider.dart';
import 'notes_refresh_service.dart';
import 'notification_refresh_service.dart';

/// Manages notification channels, shows notifications, and handles taps.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final GlobalKey<DrawerUserControllerState> drawerKey = GlobalKey<DrawerUserControllerState>();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static const List<String> notificationTypes = [
    'submissions', 'watches', 'comments', 'favorites', 'journals', 'notes', 'activities',
  ];

  // iOS <-> Dart bridge: receives taps forwarded by AppDelegate
  static const MethodChannel _iosChannel = MethodChannel('app.notifications');

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/fathemednotif');

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

    // 🔗 Handle taps routed by native AppDelegate (foreground/background/cold)
    _iosChannel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped') {
        final Map<String, dynamic> map = Map<String, dynamic>.from(call.arguments as Map);
        final String? payload = _extractPayloadFromNative(map);
        if (payload != null) {
          await _handleTapPayload(payload, source: 'iosChannel');
        } else {
          // Heuristic fallback: route by "type" in userInfo
          final userInfo = (map['userInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
          if (userInfo['type'] == 'notes') {
            await _handleTapPayload('note_native', source: 'iosChannel');
          } else if (userInfo['type'] == 'activities') {
            await _handleTapPayload('activity_native', source: 'iosChannel');
          }
        }
      }
    });

    // Tell iOS native that Dart is ready to receive any pending tap
    try { await _iosChannel.invokeMethod('notifications.ready'); } catch (_) {}

    // Cold start from plugin path (Android/iOS)
    final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if ((details?.didNotificationLaunchApp ?? false) && details?.notificationResponse != null) {
      final p = details!.notificationResponse!.payload;
      if (p != null && p.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_navigation', p);
      }
    }
  }

  // ========= iOS permissions =========
  Future<void> _requestIOSPermissions() async {
    final implementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (implementation != null) {
      final result = await implementation.requestPermissions(
        alert: true, badge: true, sound: true,
      );
      debugPrint('iOS plugin-based permission: $result');
    }
  }

  // ========= Channels =========
  Future<void> _createNotificationChannels() async {
    final prefs = await SharedPreferences.getInstance();

    for (String type in notificationTypes) {
      bool soundEnabled = false;
      bool vibrationEnabled = false;

      switch (type) {
        case 'submissions':
          soundEnabled = prefs.getBool('sound_new_submissions_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_submissions_enabled') ?? true;
          break;
        case 'watches':
          soundEnabled = prefs.getBool('sound_new_watches_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_watches_enabled') ?? true;
          break;
        case 'comments':
          soundEnabled = prefs.getBool('sound_new_comments_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_comments_enabled') ?? true;
          break;
        case 'favorites':
          soundEnabled = prefs.getBool('sound_new_favorites_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_favorites_enabled') ?? true;
          break;
        case 'journals':
          soundEnabled = prefs.getBool('sound_new_journals_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_journals_enabled') ?? true;
          break;
        case 'notes':
          soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_notes_enabled') ?? true;
          break;
        case 'activities':
          soundEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
          vibrationEnabled = prefs.getBool('vibration_new_activities_enabled') ?? true;
          break;
        default:
          soundEnabled = true;
          vibrationEnabled = true;
      }

      final String channelId =
          '${type}_sound_${soundEnabled ? "on" : "off"}_vibration_${vibrationEnabled ? "on" : "off"}';

      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        '${_capitalize(type)} Notifications',
        description: 'Notifications for $type with sound and vibration settings',
        importance: Importance.high,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        sound: soundEnabled ? null : const RawResourceAndroidNotificationSound('silent'),
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  // ========= Taps (plugin path) =========
  Future<void> onDidReceiveNotificationResponse(NotificationResponse response) async {
    final String? payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    await _handleTapPayload(payload, source: 'plugin');
  }

  // ========= Shared tap handler (updates index + refresh) =========
  Future<void> _handleTapPayload(String payload, {required String source}) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_navigation', payload);
      return;
    }

    // Persist once so HomeScreen can also react if needed
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_navigation', payload);

    final navProvider = Provider.of<NotificationNavigationProvider>(context, listen: false);

    if (payload.startsWith('note_') || payload.contains("DrawerIndex.Notes")) {
      navProvider.setTargetIndex(4);                // Notes tab
      NotesRefreshService().triggerRefresh();       // 🔄 refresh Notes
    } else if (payload.startsWith('activity_') || payload.contains("DrawerIndex.Notifications")) {
      navProvider.setTargetIndex(3);                // Notifications tab
      NotificationRefreshService().triggerRefresh();// 🔄 refresh Notifications
    } else {
      // default to notifications if unknown
      navProvider.setTargetIndex(3);
      NotificationRefreshService().triggerRefresh();
    }

    // Return to root if needed
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // For iOS native dictionary -> payload string
  String? _extractPayloadFromNative(Map<String, dynamic> native) {
    if (native['payload'] is String && (native['payload'] as String).isNotEmpty) {
      return native['payload'] as String;
    }
    final userInfo = (native['userInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (userInfo['payload'] is String) return userInfo['payload'] as String;
    if (userInfo['route'] == '/notes') return 'note_native';
    if (userInfo['route'] == '/activities') return 'activity_native';
    return null;
  }

  // ========= Utility =========
  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> showNotification(
      int id,
      String title,
      String body,
      String payload,
      String type,
      ) async {
    debugPrint('NotificationService.showNotification id=$id title=$title type=$type');

    final prefs = await SharedPreferences.getInstance();
    bool soundEnabled = true, vibrationEnabled = true;

    switch (type) {
      case 'notes':
        soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
        vibrationEnabled = prefs.getBool('vibration_new_notes_enabled') ?? true;
        break;
      case 'activities':
        soundEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
        vibrationEnabled = prefs.getBool('vibration_new_activities_enabled') ?? true;
        break;
      default:
        soundEnabled = true; vibrationEnabled = true;
    }

    final channelId =
        '${type}_sound_${soundEnabled ? "on" : "off"}_vibration_${vibrationEnabled ? "on" : "off"}';

    final icon = await getNotificationIconBasedOnPreference();

    final android = AndroidNotificationDetails(
      channelId,
      '${_capitalize(type)} Notifications',
      channelDescription: soundEnabled
          ? 'Notifications for $type with sound enabled'
          : 'Notifications for $type with sound disabled',
      importance: Importance.high,
      priority: Priority.high,
      icon: icon,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );

    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      attachments: null,
      interruptionLevel: InterruptionLevel.active,
    );

    final details = NotificationDetails(android: android, iOS: ios);

    await flutterLocalNotificationsPlugin.show(
      id, title, body, details,
      payload: payload,
    );

    debugPrint('flutterLocalNotificationsPlugin.show completed');
  }

  Future<void> updateNotificationChannels() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (String type in notificationTypes) {
        for (final channelId in <String>[
          '${type}_sound_on_vibration_on',
          '${type}_sound_on_vibration_off',
          '${type}_sound_off_vibration_on',
          '${type}_sound_off_vibration_off',
        ]) {
          await androidPlugin.deleteNotificationChannel(channelId);
        }
      }
    }
    await _createNotificationChannels();
  }

  Future<String?> getNotificationIconBasedOnPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final useAdaptiveNotify = prefs.getBool('useAdaptiveNotificationIcon')
        ?? prefs.getBool('useAdaptiveIcon')
        ?? false;
    return useAdaptiveNotify ? 'ic_stat_notify' : null;
  }
}
