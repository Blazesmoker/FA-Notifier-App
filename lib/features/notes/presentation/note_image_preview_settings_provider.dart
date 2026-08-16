import 'package:fanotifier/features/notes/data/note_image_preview_preference.dart';
import 'package:fanotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:flutter/foundation.dart';

class NoteImagePreviewSettingsProvider with ChangeNotifier {
  NoteImagePreviewSettingsProvider({
    this._preference = const NoteImagePreviewPreference(),
  }) {
    load();
  }

  final NoteImagePreviewPreference _preference;
  NoteImagePreviewMode _mode = NoteImagePreviewMode.manual;
  bool _loaded = false;

  NoteImagePreviewMode get mode => _mode;
  bool get loaded => _loaded;

  Future<void> load() async {
    _mode = await _preference.loadMode();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(NoteImagePreviewMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _preference.saveMode(mode);
  }
}
