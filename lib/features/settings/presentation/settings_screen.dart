import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/core/links/app_external_links.dart';
import 'package:fanotifier/features/settings/domain/settings_app_info_repository.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/settings/presentation/site_settings.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/settings/presentation/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  final Function onLogout;

  const SettingsScreen({
    super.key,
    required this.onLogout,
  });

  Future<void> _openTelegram(BuildContext context) async {
    try {
      await launchExternalUriWithFallback(AppExternalLinks.telegramUri);
    } catch (_) {
      if (!context.mounted) return;
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
    final userAgent = context.read<SettingsAppInfoRepository>().userAgent;
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
                          settings: const AnalyticsRouteSettings(
                            AppScreens.appSettings,
                          ),
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
                    title: const Text('FurAffinity Settings'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: const AnalyticsRouteSettings(
                            AppScreens.furAffinitySettings,
                          ),
                          builder: (context) => FurAffinitySettingsScreen(
                            onLogout: () {
                              onLogout();
                            },
                          ),
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
                userAgent,
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
