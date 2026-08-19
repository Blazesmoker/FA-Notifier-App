import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/preferences/privacy_settings_provider.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<PrivacySettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          const SizedBox(height: 8),
          SwitchListTile(
            activeThumbColor: const Color(0xFFE09321),
            secondary: const Icon(
              Icons.analytics_outlined,
              color: Color(0xFFE09321),
            ),
            title: const Text('Google Firebase Analytics'),
            value: settings.analyticsEnabled,
            onChanged: settings.setAnalyticsEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
            child: Text(
              'App usage statistics, which screens are used, and general '
              'geographic statistics such as country. Not used for '
              'advertising tracking.',
              style: TextStyle(
                fontFamily: AppTheme.fontName,
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          SwitchListTile(
            activeThumbColor: const Color(0xFFE09321),
            secondary: const Icon(
              Icons.bug_report_outlined,
              color: Color(0xFFE09321),
            ),
            title: const Text('Google Firebase Crashlytics'),
            value: settings.crashlyticsEnabled,
            onChanged: settings.setCrashlyticsEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
            child: Text(
              'Crash reports and technical diagnostics of errors and app '
              'crashes.',
              style: TextStyle(
                fontFamily: AppTheme.fontName,
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Analytics and crash reports are used only to understand app '
              'usage and diagnose problems. FA Notifier does not use this '
              'data for advertising or tracking and does not intentionally '
              'collect your name, email address, Fur Affinity credentials, '
              'messages, or other personal content.',
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
    );
  }
}