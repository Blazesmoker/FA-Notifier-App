import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../custom_drawer/drawer_user_controller.dart';
import '../main.dart';
import '../screens/notesscreen.dart';


class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;
  final GlobalKey<DrawerUserControllerState> drawerKey = GlobalKey<DrawerUserControllerState>();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  NotificationService._internal();

  Future<String?> getNotificationIconBasedOnPreference() async {
    final prefs = await SharedPreferences.getInstance();


    final useAdaptiveNotify = prefs.getBool('useAdaptiveNotificationIcon')
        ?? prefs.getBool('useAdaptiveIcon')
        ?? false;

    return useAdaptiveNotify ? 'ic_stat_notify' : null;
  }


  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

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

    // On iOS, request permission
    if (!Platform.isAndroid) {
      await _requestIOSPermissions();
    }
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
      debugPrint('iOS notification permission: $result');
    }
  }

  void onDidReceiveNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NotesScreen(drawerKey: drawerKey,),
      ),
    );
  }

  Future<void> showNotesNotification(int id, String title, String body, String payload) async {
    debugPrint('NotificationService.showNotification called with id=$id, title=$title');

    final icon = await getNotificationIconBasedOnPreference();

    // BigTextStyleInformation to display long text on Android
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'new_message_channel_id',
      'New Messages',
      channelDescription: 'Channel for new message notifications',
      importance: Importance.max,
      priority: Priority.high,
      icon: icon, // adaptive-aware icon
      showWhen: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        // summaryText: 'Optional summary text',
      ),
    );


    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
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
}