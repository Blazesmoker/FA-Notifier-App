import 'dart:io';

import 'package:fanotifier/features/notifications/data/notification_service.dart';
import 'package:fanotifier/features/notifications/domain/notification_permission_state.dart';
import 'package:fanotifier/features/notifications/domain/notification_platform_settings_repository.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService
    implements NotificationPlatformSettingsRepository {
  static const MethodChannel _settingsChannel =
      MethodChannel('com.blazesmoker.fanotifier/settings');
  static const _useAdaptiveNotificationIconKey = 'useAdaptiveNotificationIcon';

  @override
  Future<bool> loadUseAdaptiveNotificationIcon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdaptiveNotificationIconKey) ?? false;
  }

  @override
  Future<void> setUseAdaptiveNotificationIcon(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdaptiveNotificationIconKey, value);
    await refreshNotificationChannels();
  }

  @override
  Future<void> refreshNotificationChannels() async {
    await NotificationService().updateNotificationChannels();
  }

  @override
  Future<NotificationPermissionState> getNotificationPermissionState() async {
    final status = await Permission.notification.status;
    if (status.isGranted) {
      return NotificationPermissionState.granted;
    }
    if (status.isProvisional) {
      return NotificationPermissionState.provisional;
    }
    if (status.isRestricted) {
      return NotificationPermissionState.restricted;
    }
    if (status.isPermanentlyDenied) {
      return NotificationPermissionState.permanentlyDenied;
    }
    return NotificationPermissionState.denied;
  }

  @override
  Future<bool> openNotificationSettings() async {
    if (Platform.isAndroid) {
      return await _settingsChannel.invokeMethod<bool>('openAppSettings') ??
          false;
    }
    return openAppSettings();
  }
}
