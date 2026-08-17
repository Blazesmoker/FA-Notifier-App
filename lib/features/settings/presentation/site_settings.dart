import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_account_settings_screen.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_global_site_settings_screen.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_user_settings_screen.dart';
import 'package:fanotifier/features/settings/presentation/tag_blocklist_screen.dart';

class FurAffinitySettingsScreen extends StatelessWidget {
  const FurAffinitySettingsScreen({
    super.key,
    required this.onLogout,
  });

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FurAffinity Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.manage_accounts_outlined,
                color: Color(0xFFE09321),
              ),
              title: const Text('Account Settings'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const AnalyticsRouteSettings(
                      AppScreens.furAffinityAccountSettings,
                    ),
                    builder: (_) => FurAffinityAccountSettingsScreen(
                      onSessionInvalidated: onLogout,
                    ),
                  ),
                );
              },
            ),
            const Divider(
              height: 1,
              color: Color(0xFF111111),
              thickness: 3,
            ),
            ListTile(
              leading: const Icon(
                Icons.public_outlined,
                color: Color(0xFFE09321),
              ),
              title: const Text('Global Site Settings'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const AnalyticsRouteSettings(
                      AppScreens.furAffinityGlobalSiteSettings,
                    ),
                    builder: (_) =>
                        const FurAffinityGlobalSiteSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(
              height: 1,
              color: Color(0xFF111111),
              thickness: 3,
            ),
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: Color(0xFFE09321),
              ),
              title: const Text('User Settings'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const AnalyticsRouteSettings(
                      AppScreens.furAffinityUserSettings,
                    ),
                    builder: (_) => const FurAffinityUserSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(
              height: 1,
              color: Color(0xFF111111),
              thickness: 3,
            ),
            ListTile(
              leading: const Icon(
                Icons.label_off_outlined,
                color: Color(0xFFE09321),
              ),
              title: const Text('Tag Blocklist'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const AnalyticsRouteSettings(
                      AppScreens.tagBlocklist,
                    ),
                    builder: (_) => const TagBlocklistScreen(),
                  ),
                );
              },
            ),
            const Divider(
              height: 1,
              color: Color(0xFF111111),
              thickness: 3,
            ),
          ],
        ),
      ),
    );
  }
}
