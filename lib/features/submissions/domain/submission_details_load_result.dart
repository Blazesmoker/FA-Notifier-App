import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';

enum SubmissionDetailsLoadStatus { httpFailure, matureWarning, success }

class SubmissionDetailsLoadResult {
  const SubmissionDetailsLoadResult({
    required this.status,
    this.statusCode,
    this.parsedPost,
    this.comments,
  });

  final SubmissionDetailsLoadStatus status;
  final int? statusCode;
  final SubmissionParseResult? parsedPost;
  final List<Map<String, dynamic>>? comments;
}
