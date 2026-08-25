// lib/services/notification_service.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notifications/data/pending_navigation_store.dart';
import 'package:fanotifier/features/notifications/domain/notification_payloads.dart';
import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';

typedef NotificationTapHandler = Future<void> Function(
  String payload,
  String source,
);

Future<void> _markTappedNoteAsShown(String payload) async {
  final noteId = noteIdFromNotificationPayload(payload);
  if (noteId == null) return;
  await MessageStorage.addShownNoteIds(<String>[noteId]);
}

/// Manages notification channels, shows notifications, and handles taps.
class NotificationService implements LocalNotificationGateway {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _kNextActivityNotificationId =
      'next_activity_notification_id';
  static const int _kActivityNotificationIdBase = 1500000000;
  static const int _kActivityNotificationIdMax = 1999999999;
  static const int activityNotificationId = _kActivityNotificationIdBase;
  static const int appUpdateNotificationId = 1400000000;
  static const String appUpdatePayload = appUpdateNotificationPayload;
  NotificationTapHandler? _notificationTapHandler;
  bool _pluginInitialized = false;
  bool _platformConfigured = false;

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

  Future<void> cancelActivityNotification({
    String source = 'unspecified',
  }) {
    appLog(
      '[NOTIFICATION_CANCEL] id=$activityNotificationId '
      'type=activity source=$source',
    );
    return flutterLocalNotificationsPlugin.cancel(id: activityNotificationId);
  }

  Future<void> cancelNotification(
    int id, {
    String source = 'unspecified',
  }) {
    appLog('[NOTIFICATION_CANCEL] id=$id type=generic source=$source');
    return flutterLocalNotificationsPlugin.cancel(id: id);
  }

  Future<Set<int>> getActiveNotificationIds() async {
    final notifications =
        await flutterLocalNotificationsPlugin.getActiveNotifications();
    return notifications
        .map((notification) => notification.id)
        .whereType<int>()
        .toSet();
  }

  Future<void> init({
    NotificationTapHandler? onNotificationTap,
  }) async {
    if (onNotificationTap != null) {
      _notificationTapHandler = onNotificationTap;
    }
    if (_pluginInitialized) return;

    await _initializePlugin(handlesTaps: true);
    final details =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if ((details?.didNotificationLaunchApp ?? false) &&
        details?.notificationResponse != null) {
      final payload = details!.notificationResponse!.payload;
      if (payload != null && payload.isNotEmpty) {
        await _markTappedNoteAsShown(payload);
        await const PendingNavigationStore().savePayload(payload);
      }
    }
    _pluginInitialized = true;
  }

  Future<void> initForBackgroundDisplay() async {
    if (!Platform.isIOS) {
      await init();
      return;
    }
    if (_pluginInitialized) return;
    await _initializePlugin(handlesTaps: false);
    _pluginInitialized = true;
  }

  Future<void> _initializePlugin({required bool handlesTaps}) async {
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
      onDidReceiveNotificationResponse:
          handlesTaps ? onDidReceiveNotificationResponse : null,
      onDidReceiveBackgroundNotificationResponse:
          handlesTaps ? notificationTapBackground : null,
    );
  }

  Future<void> configurePlatform() async {
    if (_platformConfigured) return;
    await init();
    if (!Platform.isAndroid) {
      await _requestIOSPermissions();
    }
    await _createNotificationChannels();
    _platformConfigured = true;
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
      const pendingNavigationStore = PendingNavigationStore();
      if (payload == appUpdatePayload) {
        await pendingNavigationStore.clearPayload();
        return;
      }

      await _markTappedNoteAsShown(payload);
      appLog('[NOTIF] Notification tap received (source=$source)');
      kDebugPrint(
        'NOTES REFRESH TRIGGERED_handletappayload (source=$source, payload=$payload)',
      );

      final handler = _notificationTapHandler;
      if (handler == null) {
        await pendingNavigationStore.savePayload(payload);
        return;
      }
      await handler(payload, source);
    } catch (e, st) {
      appLog('[_handleTapPayload] error: $e');
      kDebugPrint('[_handleTapPayload] error: $e\n$st');

      await const PendingNavigationStore().savePayload(payload);
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Future<void> showNotification(
    int id,
    String title,
    String body,
    String payload,
    String type, {
    int? badgeNumber,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    if (normalizedTitle.isEmpty || normalizedBody.isEmpty) {
      throw ArgumentError('Notification title and body must not be empty');
    }
    appLog('NotificationService.showNotification type=$type');
    kDebugPrint(
      'NotificationService.showNotification '
      'id=$id title=$normalizedTitle type=$type',
    );

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
        normalizedBody,
        contentTitle: normalizedTitle,
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
      title: normalizedTitle,
      body: normalizedBody,
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
  await _markTappedNoteAsShown(payload);
  await const PendingNavigationStore().savePayload(payload);
  appLog('[NOTIF_TAP_BG] saved pending notification payload.');
  kDebugPrint('[NOTIF_TAP_BG] saved payload "$payload"');
}
