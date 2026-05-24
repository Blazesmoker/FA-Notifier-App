import 'dart:io';

import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService {
  static const MethodChannel _settingsChannel =
      MethodChannel('com.blazesmoker.fanotifier/settings');
  static const _useAdaptiveNotificationIconKey = 'useAdaptiveNotificationIcon';

  Future<bool> loadUseAdaptiveNotificationIcon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdaptiveNotificationIconKey) ?? false;
  }

  Future<void> setUseAdaptiveNotificationIcon(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdaptiveNotificationIconKey, value);
    await refreshNotificationChannels();
  }

  Future<void> refreshNotificationChannels() async {
    await NotificationService().updateNotificationChannels();
  }

  Future<bool> openNotificationSettings() async {
    if (Platform.isAndroid) {
      return await _settingsChannel.invokeMethod<bool>('openAppSettings') ??
          false;
    }
    return openAppSettings();
  }
}
