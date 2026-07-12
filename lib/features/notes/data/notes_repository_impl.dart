import 'dart:async';

import 'package:FANotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:FANotifier/features/notes/data/message_storage.dart';
import 'package:FANotifier/features/notes/data/note_unread_service.dart';
import 'package:FANotifier/features/notes/data/notes_first_run_preference.dart';
import 'package:FANotifier/features/notes/data/notes_unread_notification_service.dart';
import 'package:FANotifier/features/notes/data/notesscreen_api_service.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notes/domain/notes_page_result.dart';
import 'package:FANotifier/features/notes/domain/notes_repository.dart';
import 'package:FANotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:FANotifier/features/notes/domain/notes_unread_notification_result.dart';
import 'package:FANotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:FANotifier/shared/fa/domain/notification_counts.dart';

class NotesRepositoryImpl implements NotesRepository {
  factory NotesRepositoryImpl.create({
    required NotesRefreshPort refreshPort,
    required FaActivitiesPollingPort activitiesPollingPort,
    required LocalNotificationGateway notificationGateway,
  }) {
    final notesApi = NotesApiService();
    final noteUnreadService = NoteUnreadService();
    return NotesRepositoryImpl(
      notesApi: notesApi,
      firstRunPreference: NotesFirstRunPreference(),
      unreadNotificationService: NotesUnreadNotificationService(
        notesApi: notesApi,
        noteUnreadService: noteUnreadService,
        notificationGateway: notificationGateway,
      ),
      noteUnreadService: noteUnreadService,
      refreshPort: refreshPort,
      activitiesPollingPort: activitiesPollingPort,
    );
  }

  const NotesRepositoryImpl({
    required NotesApiService notesApi,
    required NotesFirstRunPreference firstRunPreference,
    required NotesUnreadNotificationService unreadNotificationService,
    required NoteUnreadService noteUnreadService,
    required NotesRefreshPort refreshPort,
    required FaActivitiesPollingPort activitiesPollingPort,
  })  : _notesApi = notesApi,
        _firstRunPreference = firstRunPreference,
        _unreadNotificationService = unreadNotificationService,
        _noteUnreadService = noteUnreadService,
        _refreshPort = refreshPort,
        _activitiesPollingPort = activitiesPollingPort;

  final NotesApiService _notesApi;
  final NotesFirstRunPreference _firstRunPreference;
  final NotesUnreadNotificationService _unreadNotificationService;
  final NoteUnreadService _noteUnreadService;
  final NotesRefreshPort _refreshPort;
  final FaActivitiesPollingPort _activitiesPollingPort;

  @override
  Stream<void> get refreshStream => _refreshPort.stream;

  @override
  bool takePendingRefresh() {
    return _refreshPort.takePendingRefresh();
  }

  @override
  void setScreenVisible(bool visible) {
    _activitiesPollingPort.setNotesScreenVisible(visible);
  }

  @override
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

  @override
  Future<List<Message>> fetchMessages({
    required String folder,
    required int page,
  }) {
    return _notesApi.fetchNotesPage(folder: folder, page: page);
  }

  @override
  Future<bool> loadDidFirstRunSkip() {
    return _firstRunPreference.loadDidFirstRunSkip();
  }

  @override
  Future<void> setFirstRunSkipDone() {
    return _firstRunPreference.setFirstRunSkipDone();
  }

  @override
  Future<Set<String>> getShownNoteIds() {
    return MessageStorage.getShownNoteIds();
  }

  @override
  Future<Set<String>> getSeenNoteIds() {
    return MessageStorage.getSeenNoteIds();
  }

  @override
  Future<void> markUnreadMessagesAsShown(List<Message> messages) async {
    final unreadIds = messages
        .where((message) => message.isUnread)
        .map((message) => message.id)
        .toList();
    if (unreadIds.isNotEmpty) {
      await MessageStorage.addShownNoteIds(unreadIds);
    }
  }

  @override
  Future<void> markMessagesAsSeen(List<Message> messages) async {
    final ids = messages.map((message) => message.id).toList();
    if (ids.isNotEmpty) {
      await MessageStorage.addSeenNoteIds(ids);
    }
  }

  @override
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

  @override
  Future<void> handleTopbarCounts(
    NotificationCounts? counts, {
    required String source,
  }) async {
    if (counts == null) return;
    await _activitiesPollingPort.handleExternalCounts(
      currentCounts: counts,
      resetTimer: true,
      source: source,
    );
  }

  @override
  Future<void> markAsUnreadWithoutRefetch(Message message) {
    return _noteUnreadService.markAsUnreadWithoutRefetch(message);
  }

  @override
  Future<void> moveNotesToTrash({
    required List<String> ids,
    required String folder,
  }) {
    return _notesApi.moveNotesToTrash(ids: ids, folder: folder);
  }
}
