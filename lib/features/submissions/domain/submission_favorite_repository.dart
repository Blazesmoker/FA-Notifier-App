import 'package:fanotifier/shared/fa/domain/submission_favorite_links.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';

abstract interface class SubmissionFavoriteRepository {
  Future<bool> executePostWithRetry(String url);

  Future<FaContentManagementResult> removeFavorites(
    Set<String> favoriteIds,
  );

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
