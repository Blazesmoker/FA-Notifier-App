// lib/utils/message_storage.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingNoteUnreadRestore {
  const PendingNoteUnreadRestore({
    required this.noteId,
    required this.link,
    required this.createdAtMilliseconds,
  });

  final String noteId;
  final String link;
  final int createdAtMilliseconds;
}

class MessageStorage {
  static const String _shownNoteIdsKey = 'shown_note_ids';
  static const String _seenNoteIdsKey = 'seen_note_ids';
  static const String _pendingUnreadRestoresKey =
      'pending_note_unread_restores';
  static Future<void> _mutationQueue = Future<void>.value();

  static Set<String> _readIds(SharedPreferences prefs, String key) {
    return prefs
            .getStringList(key)
            ?.where((id) => id.trim().isNotEmpty)
            .toSet() ??
        <String>{};
  }

  static Map<String, PendingNoteUnreadRestore> _readPendingUnreadRestores(
    SharedPreferences prefs,
  ) {
    final encoded = prefs.getString(_pendingUnreadRestoresKey);
    if (encoded == null || encoded.isEmpty) {
      return <String, PendingNoteUnreadRestore>{};
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return <String, PendingNoteUnreadRestore>{};
      }

      final result = <String, PendingNoteUnreadRestore>{};
      for (final entry in decoded.entries) {
        final noteId = entry.key;
        final value = entry.value;
        if (noteId is! String || noteId.trim().isEmpty || value is! Map) {
          continue;
        }
        final link = value['link'];
        final createdAtMilliseconds = value['createdAtMilliseconds'];
        if (link is! String || createdAtMilliseconds is! int) {
          continue;
        }
        final cleaned = noteId.trim();
        result[cleaned] = PendingNoteUnreadRestore(
          noteId: cleaned,
          link: link,
          createdAtMilliseconds: createdAtMilliseconds,
        );
      }
      return result;
    } catch (_) {
      return <String, PendingNoteUnreadRestore>{};
    }
  }

  static Future<void> _writePendingUnreadRestores(
    SharedPreferences prefs,
    Map<String, PendingNoteUnreadRestore> pending,
  ) async {
    if (pending.isEmpty) {
      final removed = await prefs.remove(_pendingUnreadRestoresKey);
      if (!removed && prefs.containsKey(_pendingUnreadRestoresKey)) {
        throw StateError('Failed to clear pending note unread restores');
      }
      return;
    }

    final encoded = jsonEncode(<String, Object>{
      for (final entry in pending.entries)
        entry.key: <String, Object>{
          'link': entry.value.link,
          'createdAtMilliseconds': entry.value.createdAtMilliseconds,
        },
    });
    final saved = await prefs.setString(_pendingUnreadRestoresKey, encoded);
    if (!saved) {
      throw StateError('Failed to persist pending note unread restores');
    }
  }

  static Future<T> _enqueueMutation<T>(
    Future<T> Function() mutation,
  ) {
    final operation = _mutationQueue.then((_) => mutation());
    _mutationQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static Future<bool> claimUnshownNoteId(String noteId) {
    final cleaned = noteId.trim();
    if (cleaned.isEmpty) return Future<bool>.value(false);

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final shownIds = _readIds(prefs, _shownNoteIdsKey);
      if (shownIds.contains(cleaned)) return false;

      final seenIds = _readIds(prefs, _seenNoteIdsKey);
      shownIds.add(cleaned);
      seenIds.add(cleaned);
      await prefs.setStringList(_shownNoteIdsKey, shownIds.toList());
      await prefs.setStringList(_seenNoteIdsKey, seenIds.toList());
      return true;
    });
  }

  static Future<void> releaseClaimedNoteId(String noteId) {
    final cleaned = noteId.trim();
    if (cleaned.isEmpty) return Future<void>.value();

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final shownIds = _readIds(prefs, _shownNoteIdsKey);
      if (!shownIds.remove(cleaned)) return;
      final saved =
          await prefs.setStringList(_shownNoteIdsKey, shownIds.toList());
      if (!saved) {
        throw StateError('Failed to release claimed note ID');
      }
    });
  }

  static Future<PendingNoteUnreadRestore> addPendingUnreadRestore({
    required String noteId,
    required String link,
  }) {
    final cleaned = noteId.trim();
    if (cleaned.isEmpty) {
      return Future<PendingNoteUnreadRestore>.error(
        ArgumentError.value(noteId, 'noteId'),
      );
    }

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pending = _readPendingUnreadRestores(prefs);
      final existing = pending[cleaned];
      final restore = PendingNoteUnreadRestore(
        noteId: cleaned,
        link: link,
        createdAtMilliseconds: existing?.createdAtMilliseconds ??
            DateTime.now().millisecondsSinceEpoch,
      );
      pending[cleaned] = restore;
      await _writePendingUnreadRestores(prefs, pending);
      return restore;
    });
  }

  static Future<List<PendingNoteUnreadRestore>>
      getPendingUnreadRestores() async {
    await _mutationQueue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final result = _readPendingUnreadRestores(prefs).values.toList();
    result.sort(
      (a, b) => a.createdAtMilliseconds.compareTo(b.createdAtMilliseconds),
    );
    return result;
  }

  static Future<void> removePendingUnreadRestore(String noteId) {
    final cleaned = noteId.trim();
    if (cleaned.isEmpty) return Future<void>.value();

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pending = _readPendingUnreadRestores(prefs);
      if (pending.remove(cleaned) == null) return;
      await _writePendingUnreadRestores(prefs, pending);
    });
  }

  static Future<void> removePendingUnreadRestores(Iterable<String> noteIds) {
    final cleaned = noteIds
        .map((noteId) => noteId.trim())
        .where((noteId) => noteId.isNotEmpty)
        .toSet();
    if (cleaned.isEmpty) return Future<void>.value();

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pending = _readPendingUnreadRestores(prefs);
      final previousLength = pending.length;
      pending.removeWhere((noteId, _) => cleaned.contains(noteId));
      if (pending.length == previousLength) return;
      await _writePendingUnreadRestores(prefs, pending);
    });
  }

  /// Returns the set of note IDs that have already been shown in a notification.
  static Future<Set<String>> getShownNoteIds() async {
    await _mutationQueue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _readIds(prefs, _shownNoteIdsKey);
  }

  /// Returns note IDs that have appeared in a fetched inbox page.
  ///
  /// This is separate from [getShownNoteIds]: old unread notes from the first
  /// install run are "known" even when they should not produce notifications.
  static Future<Set<String>> getSeenNoteIds() async {
    await _mutationQueue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _readIds(prefs, _seenNoteIdsKey);
  }

  /// Adds [noteIds] to the “already shown” set so we don't show them again.
  static Future<void> addShownNoteIds(List<String> noteIds) {
    final cleaned = noteIds.where((id) => id.trim().isNotEmpty).toSet();
    if (cleaned.isEmpty) return Future<void>.value();

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final shownIds = _readIds(prefs, _shownNoteIdsKey)..addAll(cleaned);
      final seenIds = _readIds(prefs, _seenNoteIdsKey)..addAll(cleaned);
      await prefs.setStringList(_shownNoteIdsKey, shownIds.toList());
      await prefs.setStringList(_seenNoteIdsKey, seenIds.toList());
    });
  }

  /// Adds [noteIds] to the known inbox boundary set.
  static Future<void> addSeenNoteIds(List<String> noteIds) {
    final cleaned = noteIds.where((id) => id.trim().isNotEmpty).toSet();
    if (cleaned.isEmpty) return Future<void>.value();

    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final seenIds = _readIds(prefs, _seenNoteIdsKey)..addAll(cleaned);
      await prefs.setStringList(_seenNoteIdsKey, seenIds.toList());
    });
  }

  static Future<void> clearShownNoteIds() {
    return _enqueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shownNoteIdsKey);
      await prefs.remove(_seenNoteIdsKey);
      await prefs.remove(_pendingUnreadRestoresKey);
    });
  }
}
