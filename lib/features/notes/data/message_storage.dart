// lib/utils/message_storage.dart

import 'package:shared_preferences/shared_preferences.dart';

class MessageStorage {
  static const String _shownNoteIdsKey = 'shown_note_ids';

  /// Returns the set of note IDs that have already been shown in a notification.
  static Future<Set<String>> getShownNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_shownNoteIdsKey);
    return list?.toSet() ?? <String>{};
  }

  /// Adds [noteIds] to the “already shown” set so we don't show them again.
  static Future<void> addShownNoteIds(List<String> noteIds) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getShownNoteIds();
    existing.addAll(noteIds);
    await prefs.setStringList(_shownNoteIdsKey, existing.toList());
  }


  static Future<void> clearShownNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shownNoteIdsKey);
  }
}
