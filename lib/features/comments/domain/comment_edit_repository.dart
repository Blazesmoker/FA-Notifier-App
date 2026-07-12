import 'package:FANotifier/features/comments/domain/comment_edit_models.dart';

typedef CommentEditRepositoryFactory = CommentEditRepository Function();

abstract interface class CommentEditRepository {
  Future<EditCommentLoadResult> loadEditCommentText({
    required String editLink,
  });

  Future<EditCommentSubmitResult> submitEditComment({
    required String editLink,
    required String updatedText,
    required bool requireFValue,
    required bool includeFValue,
    bool logFormDebug = false,
  });

  void close();
}
