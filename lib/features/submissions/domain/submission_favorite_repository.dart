import 'package:FANotifier/shared/fa/domain/submission_favorite_links.dart';

abstract interface class SubmissionFavoriteRepository {
  Future<bool> executePostWithRetry(String url);

  Future<SubmissionFavoriteLinks?> fetchLinksForSubmissionId({
    required String submissionId,
    required Future<String> Function() cookieHeaderProvider,
  });

  Future<SubmissionFavoriteLinks?> fetchLinksForPostUrl({
    required String postUrl,
    required Future<String> Function() cookieHeaderProvider,
    String? debugPostLabel,
  });
}
