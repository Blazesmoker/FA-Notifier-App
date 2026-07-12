import 'package:FANotifier/features/notifications/data/fa_notification_cookie_header_provider.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_media_repository.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_shout_repository.dart';
import 'package:FANotifier/features/notifications/data/fa_notifications_page_parser.dart';
import 'package:FANotifier/features/notifications/data/fa_notifications_remote_data_source.dart';
import 'package:FANotifier/features/notifications/data/notification_removal_request_builder.dart';
import 'package:FANotifier/features/notifications/data/simple_semaphore.dart';
import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:FANotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:FANotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';
import 'package:FANotifier/features/notifications/domain/fa_notifications_repository.dart';

class FaNotificationsRepositoryImpl implements FaNotificationsRepository {
  factory FaNotificationsRepositoryImpl({
    FaNotificationsRemoteDataSource? remoteDataSource,
    FaNotificationShoutRepository? shoutRepository,
    FaNotificationMediaRepository? mediaRepository,
  }) {
    final semaphore = SimpleSemaphore(3);
    const cookieHeaderProvider = FaNotificationCookieHeaderProvider();
    return FaNotificationsRepositoryImpl._(
      remoteDataSource:
          remoteDataSource ?? FaNotificationsRemoteDataSource(),
      shoutRepository: shoutRepository ??
          FaNotificationShoutRepository(
            semaphore: semaphore,
            cookieHeaderProvider: cookieHeaderProvider,
          ),
      mediaRepository: mediaRepository ??
          FaNotificationMediaRepository(
            semaphore: semaphore,
            cookieHeaderProvider: cookieHeaderProvider,
          ),
    );
  }

  const FaNotificationsRepositoryImpl._({
    required FaNotificationsRemoteDataSource remoteDataSource,
    required FaNotificationShoutRepository shoutRepository,
    required FaNotificationMediaRepository mediaRepository,
  })  : _remoteDataSource = remoteDataSource,
        _shoutRepository = shoutRepository,
        _mediaRepository = mediaRepository;

  final FaNotificationsRemoteDataSource _remoteDataSource;
  final FaNotificationShoutRepository _shoutRepository;
  final FaNotificationMediaRepository _mediaRepository;

  @override
  Future<FaNotificationsPageSnapshot> fetchNotifications({
    required Map<String, int> messageBarCounts,
    required FaNotificationsPageParserState parserState,
  }) async {
    final session = await _remoteDataSource.createAuthenticatedSession();
    final response = await _remoteDataSource.fetchNotificationsPage(session);
    return parseFaNotificationsPage(
      response.htmlBody,
      messageBarCounts: messageBarCounts,
      sideState: parserState,
    );
  }

  @override
  Future<FaNotificationsMutationSession> createMutationSession() async {
    return _FaNotificationsMutationSession(
      await _remoteDataSource.createAuthenticatedSession(),
    );
  }

  @override
  Future<int?> removeSelected(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
    required Iterable<String> itemIds,
  }) async {
    final response = await _remoteDataSource.removeSelected(
      _remoteSession(session),
      formAction: formAction,
      fields: buildSelectedNotificationRemovalFields(
        sectionTitle,
        itemIds,
      ),
    );
    return response.statusCode;
  }

  @override
  Future<int?> nukeSection(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
  }) async {
    final fields = buildNotificationNukeFields(sectionTitle);
    if (fields.isEmpty) {
      throw Exception('Unknown section type for nuking: $sectionTitle');
    }
    final response = await _remoteDataSource.nukeSection(
      _remoteSession(session),
      formAction: formAction,
      fields: fields,
    );
    return response.statusCode;
  }

  @override
  Future<int?> removeAllFromSection(
    FaNotificationsMutationSession session, {
    required String sectionTitle,
    required String formAction,
    required Iterable<String> itemIds,
  }) async {
    final response = await _remoteDataSource.removeAllFromSection(
      _remoteSession(session),
      formAction: formAction,
      fields: buildSelectedNotificationRemovalFields(
        sectionTitle,
        itemIds,
      ),
    );
    return response.statusCode;
  }

  @override
  bool canRemoveAllFromSection(String sectionTitle) {
    return buildSelectedNotificationRemovalFields(
      sectionTitle,
      const <String>[],
    ).isNotEmpty;
  }

  @override
  Future<List<Shout>> fetchProfileShouts(
    String username, {
    bool forceRefresh = false,
  }) {
    return _shoutRepository.fetchProfileShouts(
      username,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<List<Shout>> fetchMsgCenterShouts() {
    return _shoutRepository.fetchMsgCenterShouts();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMsgOthersShouts() {
    return _shoutRepository.fetchMsgOthersShouts();
  }

  @override
  Future<String?> fetchAvatarUrl(String username) {
    return _mediaRepository.fetchAvatarUrl(username);
  }

  @override
  Future<String?> fetchSubmissionPreview(String submissionId) {
    return _mediaRepository.fetchSubmissionPreview(submissionId);
  }

  FaNotificationsRemoteSession _remoteSession(
    FaNotificationsMutationSession session,
  ) {
    if (session is! _FaNotificationsMutationSession) {
      throw ArgumentError.value(session, 'session');
    }
    return session.remoteSession;
  }
}

class _FaNotificationsMutationSession
    implements FaNotificationsMutationSession {
  const _FaNotificationsMutationSession(this.remoteSession);

  final FaNotificationsRemoteSession remoteSession;
}
