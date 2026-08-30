import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';
import 'package:fanotifier/features/notifications/domain/notification_removal_outcome.dart';

abstract interface class FaNotificationsMutationSession {}

abstract interface class FaNotificationsRepository {
  Future<FaNotificationsPageSnapshot> fetchNotifications({
    required Map<String, int> messageBarCounts,
    required FaNotificationsPageParserState parserState,
  });

  Future<FaNotificationsMutationSession> createMutationSession();

  Future<NotificationRemovalRequestOutcome> removeSelected(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
    required Iterable<String> itemIds,
  });

  Future<NotificationRemovalRequestOutcome> nukeSection(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
  });

  Future<NotificationRemovalRequestOutcome> removeAllFromSection(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
    required Iterable<String> itemIds,
  });

  bool canRemoveAllFromSection(String sectionTitle);

  Future<List<Shout>> fetchProfileShouts(
    String username, {
    bool forceRefresh = false,
  });

  Future<List<Shout>> fetchMsgCenterShouts();

  Future<List<Map<String, dynamic>>> fetchMsgOthersShouts();

  Future<String?> fetchAvatarUrl(String username);

  Future<String?> fetchSubmissionPreview(String submissionId);
}
