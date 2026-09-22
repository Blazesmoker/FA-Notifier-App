import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/notes/data/background_inbox_service.dart';
import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notes/domain/note_arrival_policy.dart';

class ManualNoteActivityStore {
  static const _key = 'manual_note_activity_state_v1';
  static Future<void> _queue = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.catchError((_) {}).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> registerManualUnread(String noteId) {
    return registerManualUnreadBatch([noteId]);
  }

  Future<void> registerManualUnreadBatch(Iterable<String> noteIds) {
    return registerManualAction(noteIds);
  }

  Future<void> registerManualAction(Iterable<String> noteIds) {
    final selectedIds = noteIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    return _serialized(() async {
      if (selectedIds.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      var state = _read(prefs);
      if (state == null) {
        final shown = await MessageStorage.getShownNoteIds();
        final seen = await MessageStorage.getSeenNoteIds();
        await prefs.reload();
        state = _read(prefs) ??
            _ManualNoteActivityState(
              knownIds: {...shown, ...seen},
              pendingIds: {},
              notBeforeMilliseconds: DateTime.now().millisecondsSinceEpoch,
              baselineReady: (prefs.getBool('did_first_run_skip') ?? false) &&
                  (shown.isNotEmpty || seen.isNotEmpty),
            );
      }
      state.notBeforeMilliseconds = DateTime.now().millisecondsSinceEpoch;
      state.knownIds.addAll(selectedIds);
      state.pendingIds.removeAll(selectedIds);
      await _save(prefs, state);
      await MessageStorage.addShownNoteIds(selectedIds.toList());
    });
  }

  Future<void> finishManualAction() {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final state = _read(prefs);
      if (state == null) return;
      state.notBeforeMilliseconds = DateTime.now().millisecondsSinceEpoch;
      await _save(prefs, state);
    });
  }

  Future<NoteActivitySnapshot?> fetchSnapshotIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (_read(prefs) == null) return null;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final snapshot = await BackgroundInboxService().fetchSnapshot(
      shownNoteIds: await MessageStorage.getShownNoteIds(),
      seenNoteIds: await MessageStorage.getSeenNoteIds(),
    );
    if (snapshot.topbarCounts == null) {
      throw StateError('No valid note activity snapshot');
    }
    return NoteActivitySnapshot(
      messages: snapshot.messages,
      startedAtMilliseconds: startedAt,
      unreadCount: snapshot.topbarCounts!.notes,
    );
  }

  Future<Set<String>?> reconcile(NoteActivitySnapshot? snapshot) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final state = _read(prefs);
      if (state == null) return null;
      if (snapshot != null &&
          snapshot.startedAtMilliseconds >= state.notBeforeMilliseconds) {
        final restoring = await MessageStorage.getPendingUnreadRestores();
        _observe(
          state,
          snapshot,
          allowNewNotes: state.baselineReady &&
              (prefs.getBool('did_first_run_skip') ?? false),
          temporarilyReadIds: restoring.map((note) => note.noteId).toSet(),
        );
        state.notBeforeMilliseconds = snapshot.startedAtMilliseconds;
        state.baselineReady = prefs.getBool('did_first_run_skip') ?? false;
        await _save(prefs, state);
      }
      return {...state.pendingIds};
    });
  }

  Future<void> acknowledge({Set<String>? noteIds}) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final state = _read(prefs);
      if (state == null) return;
      if (noteIds == null) {
        state.pendingIds.clear();
      } else {
        state.pendingIds.removeAll(noteIds);
      }
      await _save(prefs, state);
    });
  }

  Future<void> dispatchActivity({
    required Set<String>? noteIds,
    required Future<void> Function() dispatch,
  }) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final state = _read(prefs);
      if ((state == null && noteIds != null) ||
          (state != null &&
              (noteIds == null ||
                  noteIds.isEmpty ||
                  !state.pendingIds.containsAll(noteIds)))) {
        throw StateError('Note activity decision changed before dispatch');
      }
      await dispatch();
    });
  }

  void _observe(
    _ManualNoteActivityState state,
    NoteActivitySnapshot snapshot, {
    required bool allowNewNotes,
    required Set<String> temporarilyReadIds,
  }) {
    if (snapshot.unreadCount == 0 && temporarilyReadIds.isEmpty) {
      state.pendingIds.clear();
    }
    final arrivals = NoteArrivalPolicy(state.knownIds);
    for (final message in snapshot.messages) {
      if (message.id.isEmpty) continue;
      if (allowNewNotes &&
          arrivals.isNewArrival(message.id) &&
          (message.isUnread || temporarilyReadIds.contains(message.id))) {
        state.pendingIds.add(message.id);
      }
      if (!message.isUnread && !temporarilyReadIds.contains(message.id)) {
        state.pendingIds.remove(message.id);
      }
    }
    state.knownIds.addAll(snapshot.messages.map((message) => message.id));
  }

  _ManualNoteActivityState? _read(SharedPreferences prefs) {
    final encoded = prefs.getString(_key);
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      return _ManualNoteActivityState(
        knownIds: (value['knownIds'] as List).cast<String>().toSet(),
        pendingIds: (value['pendingIds'] as List).cast<String>().toSet(),
        notBeforeMilliseconds: value['notBeforeMilliseconds'] as int,
        baselineReady: value['baselineReady'] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(
    SharedPreferences prefs,
    _ManualNoteActivityState state,
  ) async {
    final saved = await prefs.setString(_key, jsonEncode({
      'knownIds': state.knownIds.toList(),
      'pendingIds': state.pendingIds.toList(),
      'notBeforeMilliseconds': state.notBeforeMilliseconds,
      'baselineReady': state.baselineReady,
    }));
    if (!saved) throw StateError('Failed to save manual note activity state');
  }
}

class _ManualNoteActivityState {
  _ManualNoteActivityState({
    required this.knownIds,
    required this.pendingIds,
    required this.notBeforeMilliseconds,
    required this.baselineReady,
  });

  final Set<String> knownIds;
  final Set<String> pendingIds;
  int notBeforeMilliseconds;
  bool baselineReady;
}
