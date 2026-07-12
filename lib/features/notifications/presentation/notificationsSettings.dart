// lib/screens/notificationsSettings.dart

import 'dart:io';

import 'package:FANotifier/features/notifications/domain/notification_permission_state.dart';
import 'package:FANotifier/features/notifications/domain/notification_platform_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:FANotifier/features/notifications/presentation/notification_settings_provider.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({
    Key? key,
    this.platformSettingsRepository,
  }) : super(key: key);

  final NotificationPlatformSettingsRepository? platformSettingsRepository;

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  late final NotificationPlatformSettingsRepository
      _notificationSettingsService;
  bool useAdaptiveNotificationIcon = false;

  @override
  void initState() {
    super.initState();
    _notificationSettingsService = widget.platformSettingsRepository ??
        context.read<NotificationPlatformSettingsRepository>();
    _loadNotificationIconPreference();
  }

  Future<void> _loadNotificationIconPreference() async {
    final loadedUseAdaptiveNotificationIcon =
        await _notificationSettingsService.loadUseAdaptiveNotificationIcon();
    setState(() {
      useAdaptiveNotificationIcon = loadedUseAdaptiveNotificationIcon;
    });
  }

  Future<void> _toggleNotificationIcon(bool value) async {
    setState(() => useAdaptiveNotificationIcon = value);
    await _notificationSettingsService.setUseAdaptiveNotificationIcon(value);

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
    final status =
        await _notificationSettingsService.getNotificationPermissionState();
    if (!mounted) {
      return;
    }

    final message = status == NotificationPermissionState.granted
        ? 'Notification permissions are allowed.'
        : status == NotificationPermissionState.provisional
            ? 'Notification permissions are provisional.'
            : status == NotificationPermissionState.restricted
                ? 'Notification permissions are restricted.'
                : status == NotificationPermissionState.permanentlyDenied
                    ? 'Notification permissions are blocked. Open app settings to change them.'
                    : 'Notification permissions are not allowed.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: status == NotificationPermissionState.granted ||
                status == NotificationPermissionState.provisional
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
    final opened =
        await _notificationSettingsService.openNotificationSettings();
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
                        await _notificationSettingsService
                            .refreshNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Vibration for Notes'),
                      value: settings.vibrationNewNotesEnabled,
                      onChanged: (bool value) async {
                        settings.setVibrationNewNotesEnabled(value);
                        await _notificationSettingsService
                            .refreshNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Sound for Activities'),
                      value: settings.soundNewActivitiesEnabled,
                      onChanged: (bool value) async {
                        settings.setSoundNewActivitiesEnabled(value);
                        await _notificationSettingsService
                            .refreshNotificationChannels();
                      },
                    ),
                    SwitchListTile(
                      activeThumbColor: const Color(0xFFE09321),
                      title: const Text('Vibration for Activities'),
                      value: settings.vibrationNewActivitiesEnabled,
                      onChanged: (bool value) async {
                        settings.setVibrationNewActivitiesEnabled(value);
                        await _notificationSettingsService
                            .refreshNotificationChannels();
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
