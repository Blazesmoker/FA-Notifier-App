import 'package:fanotifier/features/submissions/data/submission_html_parser.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';
import 'package:fanotifier/features/submissions/domain/submission_user_actions_load_result.dart';

class SubmissionUserActionsLoader {
  const SubmissionUserActionsLoader();

  Future<SubmissionUserActionsLoadResult> load({
    required String url,
    required SubmissionPageFetcher fetch,
  }) async {
    final response = await fetch(url);
    if (response.statusCode != 200) {
      return SubmissionUserActionsLoadResult(statusCode: response.statusCode);
    }

    final decodedBody = decodeSubmissionResponseBody(response.bodyBytes);
    final document = await parseSubmissionHtmlDocument(decodedBody);
    return SubmissionUserActionsLoadResult(
      statusCode: response.statusCode,
      actions: parseSubmissionUserPageActions(document),
    );
  }
}
