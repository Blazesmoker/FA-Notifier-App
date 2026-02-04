import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart'; // If you need to reference AppTheme.fontName, etc.

import '../services/fa_http.dart';
import 'siteSettings.dart';
import 'appSettings.dart';

class SettingsScreen extends StatelessWidget {
  final Function onLogout;

  const SettingsScreen({
    Key? key,
    required this.onLogout,
  }) : super(key: key);

  static final Uri _telegramUri = Uri.parse('https://t.me/+xTEmmXoDW5tkMGFi');

  Future<void> _openTelegram(BuildContext context) async {
    try {
      if (!await launchUrl(_telegramUri, mode: LaunchMode.externalApplication)) {
        await launchUrl(_telegramUri);
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Telegram link')),
      );
    }
  }

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
    const String telegramDisplayText = 'Join our Telegram Group!';
    final noSplashTheme = Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
    return SafeArea(
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: Column(
          children: [
            Expanded(

              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_android, color: Color(0xFFE09321)),
                    title: const Text('App Settings'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AppSettingsScreen(),
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
                    leading: const Icon(Icons.public, color: Color(0xFFE09321)),
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
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 0.0),
              child: TextButton(
                onPressed: () => _openTelegram(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0088CC),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/Telegram_Logo.png',
                      width: 21,
                      height: 21,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      telegramDisplayText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontName,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE09321),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Image.asset(
                      'assets/icons/fathemed.png',
                      width: 21,
                      height: 21,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                FAHttp.userAgent,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontName,
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
