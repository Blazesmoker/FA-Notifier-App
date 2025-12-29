// lib/services/notification_service.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../custom_drawer/drawer_user_controller.dart';
import '../main.dart';
import 'package:FANotifier/providers/NotificationNavigationProvider.dart';
import 'package:FANotifier/services/notes_refresh_service.dart';
import 'package:FANotifier/services/notification_refresh_service.dart';

/// Manages notification channels, shows notifications, and handles taps.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final GlobalKey<DrawerUserControllerState> drawerKey =
  GlobalKey<DrawerUserControllerState>();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static const List<String> notificationTypes = <String>[
    'submissions',
    'watches',
    'comments',
    'favorites',
    'journals',
    'notes',
    'activities',
  ];

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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (!Platform.isAndroid) {
      await _requestIOSPermissions();
    }

    await _createNotificationChannels();

    _iosChannel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped') {
        final Map<String, dynamic> map =
        Map<String, dynamic>.from(call.arguments as Map);
        final String? payload = _extractPayloadFromNative(map);
        if (payload != null) {
          await _handleTapPayload(payload, source: 'iosChannel');
        } else {
          // Heuristic fallback: route by "type" in userInfo
          final userInfo =
              (map['userInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
          if (userInfo['type'] == 'notes') {
            await _handleTapPayload('note_native', source: 'iosChannel');
          } else if (userInfo['type'] == 'activities') {
            await _handleTapPayload('activity_native', source: 'iosChannel');
          }
        }
      }
    });

    try {
      await _iosChannel.invokeMethod('notifications.ready');
    } catch (_) {}

    final details =
    await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if ((details?.didNotificationLaunchApp ?? false) &&
        details?.notificationResponse != null) {
      final payload = details!.notificationResponse!.payload;
      if (payload != null && payload.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_navigation', payload);
      }
    }
  }


  Future<void> _requestIOSPermissions() async {
    final implementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (implementation != null) {
      await implementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }


  Future<void> _createNotificationChannels() async {
    final prefs = await SharedPreferences.getInstance();

    for (final type in notificationTypes) {
      bool soundEnabled = true;
      bool vibrationEnabled = true;

      switch (type) {
        case 'submissions':
          soundEnabled =
              prefs.getBool('sound_new_submissions_enabled') ?? true;
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

      final String channelId =
          '${type}_sound_${soundEnabled ? "on" : "off"}_vibration_${vibrationEnabled ? "on" : "off"}';

      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        '${_capitalize(type)} Notifications',
        description: 'Notifications for $type with sound/vibration preferences',
        importance: Importance.high,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        sound: soundEnabled
            ? null
            : const RawResourceAndroidNotificationSound('silent'),
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }


  Future<void> onDidReceiveNotificationResponse(
      NotificationResponse response) async {
    final String? payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    await _handleTapPayload(payload, source: 'plugin');
  }


  Future<void> _handleTapPayload(
      String payload, {
        required String source,
      }) async {
    try {
      debugPrint(
        'NOTES REFRESH TRIGGERED_handletappayload (source=$source, payload=$payload)',
      );

      final prefs = await SharedPreferences.getInstance();

      // If no UI yet, stash for later processing by lifecycle/Home
      final BuildContext? context = navigatorKey.currentContext;
      if (context == null) {
        await prefs.setString('pending_navigation', payload);
        debugPrint('[NOTIF] No UI context; saved pending_navigation="$payload"');
        return;
      }


      // Pop to root to ensure HomeScreen is on top
      navigatorKey.currentState?.popUntil((r) => r.isFirst);

      // Remove pending since we're going to handle it now
      await prefs.remove('pending_navigation');

      // Defer until the next frame so HomeScreen is definitely built.
      //
      // IMPORTANT: `addPostFrameCallback` does NOT schedule a frame by itself.
      // When the app is already on the root route and idle, tapping a system
      // notification may deliver the callback without triggering a Flutter
      // frame. In that case this work would not run until the user touches the
      // screen (which schedules a frame). We force a visual update below.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Extra micro-delay helps in release with heavy first-frame work
        await Future<void>.delayed(const Duration(milliseconds: 16));

        final ctx = navigatorKey.currentContext;
        if (ctx == null) {
          // If we lost context again, stash and bail
          await prefs.setString('pending_navigation', payload);
          debugPrint('[NOTIF] Lost context after frame; re-stashed payload.');
          return;
        }

        final navProvider =
        Provider.of<NotificationNavigationProvider>(ctx, listen: false);

        final bool isNotes = payload.startsWith('note_') ||
            payload.contains('DrawerIndex.Notes') ||
            payload == 'note_native';

        // Switch tab first
        navProvider.setTargetIndex(isNotes ? 4 : 3);

        // Trigger refresh immediately. Both screens are kept alive in the
        // HomeScreen `IndexedStack`, so their stream listeners are active even
        // when not visible.
        try {
          if (isNotes) {
            NotesRefreshService().triggerRefresh();
            debugPrint('NOTES REFRESH TRIGGERED_service');
          } else {
            NotificationRefreshService().triggerRefresh();
            debugPrint('ACTIVITIES REFRESH TRIGGERED_service');
          }
        } catch (e) {
          debugPrint('[_handleTapPayload] refresh error: $e');
        }

        // Mark handled to avoid double-processing
        await prefs.setString('last_handled_payload', payload);
      });

      // Ensure the post-frame callback above actually gets a frame to run on.
      // (Fixes "tap does nothing until I touch the screen".)
      SchedulerBinding.instance.ensureVisualUpdate();
    } catch (e, st) {
      debugPrint('[_handleTapPayload] error: $e\n$st');
      // As a fallback, stash for lifecycle processing
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_navigation', payload);
    }
  }


  // For iOS native dictionary -> payload string
  String? _extractPayloadFromNative(Map<String, dynamic> native) {
    if (native['payload'] is String &&
        (native['payload'] as String).isNotEmpty) {
      return native['payload'] as String;
    }
    final Map<String, dynamic> userInfo =
        (native['userInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (userInfo['payload'] is String) return userInfo['payload'] as String;
    if (userInfo['route'] == '/notes') return 'note_native';
    if (userInfo['route'] == '/activities') return 'activity_native';
    return null;
  }

  // ========= Utility =========
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> showNotification(
      int id,
      String title,
      String body,
      String payload,
      String type,
      ) async {
    debugPrint(
        'NotificationService.showNotification id=$id title=$title type=$type');

    final prefs = await SharedPreferences.getInstance();
    bool soundEnabled = true, vibrationEnabled = true;

    switch (type) {
      case 'notes':
        soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
        vibrationEnabled =
            prefs.getBool('vibration_new_notes_enabled') ?? true;
        break;
      case 'activities':
        soundEnabled =
            prefs.getBool('sound_new_activities_enabled') ?? true;
        vibrationEnabled =
            prefs.getBool('vibration_new_activities_enabled') ?? true;
        break;
      default:
        soundEnabled = true;
        vibrationEnabled = true;
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
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );

    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      interruptionLevel: InterruptionLevel.active,
    );

    final details = NotificationDetails(android: android, iOS: ios);

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    debugPrint('flutterLocalNotificationsPlugin.show completed');
  }

  Future<void> updateNotificationChannels() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (final type in notificationTypes) {
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
    final useAdaptiveNotify = prefs.getBool('useAdaptiveNotificationIcon') ??
        prefs.getBool('useAdaptiveIcon') ??
        false;
    return useAdaptiveNotify ? 'ic_stat_notify' : null;
  }
}


@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  WidgetsFlutterBinding.ensureInitialized();

  final payload = response.payload ?? '';
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_navigation', payload);
  debugPrint('[NOTIF_TAP_BG] saved payload "$payload"');
}
