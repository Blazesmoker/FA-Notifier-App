// lib/screens/notificationsSettings.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/notification_settings_provider.dart';
import '../services/notification_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  static const MethodChannel _settingsChannel =
      MethodChannel('com.blazesmoker.fanotifier/settings');
  bool useAdaptiveNotificationIcon = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationIconPreference();
  }

  Future<void> _loadNotificationIconPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      useAdaptiveNotificationIcon =
          prefs.getBool('useAdaptiveNotificationIcon') ?? false;
    });
  }

  Future<void> _toggleNotificationIcon(bool value) async {
    setState(() => useAdaptiveNotificationIcon = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useAdaptiveNotificationIcon', value);

    // Recreates channels so they pick up the new icon
    await NotificationService().updateNotificationChannels();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        content: Text(
          'Notification icon set to ${value ? 'Adaptive' : 'Classic'}.',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _checkNotificationPermissions() async {
    final status = await Permission.notification.status;
    if (!mounted) {
      return;
    }

    final message = status.isGranted
        ? 'Notification permissions are allowed.'
        : status.isProvisional
            ? 'Notification permissions are provisional.'
            : status.isRestricted
                ? 'Notification permissions are restricted.'
                : status.isPermanentlyDenied
                    ? 'Notification permissions are blocked. Open app settings to change them.'
                    : 'Notification permissions are not allowed.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: status.isGranted || status.isProvisional
            ? Colors.green
            : const Color(0xFFE09321),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    final opened = Platform.isAndroid
        ? await _settingsChannel.invokeMethod<bool>('openAppSettings') ?? false
        : await openAppSettings();
    if (!mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open app settings.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE09321),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 8.0,
                        ),
                      ),
                      onPressed: _checkNotificationPermissions,
                      child: const Text('Check notification permissions'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openNotificationSettings,
                    icon: const Icon(
                      Icons.open_in_new,
                      color: Color(0xFFE09321),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              color: Color(0xFF111111),
              thickness: 3,
            ),
            if (Platform.isAndroid) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6.0, bottom: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: const Text(
                          'Classic icon',
                          style: TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Switch(
                      value: useAdaptiveNotificationIcon,
                      activeThumbColor: const Color(0xFFE09321),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: _toggleNotificationIcon,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: const Text(
                          'Adaptive icon',
                          style: TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
                color: Color(0xFF111111),
                thickness: 3,
              ),
            ],
            Consumer<NotificationSettingsProvider>(
              builder: (context, settings, child) {
                return Column(
                  children: [
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Submissions'),
                      value: settings.drawerSubmissionsEnabled,
                      onChanged: settings.setDrawerSubmissionsEnabled,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Watches'),
                      value: settings.drawerWatchesEnabled,
                      onChanged: settings.setDrawerWatchesEnabled,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Comments'),
                      value: settings.drawerCommentsEnabled,
                      onChanged: settings.setDrawerCommentsEnabled,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Favorites'),
                      value: settings.drawerFavoritesEnabled,
                      onChanged: settings.setDrawerFavoritesEnabled,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Journals'),
                      value: settings.drawerJournalsEnabled,
                      onChanged: settings.setDrawerJournalsEnabled,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Notes'),
                      value: settings.drawerNotesEnabled,
                      onChanged: settings.setDrawerNotesEnabled,
                    ),
                    const Divider(
                      height: 8.0,
                      color: Color(0xFF111111),
                      thickness: 3.0,
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Sound for Notes'),
                      value: settings.soundNewNotesEnabled,
                      onChanged: (bool value) async {
                        settings.setSoundNewNotesEnabled(value);
                        await NotificationService().updateNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Vibration for Notes'),
                      value: settings.vibrationNewNotesEnabled,
                      onChanged: (bool value) async {
                        settings.setVibrationNewNotesEnabled(value);
                        await NotificationService().updateNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Sound for Activities'),
                      value: settings.soundNewActivitiesEnabled,
                      onChanged: (bool value) async {
                        settings.setSoundNewActivitiesEnabled(value);
                        await NotificationService().updateNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Vibration for Activities'),
                      value: settings.vibrationNewActivitiesEnabled,
                      onChanged: (bool value) async {
                        settings.setVibrationNewActivitiesEnabled(value);
                        await NotificationService().updateNotificationChannels();
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
