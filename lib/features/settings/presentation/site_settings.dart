import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/settings/presentation/tag_blocklist_screen.dart';

class SiteSettingsScreen extends StatelessWidget {
  const SiteSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text('Site Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          ListTile(
            leading: const Icon(
              Icons.label_off_outlined,
              color: Color(0xFFE09321),
            ),
            title: const Text('Tag Blocklist'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TagBlocklistScreen()),
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
