import 'dart:async';

import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';
import 'package:fanotifier/features/notes/domain/notes_unread_notification_result.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

typedef NotesRepositoryFactory = NotesRepository Function();

abstract class NotesRepository {
  Stream<void> get refreshStream;

  bool takePendingRefresh();

  void setScreenVisible(bool visible);

  Future<NotesPageResult> fetchPage({
    required String folder,
    required int page,
  });

  Future<List<Message>> fetchMessages({
    required String folder,
    required int page,
  });

  Future<bool> loadDidFirstRunSkip();

  Future<void> setFirstRunSkipDone();

  Future<Set<String>> getShownNoteIds();

  Future<Set<String>> getSeenNoteIds();

  Future<void> markUnreadMessagesAsShown(List<Message> messages);

  Future<void> markMessagesAsSeen(List<Message> messages);

  Future<NotesUnreadNotificationResult> handleNewUnreadMessages({
    required List<Message> fetchedInbox,
    required String? previousTopId,
    required bool didFirstRunSkip,
  });

  Future<void> handleTopbarCounts(
    NotificationCounts? counts, {
    required String source,
  });

  Future<void> markAsUnreadWithoutRefetch(Message message);

  Future<void> moveNotesToTrash({
    required List<String> ids,
    required String folder,
  });
}
