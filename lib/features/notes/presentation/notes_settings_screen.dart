import 'package:fanotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:fanotifier/features/notes/presentation/note_image_preview_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotesSettingsScreen extends StatelessWidget {
  const NotesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<NoteImagePreviewSettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notes Settings')),
      body: RadioGroup<NoteImagePreviewMode>(
        groupValue: settings.mode,
        onChanged: (value) {
          if (value != null) settings.setMode(value);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            const SizedBox(height: 8),
            const ListTile(
              leading: Icon(Icons.image_search, color: Color(0xFFE09321)),
              title: Text('Submission Image Previews'),
            ),
            const RadioListTile<NoteImagePreviewMode>(
              value: NoteImagePreviewMode.manual,
              activeColor: Color(0xFFE09321),
              title: Text('Manual'),
              subtitle: Text('Load a preview after tapping its icon.'),
            ),
            const RadioListTile<NoteImagePreviewMode>(
              value: NoteImagePreviewMode.always,
              activeColor: Color(0xFFE09321),
              title: Text('Always'),
              subtitle: Text('Automatically load image previews.'),
            ),
            const RadioListTile<NoteImagePreviewMode>(
              value: NoteImagePreviewMode.off,
              activeColor: Color(0xFFE09321),
              title: Text('Off'),
            ),
          ],
        ),
      ),
    );
  }
}
