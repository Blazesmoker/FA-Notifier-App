import 'dart:async';

import 'package:FANotifier/features/notes/data/message_storage.dart';
import 'package:FANotifier/features/notes/data/note_unread_service.dart';
import 'package:FANotifier/features/notes/data/notes_first_run_preference.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/features/notes/data/notes_unread_notification_service.dart';
import 'package:FANotifier/features/notes/data/notesscreen_api_service.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notes/domain/notes_page_result.dart';
import 'package:FANotifier/features/notes/domain/notes_unread_notification_result.dart';
import 'package:FANotifier/features/notifications/data/fa_activities_polling_service.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

class NotesRepository {
  factory NotesRepository.create() {
    final notesApi = NotesApiService();
    final noteUnreadService = NoteUnreadService();
    return NotesRepository(
      notesApi: notesApi,
      firstRunPreference: NotesFirstRunPreference(),
      unreadNotificationService: NotesUnreadNotificationService(
        notesApi: notesApi,
        noteUnreadService: noteUnreadService,
      ),
      noteUnreadService: noteUnreadService,
    );
  }

  const NotesRepository({
    required NotesApiService notesApi,
    required NotesFirstRunPreference firstRunPreference,
    required NotesUnreadNotificationService unreadNotificationService,
    required NoteUnreadService noteUnreadService,
  })  : _notesApi = notesApi,
        _firstRunPreference = firstRunPreference,
        _unreadNotificationService = unreadNotificationService,
        _noteUnreadService = noteUnreadService;

  final NotesApiService _notesApi;
  final NotesFirstRunPreference _firstRunPreference;
  final NotesUnreadNotificationService _unreadNotificationService;
  final NoteUnreadService _noteUnreadService;

  Stream<void> get refreshStream => NotesRefreshService().stream;

  bool takePendingRefresh() {
    return NotesRefreshService().takePendingRefresh();
  }

  void setScreenVisible(bool visible) {
    FaActivitiesPollingService().setNotesScreenVisible(visible);
  }

  Future<NotesPageResult> fetchPage({
    required String folder,
    required int page,
  }) async {
    final snapshot =
        await _notesApi.fetchNotesPageSnapshot(folder: folder, page: page);
    return NotesPageResult(
      messages: snapshot.messages,
      topbarCounts: snapshot.topbarCounts,
    );
  }

  Future<List<Message>> fetchMessages({
    required String folder,
    required int page,
  }) {
    return _notesApi.fetchNotesPage(folder: folder, page: page);
  }

  Future<bool> loadDidFirstRunSkip() {
    return _firstRunPreference.loadDidFirstRunSkip();
  }

  Future<void> setFirstRunSkipDone() {
    return _firstRunPreference.setFirstRunSkipDone();
  }

  Future<Set<String>> getShownNoteIds() {
    return MessageStorage.getShownNoteIds();
  }

  Future<Set<String>> getSeenNoteIds() {
    return MessageStorage.getSeenNoteIds();
  }

  Future<void> markUnreadMessagesAsShown(List<Message> messages) async {
    final unreadIds = messages
        .where((message) => message.isUnread)
        .map((message) => message.id)
        .toList();
    if (unreadIds.isNotEmpty) {
      await MessageStorage.addShownNoteIds(unreadIds);
    }
  }

  Future<void> markMessagesAsSeen(List<Message> messages) async {
    final ids = messages.map((message) => message.id).toList();
    if (ids.isNotEmpty) {
      await MessageStorage.addSeenNoteIds(ids);
    }
  }

  Future<NotesUnreadNotificationResult> handleNewUnreadMessages({
    required List<Message> fetchedInbox,
    required String? previousTopId,
    required bool didFirstRunSkip,
  }) {
    return _unreadNotificationService.handle(
      fetchedInbox: fetchedInbox,
      previousTopId: previousTopId,
      didFirstRunSkip: didFirstRunSkip,
    );
  }

  Future<void> handleTopbarCounts(
    NotificationCounts? counts, {
    required String source,
  }) async {
    if (counts == null) return;
    await FaActivitiesPollingService().handleExternalCounts(
      currentCounts: counts,
      resetTimer: true,
      source: source,
    );
  }

  Future<void> markAsUnreadWithoutRefetch(Message message) {
    return _noteUnreadService.markAsUnreadWithoutRefetch(message);
  }

  Future<void> moveNotesToTrash({
    required List<String> ids,
    required String folder,
  }) {
    return _notesApi.moveNotesToTrash(ids: ids, folder: folder);
  }
}
