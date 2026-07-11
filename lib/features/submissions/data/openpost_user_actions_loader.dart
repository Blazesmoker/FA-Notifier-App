import 'package:FANotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:FANotifier/features/submissions/domain/openpost_models.dart';
import 'package:http/http.dart';

class OpenPostUserActionsLoadResult {
  const OpenPostUserActionsLoadResult({
    required this.statusCode,
    this.actions,
  });

  final int statusCode;
  final OpenPostUserPageActions? actions;
}

class OpenPostUserActionsLoader {
  const OpenPostUserActionsLoader();

  Future<OpenPostUserActionsLoadResult> load({
    required String url,
    required Future<Response> Function(String url) fetch,
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
