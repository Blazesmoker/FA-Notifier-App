import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:FANotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:FANotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';

abstract interface class FaNotificationsMutationSession {}

abstract interface class FaNotificationsRepository {
  Future<FaNotificationsPageSnapshot> fetchNotifications({
    required Map<String, int> messageBarCounts,
    required FaNotificationsPageParserState parserState,
  });

  Future<FaNotificationsMutationSession> createMutationSession();

  Future<int?> removeSelected(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
    required Iterable<String> itemIds,
  });

  Future<int?> nukeSection(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
  });

  Future<int?> removeAllFromSection(
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
