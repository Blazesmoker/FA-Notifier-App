import 'dart:async';

import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notes/data/manual_note_activity_store.dart';
import 'package:fanotifier/features/notes/data/note_unread_service.dart';
import 'package:fanotifier/features/notes/data/notes_first_run_preference.dart';
import 'package:fanotifier/features/notes/data/notes_unread_notification_service.dart';
import 'package:fanotifier/features/notes/data/notes_api_service.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';
import 'package:fanotifier/features/notes/domain/notes_inbox_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/features/notes/domain/notes_unread_notification_result.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

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
        notificationGateway: notificationGateway,
      ),
      noteUnreadService: noteUnreadService,
      refreshPort: refreshPort,
      activitiesPollingPort: activitiesPollingPort,
    );
  }

  const NotesRepositoryImpl({
    required this._notesApi,
    required this._firstRunPreference,
    required this._unreadNotificationService,
    required this._noteUnreadService,
    required this._refreshPort,
    required this._activitiesPollingPort,
  });

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
  NotesInboxSnapshot? get latestInboxSnapshot => _refreshPort.latestInboxSnapshot;

  @override
  int get inboxGeneration => _refreshPort.inboxGeneration;

  @override
  Future<NotesInboxSnapshot?> refreshInbox(
    Future<NotesInboxSnapshot?> Function() fallback,
  ) {
    return _refreshPort.refreshInbox(fallback);
  }

  @override
  void bindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler) {
    _refreshPort.bindInboxRefresh(handler);
  }

  @override
  void unbindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler) {
    _refreshPort.unbindInboxRefresh(handler);
  }

  @override
  void rememberInboxSnapshot(NotesInboxSnapshot snapshot) {
    _refreshPort.rememberInboxSnapshot(snapshot);
  }

  @override
  void setScreenVisible(bool visible) {
    _activitiesPollingPort.setNotesScreenVisible(visible);
  }

  @override
  Future<NotesPageResult> fetchPage({
    required String folder,
    required int page,
    bool requireFresh = false,
  }) async {
    Future<NotesPageResult> load() async {
      final snapshot =
          await _notesApi.fetchNotesPageSnapshot(folder: folder, page: page);
      return NotesPageResult(
        messages: snapshot.messages,
        topbarCounts: snapshot.topbarCounts,
        startedAtMilliseconds: snapshot.startedAtMilliseconds,
        completedAtMilliseconds: snapshot.completedAtMilliseconds,
      );
    }
    if (folder == 'inbox') {
      return _refreshPort.fetchInboxPage(
        load, page: page, requireFresh: requireFresh,
      );
    }
    return load();
  }

  @override
  Future<List<Message>> fetchMessages({
    required String folder,
    required int page,
  }) {
    return fetchPage(folder: folder, page: page).then((result) => result.messages);
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
    NoteActivitySnapshot? noteActivitySnapshot,
    int? startedAtMilliseconds,
  }) async {
    if (counts == null) return;
    await _activitiesPollingPort.handleExternalCounts(
      currentCounts: counts,
      resetTimer: true,
      source: source,
      noteActivitySnapshot: noteActivitySnapshot,
      startedAtMilliseconds: startedAtMilliseconds,
    );
  }

  @override
  Future<void> markAsUnreadWithoutRefetch(Message message) {
    return _noteUnreadService.markAsUnreadWithoutRefetch(message);
  }

  @override
  Future<void> reconcileManualUnread({
    required Set<String> noteIds,
    required NoteActivitySnapshot snapshot,
  }) async {
    final activityStore = ManualNoteActivityStore();
    await activityStore.reconcile(snapshot);
  }

  @override
  Future<void> applyManagementAction({
    required List<String> ids,
    required NotesFolder sourceFolder,
    required NoteManagementAction action,
  }) {
    return _notesApi.applyAction(
      ids: ids,
      sourceFolder: sourceFolder,
      action: action,
    );
  }
}
