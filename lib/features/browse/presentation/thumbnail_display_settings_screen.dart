import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/core/preferences/thumbnail_display_settings_provider.dart';

class ThumbnailDisplaySettingsScreen extends StatelessWidget {
  const ThumbnailDisplaySettingsScreen({super.key});

  static const Color _accent = Color(0xFFE09321);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ThumbnailDisplaySettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thumbnail Display'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          SwitchListTile(
            title: const Text('Show rating outline'),
            value: settings.showRatingOutline,
            activeThumbColor: _accent,
            onChanged: (val) => settings.setShowRatingOutline(val),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          SwitchListTile(
            title: const Text('Show title & author'),
            value: settings.showTitleAuthor,
            activeThumbColor: _accent,
            onChanged: (val) => settings.setShowTitleAuthor(val),
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


