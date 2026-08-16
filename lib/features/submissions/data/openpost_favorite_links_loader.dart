import 'package:fanotifier/features/submissions/data/openpost_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:fanotifier/shared/fa/parsing/submission_favorite_links_parser.dart';
import 'package:fanotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_page_response.dart';

class OpenPostFavoriteLinksLoader {
  const OpenPostFavoriteLinksLoader({
    required this._cookieService,
  });

  final OpenPostCookieService _cookieService;

  Future<OpenPostFavoriteLinksLoadResult> load({
    required String url,
    required OpenPostPageFetcher fetch,
  }) async {
    if (!await _cookieService.hasAuthCookies()) {
      return const OpenPostFavoriteLinksLoadResult(
        status: OpenPostFavoriteLinksLoadStatus.missingAuth,
      );
    }

    final response = await fetch(url);
    if (response.statusCode != 200) {
      return OpenPostFavoriteLinksLoadResult(
        status: OpenPostFavoriteLinksLoadStatus.httpFailure,
        statusCode: response.statusCode,
      );
    }

    final decodedBody = decodeOpenPostFavoriteLinksBody(
      response.body,
      response.bodyBytes,
    );
    final document = await parseOpenPostHtmlDocument(decodedBody);
    final links = parseSubmissionFavoriteLinksFromDocument(
      document,
      includeClassicFallback: true,
    );
    return OpenPostFavoriteLinksLoadResult(
      status: OpenPostFavoriteLinksLoadStatus.success,
      favoriteLink:
          links.hasFavUrl ? toRelativeFavoriteUrl(links.favUrl) : null,
      unfavoriteLink:
          links.hasUnfavUrl ? toRelativeFavoriteUrl(links.unfavUrl) : null,
    );
  }
}
