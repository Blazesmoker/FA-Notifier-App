import 'dart:typed_data';

typedef SubmissionPageFetcher = Future<SubmissionPageResponse> Function(String url);

class SubmissionPageResponse {
  const SubmissionPageResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.bodyBytes,
    required this.isHtml,
    required this.submissionNotFound,
    required this.matureContentWarning,
    required this.oldMatureImageError,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Uint8List bodyBytes;
  final bool isHtml;
  final bool submissionNotFound;
  final bool matureContentWarning;
  final bool oldMatureImageError;
}
