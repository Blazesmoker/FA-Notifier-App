import 'package:fanotifier/features/submissions/data/favorite_service.dart';
import 'package:fanotifier/features/submissions/data/submission_favorite_details_service.dart';
import 'package:fanotifier/shared/fa/domain/submission_favorite_links.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';

class SubmissionFavoriteRepositoryImpl
    implements SubmissionFavoriteRepository {
  SubmissionFavoriteRepositoryImpl({
    FavoriteService? favoriteService,
    SubmissionFavoriteDetailsService favoriteDetailsService =
        const SubmissionFavoriteDetailsService(),
  })  : _favoriteService = favoriteService ?? FavoriteService(),
        _favoriteDetailsService = favoriteDetailsService;

  final FavoriteService _favoriteService;
  final SubmissionFavoriteDetailsService _favoriteDetailsService;

  @override
  Future<bool> executePostWithRetry(String url) {
    return _favoriteService.executePostWithRetry(url);
  }

  @override
  Future<SubmissionFavoriteLinks?> fetchLinksForSubmissionId({
    required String submissionId,
    required Future<String> Function() cookieHeaderProvider,
  }) {
    return _favoriteDetailsService.fetchLinksForSubmissionId(
      submissionId: submissionId,
      cookieHeaderProvider: cookieHeaderProvider,
    );
  }

  @override
  Future<SubmissionFavoriteLinks?> fetchLinksForPostUrl({
    required String postUrl,
    required Future<String> Function() cookieHeaderProvider,
    String? debugPostLabel,
  }) {
    return _favoriteDetailsService.fetchLinksForPostUrl(
      postUrl: postUrl,
      cookieHeaderProvider: cookieHeaderProvider,
      debugPostLabel: debugPostLabel,
    );
  }
}
