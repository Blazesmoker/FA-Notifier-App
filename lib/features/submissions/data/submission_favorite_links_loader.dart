import 'package:fanotifier/features/submissions/data/submission_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/submission_html_parser.dart';
import 'package:fanotifier/shared/fa/parsing/submission_favorite_links_parser.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_links_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';

class SubmissionFavoriteLinksLoader {
  const SubmissionFavoriteLinksLoader({
    required this._cookieService,
  });

  final SubmissionCookieService _cookieService;

  Future<SubmissionFavoriteLinksLoadResult> load({
    required String url,
    required SubmissionPageFetcher fetch,
  }) async {
    if (!await _cookieService.hasAuthCookies()) {
      return const SubmissionFavoriteLinksLoadResult(
        status: SubmissionFavoriteLinksLoadStatus.missingAuth,
      );
    }

    final response = await fetch(url);
    if (response.statusCode != 200) {
      return SubmissionFavoriteLinksLoadResult(
        status: SubmissionFavoriteLinksLoadStatus.httpFailure,
        statusCode: response.statusCode,
      );
    }

    final decodedBody = decodeSubmissionFavoriteLinksBody(
      response.body,
      response.bodyBytes,
    );
    final document = await parseSubmissionHtmlDocument(decodedBody);
    final links = parseSubmissionFavoriteLinksFromDocument(
      document,
      includeClassicFallback: true,
    );
    return SubmissionFavoriteLinksLoadResult(
      status: SubmissionFavoriteLinksLoadStatus.success,
      favoriteLink:
          links.hasFavUrl ? toRelativeFavoriteUrl(links.favUrl) : null,
      unfavoriteLink:
          links.hasUnfavUrl ? toRelativeFavoriteUrl(links.unfavUrl) : null,
    );
  }
}
