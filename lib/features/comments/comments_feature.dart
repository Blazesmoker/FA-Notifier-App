import 'package:FANotifier/features/comments/data/fa_edit_comment_service.dart';
import 'package:FANotifier/features/comments/data/submission_comment_service.dart';
import 'package:FANotifier/features/comments/domain/comment_edit_repository.dart';
import 'package:FANotifier/shared/fa/domain/submission_comment_repository.dart';

class CommentsFeature {
  const CommentsFeature._();

  static SubmissionCommentRepository createSubmissionCommentRepository() {
    return PostCommentService();
  }

  static CommentEditRepository createCommentEditRepository() {
    return AuthenticatedFaEditCommentService();
  }
}
