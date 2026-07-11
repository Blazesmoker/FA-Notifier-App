import 'package:FANotifier/features/submissions/domain/openpost_models.dart';

enum OpenPostDetailsLoadStatus { httpFailure, matureWarning, success }

class OpenPostDetailsLoadResult {
  const OpenPostDetailsLoadResult({
    required this.status,
    this.statusCode,
    this.parsedPost,
    this.comments,
  });

  final OpenPostDetailsLoadStatus status;
  final int? statusCode;
  final OpenPostParseResult? parsedPost;
  final List<Map<String, dynamic>>? comments;
}
