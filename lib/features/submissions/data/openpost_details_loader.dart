import 'package:FANotifier/features/submissions/data/openpost_api_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:FANotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_page_response.dart';

class OpenPostDetailsLoader {
  const OpenPostDetailsLoader();

  Future<OpenPostDetailsLoadResult> load({
    required String url,
    required OpenPostPageFetcher fetch,
  }) async {
    final response = await fetch(url);
    if (response.statusCode != 200) {
      return OpenPostDetailsLoadResult(
        status: OpenPostDetailsLoadStatus.httpFailure,
        statusCode: response.statusCode,
      );
    }

    final decodedBody = decodeOpenPostResponseBody(response.bodyBytes);
    final document = await parseOpenPostHtmlDocument(decodedBody);
    if (hasMatureRatingNotice(document)) {
      return const OpenPostDetailsLoadResult(
        status: OpenPostDetailsLoadStatus.matureWarning,
      );
    }

    return OpenPostDetailsLoadResult(
      status: OpenPostDetailsLoadStatus.success,
      parsedPost: OpenPostApiService.parsePostDocument(document),
      comments: OpenPostApiService.parseComments(document),
    );
  }
}
