import 'package:fanotifier/features/submissions/data/submission_document_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_html_parser.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';

class SubmissionDetailsLoader {
  const SubmissionDetailsLoader();

  Future<SubmissionDetailsLoadResult> load({
    required String url,
    required SubmissionPageFetcher fetch,
  }) async {
    final response = await fetch(url);
    if (response.statusCode != 200) {
      return SubmissionDetailsLoadResult(
        status: SubmissionDetailsLoadStatus.httpFailure,
        statusCode: response.statusCode,
      );
    }

    final decodedBody = decodeSubmissionResponseBody(response.bodyBytes);
    final document = await parseSubmissionHtmlDocument(decodedBody);
    if (hasMatureRatingNotice(document)) {
      return const SubmissionDetailsLoadResult(
        status: SubmissionDetailsLoadStatus.matureWarning,
      );
    }

    return SubmissionDetailsLoadResult(
      status: SubmissionDetailsLoadStatus.success,
      parsedPost: SubmissionDocumentParser.parsePostDocument(document),
      comments: SubmissionDocumentParser.parseComments(document),
    );
  }
}
