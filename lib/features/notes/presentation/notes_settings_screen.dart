import 'package:FANotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:FANotifier/features/notes/presentation/note_image_preview_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotesSettingsScreen extends StatelessWidget {
  const NotesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<NoteImagePreviewSettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notes Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.image_search, color: Color(0xFFE09321)),
            title: Text('Submission Image Previews'),
          ),
          RadioListTile<NoteImagePreviewMode>(
            value: NoteImagePreviewMode.manual,
            groupValue: settings.mode,
            activeColor: const Color(0xFFE09321),
            title: const Text('Manual'),
            subtitle: const Text('Load a preview after tapping its icon.'),
            onChanged: (value) {
              if (value != null) settings.setMode(value);
            },
          ),
          RadioListTile<NoteImagePreviewMode>(
            value: NoteImagePreviewMode.always,
            groupValue: settings.mode,
            activeColor: const Color(0xFFE09321),
            title: const Text('Always'),
            subtitle: const Text('Automatically load preview thumbnails.'),
            onChanged: (value) {
              if (value != null) settings.setMode(value);
            },
          ),
          RadioListTile<NoteImagePreviewMode>(
            value: NoteImagePreviewMode.off,
            groupValue: settings.mode,
            activeColor: const Color(0xFFE09321),
            title: const Text('Off'),
            onChanged: (value) {
              if (value != null) settings.setMode(value);
            },
          ),
        ],
      ),
    );
  }
}
