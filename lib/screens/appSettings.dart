import 'dart:io';

import 'package:flutter/material.dart';
import 'notificationsSettings.dart';
import 'thumbnail_display_settings_screen.dart';
import 'app_icon_settings_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          const SizedBox(height: 8),
          if (Platform.isAndroid) ...[
            ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: OverflowBox(
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: 48,
                  maxHeight: 48,
                  child: Image.asset(
                    'assets/icons/AppIcon.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              title: const Text('App Icon'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AppIconSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(
              height: 1.0,
              color: Color(0xFF111111),
              thickness: 3.0,
            ),
          ],
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: Color(0xFFE09321),
            ),
            title: const Text('Thumbnail display'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ThumbnailDisplaySettingsScreen(),
                ),
              );
            },
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Color(0xFFE09321)),
            title: const Text('Notification Settings'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
        ],
      ),
    );
  }
}
