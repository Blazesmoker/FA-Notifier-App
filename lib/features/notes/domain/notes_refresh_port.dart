import 'dart:async';
import 'package:fanotifier/features/notes/domain/notes_inbox_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';

abstract interface class NotesRefreshPort {
  Stream<void> get stream;

  void triggerRefresh();

  bool takePendingRefresh();

  NotesInboxSnapshot? get latestInboxSnapshot;

  int get inboxGeneration;

  Future<NotesPageResult> fetchInboxPage(
    Future<NotesPageResult> Function() load, {
    int page = 1,
    bool requireFresh = false,
  });

  Future<NotesInboxSnapshot?> refreshInbox(
    Future<NotesInboxSnapshot?> Function() fallback,
  );

  void bindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler);

  void unbindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler);

  void rememberInboxSnapshot(NotesInboxSnapshot snapshot);

  void clearInboxSnapshot();
}
