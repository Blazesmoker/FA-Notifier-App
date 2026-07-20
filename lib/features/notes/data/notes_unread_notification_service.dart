import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notes/data/note_unread_service.dart';
import 'package:fanotifier/features/notes/data/notesscreen_api_service.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/notes_unread_notification_result.dart';

class NotesUnreadNotificationService {
  const NotesUnreadNotificationService({
    required NotesApiService notesApi,
    required NoteUnreadService noteUnreadService,
    required LocalNotificationGateway notificationGateway,
  })  : _notesApi = notesApi,
        _noteUnreadService = noteUnreadService,
        _notificationGateway = notificationGateway;

  final NotesApiService _notesApi;
  final NoteUnreadService _noteUnreadService;
  final LocalNotificationGateway _notificationGateway;

  Future<NotesUnreadNotificationResult> handle({
    required List<Message> fetchedInbox,
    required String? previousTopId,
    required bool didFirstRunSkip,
  }) async {
    String? latestTopId = previousTopId;
    if (fetchedInbox.isNotEmpty) {
      latestTopId = fetchedInbox.first.id;
    }

    try {
      final unread = fetchedInbox.where((m) => m.isUnread).toList();
      if (unread.isEmpty || !didFirstRunSkip) {
        return NotesUnreadNotificationResult(
          latestTopId: latestTopId,
          shownCount: 0,
        );
      }

      final shownIds = await MessageStorage.getShownNoteIds();
      final unreadNotShown =
          unread.where((m) => !shownIds.contains(m.id)).toList();
      if (unreadNotShown.isEmpty) {
        return NotesUnreadNotificationResult(
          latestTopId: latestTopId,
          shownCount: 0,
        );
      }

      int anchorIndex = -1;
      if (previousTopId != null) {
        anchorIndex = fetchedInbox.indexWhere((m) => m.id == previousTopId);
      }

      final Set<String>? eligibleIds;
      if (previousTopId == null) {
        eligibleIds = null;
      } else {
        final nextEligibleIds = <String>{};
        if (anchorIndex > 0) {
          for (var i = 0; i < anchorIndex; i++) {
            nextEligibleIds.add(fetchedInbox[i].id);
          }
        }
        eligibleIds = nextEligibleIds;
      }

      final List<Message> newUnread;
      if (eligibleIds == null) {
        newUnread = unreadNotShown;
      } else if (eligibleIds.isEmpty) {
        newUnread = <Message>[];
      } else {
        final nonNullEligibleIds = eligibleIds;
        newUnread = unreadNotShown
            .where((m) => nonNullEligibleIds.contains(m.id))
            .toList();
      }

      var shownCount = 0;
      for (final msg in newUnread) {
        try {
          final content = await _notesApi.fetchMessageContent(msg.link);
          await _notificationGateway.showNotification(
            msg.id.hashCode,
            'New Note from ${msg.sender}',
            content,
            'note_${msg.id}',
            'notes',
          );
          shownCount++;
          await _noteUnreadService.markAsUnreadWithoutRefetch(msg);
        } catch (_) {}
      }

      await MessageStorage.addShownNoteIds(
        unreadNotShown.map((m) => m.id).toList(),
      );
      return NotesUnreadNotificationResult(
        latestTopId: latestTopId,
        shownCount: shownCount,
      );
    } catch (_) {
      return NotesUnreadNotificationResult(
        latestTopId: latestTopId,
        shownCount: 0,
      );
    }
  }
}
