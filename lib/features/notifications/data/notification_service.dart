// lib/services/notification_service.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:FANotifier/main.dart';
import 'package:FANotifier/features/notifications/data/NotificationNavigationProvider.dart';
import 'package:FANotifier/features/notifications/data/activities_notification_state.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/notification_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/pending_navigation_store.dart';
import 'package:FANotifier/core/logging/app_logging.dart';

bool isActivityNotificationPayload(String payload) {
  return payload.startsWith('fa_activity_') ||
      payload.startsWith('activity_') ||
      payload.contains('DrawerIndex.Notifications') ||
      payload == 'activity_native';
}

bool isNoteNotificationPayload(String payload) {
  return payload.startsWith('note_') ||
      payload.contains('DrawerIndex.Notes') ||
      payload == 'note_native';
}

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
    'updates',
  ];

  static const MethodChannel _iosChannel = MethodChannel('app.notifications');
  static const String _kNextActivityNotificationId =
      'next_activity_notification_id';
  static const int _kActivityNotificationIdBase = 1500000000;
  static const int _kActivityNotificationIdMax = 1999999999;
  static const int activityNotificationId = _kActivityNotificationIdBase;
  static const int appUpdateNotificationId = 1400000000;
  static const String appUpdatePayload = appUpdateNotificationPayload;

  Future<int> allocateActivityNotificationId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    int nextId = prefs.getInt(_kNextActivityNotificationId) ??
        _kActivityNotificationIdBase;
    if (nextId < _kActivityNotificationIdBase ||
        nextId > _kActivityNotificationIdMax) {
      nextId = _kActivityNotificationIdBase;
    }

    final int allocatedId = nextId;
    final int followingId = allocatedId >= _kActivityNotificationIdMax
        ? _kActivityNotificationIdBase
        : allocatedId + 1;
    await prefs.setInt(_kNextActivityNotificationId, followingId);

    return allocatedId;
  }

  Future<void> cancelActivityNotification() {
    return flutterLocalNotificationsPlugin.cancel(id: activityNotificationId);
  }

  Future<void> cancelNotification(int id) {
    return flutterLocalNotificationsPlugin.cancel(id: id);
  }

  Future<void> init({
    Future<void> Function()? onLaunchPayloadSaved,
  }) async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/fathemednotif');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
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
        if (isActivityNotificationPayload(payload)) {
          await ActivitiesNotificationStateStore()
              .requestAcknowledgeOnNextForegroundFetch();
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_navigation', payload);
        await onLaunchPayloadSaved?.call();
      }
    }
  }

  Future<void> _requestIOSPermissions() async {
    final implementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
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
      final prefs = await SharedPreferences.getInstance();
      if (payload == appUpdatePayload) {
        await prefs.remove('pending_navigation');
        return;
      }

      if (isActivityNotificationPayload(payload)) {
        await ActivitiesNotificationStateStore()
            .requestAcknowledgeOnNextForegroundFetch();
      }
      appLog('[NOTIF] Notification tap received (source=$source)');
      kDebugPrint(
        'NOTES REFRESH TRIGGERED_handletappayload (source=$source, payload=$payload)',
      );

      final BuildContext? context = navigatorKey.currentContext;
      if (context == null) {
        await prefs.setString('pending_navigation', payload);
        appLog('[NOTIF] No UI context; saved pending navigation.');
        kDebugPrint(
            '[NOTIF] No UI context; saved pending_navigation="$payload"');
        return;
      }

      navigatorKey.currentState?.popUntil((r) => r.isFirst);

      await prefs.remove('pending_navigation');

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 16));

        final ctx = navigatorKey.currentContext;
        if (ctx == null) {
          await prefs.setString('pending_navigation', payload);
          appLog(
              '[NOTIF] Lost context after frame; re-stashed pending navigation.');
          return;
        }

        final navProvider =
            Provider.of<NotificationNavigationProvider>(ctx, listen: false);

        final bool isNotes = isNoteNotificationPayload(payload);

        navProvider.setTargetIndex(isNotes ? 4 : 3);

        try {
          if (isNotes) {
            NotesRefreshService().triggerRefresh();
            appLog('[NOTIF] Notes refresh triggered.');
          } else {
            NotificationRefreshService().triggerRefresh();
            appLog('[NOTIF] Activities refresh triggered.');
          }
        } catch (e) {
          appLog('[_handleTapPayload] refresh error: $e');
        }

        await prefs.setString('last_handled_payload', payload);
      });

      SchedulerBinding.instance.ensureVisualUpdate();
    } catch (e, st) {
      appLog('[_handleTapPayload] error: $e');
      kDebugPrint('[_handleTapPayload] error: $e\n$st');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_navigation', payload);
    }
  }

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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> showNotification(
    int id,
    String title,
    String body,
    String payload,
    String type, {
    int? badgeNumber,
  }) async {
    appLog('NotificationService.showNotification type=$type');
    kDebugPrint(
        'NotificationService.showNotification id=$id title=$title type=$type');

    final prefs = await SharedPreferences.getInstance();
    bool soundEnabled = true, vibrationEnabled = true;

    switch (type) {
      case 'notes':
        soundEnabled = prefs.getBool('sound_new_notes_enabled') ?? true;
        vibrationEnabled = prefs.getBool('vibration_new_notes_enabled') ?? true;
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
      badgeNumber: badgeNumber,
      interruptionLevel: InterruptionLevel.active,
    );

    final details = NotificationDetails(android: android, iOS: ios);

    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );

    appLog('Notification displayed for type=$type');
  }

  Future<void> updateNotificationChannels() async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (final type in notificationTypes) {
        for (final channelId in <String>[
          '${type}_sound_on_vibration_on',
          '${type}_sound_on_vibration_off',
          '${type}_sound_off_vibration_on',
          '${type}_sound_off_vibration_off',
        ]) {
          await androidPlugin.deleteNotificationChannel(channelId: channelId);
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
  if (isActivityNotificationPayload(payload)) {
    await ActivitiesNotificationStateStore()
        .requestAcknowledgeOnNextForegroundFetch();
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_navigation', payload);
  appLog('[NOTIF_TAP_BG] saved pending notification payload.');
  kDebugPrint('[NOTIF_TAP_BG] saved payload "$payload"');
}
