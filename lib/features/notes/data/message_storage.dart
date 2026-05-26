// lib/utils/message_storage.dart

import 'package:shared_preferences/shared_preferences.dart';

class MessageStorage {
  static const String _shownNoteIdsKey = 'shown_note_ids';
  static const String _seenNoteIdsKey = 'seen_note_ids';

  /// Returns the set of note IDs that have already been shown in a notification.
  static Future<Set<String>> getShownNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_shownNoteIdsKey);
    return list?.where((id) => id.trim().isNotEmpty).toSet() ?? <String>{};
  }

  /// Returns note IDs that have appeared in a fetched inbox page.
  ///
  /// This is separate from [getShownNoteIds]: old unread notes from the first
  /// install run are "known" even when they should not produce notifications.
  static Future<Set<String>> getSeenNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_seenNoteIdsKey);
    return list?.where((id) => id.trim().isNotEmpty).toSet() ?? <String>{};
  }

  /// Adds [noteIds] to the “already shown” set so we don't show them again.
  static Future<void> addShownNoteIds(List<String> noteIds) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getShownNoteIds();
    final cleaned = noteIds.where((id) => id.trim().isNotEmpty).toList();
    existing.addAll(cleaned);
    await prefs.setStringList(_shownNoteIdsKey, existing.toList());
    await addSeenNoteIds(cleaned);
  }

  /// Adds [noteIds] to the known inbox boundary set.
  static Future<void> addSeenNoteIds(List<String> noteIds) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getSeenNoteIds();
    existing.addAll(noteIds.where((id) => id.trim().isNotEmpty));
    await prefs.setStringList(_seenNoteIdsKey, existing.toList());
  }

  static Future<void> clearShownNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shownNoteIdsKey);
    await prefs.remove(_seenNoteIdsKey);
  }
}
