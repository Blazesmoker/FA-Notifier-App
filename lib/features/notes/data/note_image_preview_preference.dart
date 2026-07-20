import 'package:fanotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoteImagePreviewPreference {
  const NoteImagePreviewPreference();

  static const _modeKey = 'note_image_preview_mode';

  Future<NoteImagePreviewMode> loadMode() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_modeKey)) {
      'off' => NoteImagePreviewMode.off,
      'always' => NoteImagePreviewMode.always,
      _ => NoteImagePreviewMode.manual,
    };
  }

  Future<void> saveMode(NoteImagePreviewMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeKey, mode.name);
  }
}
