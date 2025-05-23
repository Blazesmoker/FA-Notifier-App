// lib/screens/notificationsSettings.dart

import 'dart:io';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications Settings')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (Platform.isAndroid) ...[
                // Icon style toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Classic icon',
                            style: TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),

                        ],
                      ),
                    ),
                    Switch(
                      value: useAdaptiveNotificationIcon,
                      activeColor: const Color(0xFFE09321),
                      onChanged: _toggleNotificationIcon,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Adaptive icon',
                            style: TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),

                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(
                  height: 1,
                  color: Color(0xFF111111),
                  thickness: 3,
                ),
              ],

              // Notification type toggles
              Consumer<NotificationSettingsProvider>(
                builder: (context, settings, child) {
                  return Column(
                    children: [
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Submissions'),
                        value: settings.drawerSubmissionsEnabled,
                        onChanged: settings.setDrawerSubmissionsEnabled,
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Watches'),
                        value: settings.drawerWatchesEnabled,
                        onChanged: settings.setDrawerWatchesEnabled,
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Comments'),
                        value: settings.drawerCommentsEnabled,
                        onChanged: settings.setDrawerCommentsEnabled,
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Favorites'),
                        value: settings.drawerFavoritesEnabled,
                        onChanged: settings.setDrawerFavoritesEnabled,
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Journals'),
                        value: settings.drawerJournalsEnabled,
                        onChanged: settings.setDrawerJournalsEnabled,
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
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
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Sound for Notes'),
                        value: settings.soundNewNotesEnabled,
                        onChanged: (bool value) async {
                          settings.setSoundNewNotesEnabled(value);
                          await NotificationService()
                              .updateNotificationChannels();
                        },
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Vibration for Notes'),
                        value: settings.vibrationNewNotesEnabled,
                        onChanged: (bool value) async {
                          settings.setVibrationNewNotesEnabled(value);
                          await NotificationService()
                              .updateNotificationChannels();
                        },
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Sound for Activities'),
                        value: settings.soundNewActivitiesEnabled,
                        onChanged: (bool value) async {
                          settings.setSoundNewActivitiesEnabled(value);
                          await NotificationService()
                              .updateNotificationChannels();
                        },
                      ),
                      SwitchListTile(
                        activeColor: const Color(0xFFE09321),
                        title: const Text('Vibration for Activities'),
                        value: settings.vibrationNewActivitiesEnabled,
                        onChanged: (bool value) async {
                          settings.setVibrationNewActivitiesEnabled(value);
                          await NotificationService()
                              .updateNotificationChannels();
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
