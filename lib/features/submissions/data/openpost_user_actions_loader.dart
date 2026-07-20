import 'package:fanotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:fanotifier/features/submissions/domain/openpost_page_response.dart';
import 'package:fanotifier/features/submissions/domain/openpost_user_actions_load_result.dart';

class OpenPostUserActionsLoader {
  const OpenPostUserActionsLoader();

  Future<OpenPostUserActionsLoadResult> load({
    required String url,
    required OpenPostPageFetcher fetch,
  }) async {
    final response = await fetch(url);
    if (response.statusCode != 200) {
      return OpenPostUserActionsLoadResult(statusCode: response.statusCode);
    }

    final decodedBody = decodeOpenPostResponseBody(response.bodyBytes);
    final document = await parseOpenPostHtmlDocument(decodedBody);
    return OpenPostUserActionsLoadResult(
      statusCode: response.statusCode,
      actions: parseOpenPostUserPageActions(document),
    );
  }
}
