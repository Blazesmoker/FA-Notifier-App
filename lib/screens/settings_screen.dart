import 'package:flutter/material.dart';
import '../app_theme.dart'; // If you need to reference AppTheme.fontName, etc.

import 'siteSettings.dart';
import 'appSettings.dart';

class SettingsScreen extends StatelessWidget {
  final Function onLogout;

  const SettingsScreen({
    Key? key,
    required this.onLogout,
  }) : super(key: key);

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Log Out',
                style: TextStyle(color: Colors.redAccent),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onLogout();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('App Settings'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
              );
            },
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),

          //TODO: Site Settings Screen
          /*
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Site Settings'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SiteSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          */





          ListTile(
            leading: const Icon(
              Icons.power_settings_new,
              color: Colors.redAccent,
            ),
            title: Text(
              'Log Out',
              style: TextStyle(
                fontFamily: AppTheme.fontName,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.redAccent,
              ),
            ),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}
