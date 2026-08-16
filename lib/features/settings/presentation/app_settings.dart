import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/notifications/presentation/notifications_settings.dart';
import 'package:fanotifier/features/browse/presentation/thumbnail_display_settings_screen.dart';
import 'package:fanotifier/features/settings/presentation/app_icon_settings_screen.dart';
import 'package:fanotifier/features/settings/presentation/set_home_screen_screen.dart';
import 'package:fanotifier/features/settings/presentation/translator_settings_screen.dart';
import 'package:fanotifier/features/notes/presentation/notes_settings_screen.dart';
import 'package:fanotifier/features/comments/presentation/comment_settings_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

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
            title: const Text('Thumbnail Display'),
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
            leading: const Icon(Icons.notifications_none_rounded, color: Color(0xFFE09321)),
            title: const Text('Notifications'),
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
          ListTile(
            leading: const Icon(
              Icons.mail_outline_rounded,
              color: Color(0xFFE09321),
            ),
            title: const Text('Notes'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotesSettingsScreen(),
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
              Icons.forum_outlined,
              color: Color(0xFFE09321),
            ),
            title: const Text('Comments'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommentsSettingsScreen(),
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
              Icons.g_translate,
              color: Color(0xFFE09321),
            ),
            title: const Text('Translator'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TranslatorSettingsScreen(),
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
              Icons.home_sharp,
              color: Color(0xFFE09321),
            ),
            title: const Text('Set Home Screen'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SetHomeScreenScreen(),
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
