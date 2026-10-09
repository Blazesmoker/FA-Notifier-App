import 'package:dio/dio.dart';
import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:fanotifier/features/notes/data/background_note_unread_service.dart';
import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notes/data/notes_api_service.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_arrival_policy.dart';
import 'package:fanotifier/features/notes/domain/notes_unread_notification_result.dart';
import 'package:fanotifier/features/notifications/domain/stable_notification_id.dart';

class NotesUnreadNotificationService {
  const NotesUnreadNotificationService({
    required this._notesApi,
    required this._notificationGateway,
  });

  static const int _unreadRestoreMaxAttempts = 2;
  static const Duration _unreadRestoreAfterReadDelay = Duration(seconds: 1);
  static const Duration _unreadRestoreRetryDelay = Duration(seconds: 2);

  final NotesApiService _notesApi;
  final LocalNotificationGateway _notificationGateway;
  static Future<void> _handlingQueue = Future<void>.value();
  static final Set<CancelToken> _pendingTokens = {};

  static void cancelPending() {
    for (final token in _pendingTokens) {
      token.cancel();
    }
  }

  Future<bool> _restorePendingUnreadNotes(Set<String> noteIds, CancelToken token) async {
    for (var attempt = 1; attempt <= _unreadRestoreMaxAttempts; attempt++) {
      try {
        if (token.isCancelled) {
          return false;
        }
        final result = await restoreBackgroundNotesAsUnread(
          noteIds: noteIds,
          cancelToken: token,
        );
        if (result.success) {
          await MessageStorage.removePendingUnreadRestores(noteIds);
          return true;
        }
        if (!result.shouldRetryImmediately ||
            attempt == _unreadRestoreMaxAttempts) {
          return false;
        }
      } catch (_) {
        return false;
      }
      await Future<void>.delayed(_unreadRestoreRetryDelay);
    }
    return false;
  }

  Future<NotesUnreadNotificationResult> handle({
    required List<Message> fetchedInbox,
    required String? previousTopId,
    required bool didFirstRunSkip,
  }) {
    final token = CancelToken();
    _pendingTokens.add(token);
    final operation = _handlingQueue.then((_) => _handle(
      fetchedInbox: fetchedInbox,
      previousTopId: previousTopId,
      didFirstRunSkip: didFirstRunSkip,
      cancelToken: token,
    )).whenComplete(() {
      _pendingTokens.remove(token);
    });
    _handlingQueue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<NotesUnreadNotificationResult> _handle({
    required List<Message> fetchedInbox,
    required String? previousTopId,
    required bool didFirstRunSkip,
    required CancelToken cancelToken,
  }) async {
    String? latestTopId = previousTopId;
    if (fetchedInbox.isNotEmpty) {
      latestTopId = fetchedInbox.first.id;
    }

    try {
      final unread = fetchedInbox.where((m) => m.isUnread).toList();
      if (unread.isEmpty || !didFirstRunSkip || cancelToken.isCancelled) {
        return NotesUnreadNotificationResult(
          latestTopId: latestTopId,
          shownCount: 0,
        );
      }

      final shownIds = await MessageStorage.getShownNoteIds();
      final seenIds = await MessageStorage.getSeenNoteIds();
      final arrivals = NoteArrivalPolicy({...shownIds, ...seenIds});
      final pendingDeliveries = await MessageStorage.getPendingNoteDeliveries();
      final newUnread = unread.where((message) {
        return !shownIds.contains(message.id) &&
            (arrivals.isNewArrival(message.id) ||
                pendingDeliveries.containsKey(message.id));
      }).toList();

      final pendingRestoreIds = <String>{};
      final preparedNotes = <({Message message, String content})>[];
      for (final msg in newUnread) {
        try {
          if (cancelToken.isCancelled) {
            break;
          }
          await MessageStorage.queueNoteDelivery(noteId: msg.id, link: msg.link);
          await MessageStorage.addPendingUnreadRestore(
            noteId: msg.id,
            link: msg.link,
          );
          pendingRestoreIds.add(msg.id);
          final content = await _notesApi.fetchMessageContent(
            msg.link, cancelToken: cancelToken,
          );
          preparedNotes.add((message: msg, content: content));
        } catch (_) {}
      }

      if (pendingRestoreIds.isNotEmpty) {
        await Future<void>.delayed(_unreadRestoreAfterReadDelay);
        await _restorePendingUnreadNotes(pendingRestoreIds, cancelToken);
      }

      var shownCount = 0;
      for (final prepared in preparedNotes) {
        final msg = prepared.message;
        var claimed = false;
        var notificationShown = false;
        try {
          if (cancelToken.isCancelled) {
            break;
          }
          claimed = await MessageStorage.claimUnshownNoteId(msg.id);
          if (!claimed) continue;
          if (cancelToken.isCancelled) {
            break;
          }
          await _notificationGateway.showNotification(
            stableNotificationIdFromString(msg.id),
            'New Note from ${msg.sender}',
            prepared.content,
            'note_${msg.id}',
            'notes',
          );
          notificationShown = true;
          shownCount++;
          await MessageStorage.commitNoteDelivery(msg.id);
        } catch (_) {
          if (claimed && !notificationShown) {
            try {
              await MessageStorage.releaseClaimedNoteId(msg.id);
            } catch (_) {}
          }
        }
      }

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
