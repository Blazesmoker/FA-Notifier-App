abstract interface class SubmissionCommentRepository {
  Future<bool> submitComment({
    required String message,
    required String submissionId,
  });

  String? resolveReplyId({
    required String replyLink,
    required String? commentId,
    required bool isClassic,
  });

  Future<bool> submitReply({
    required String message,
    required String submissionId,
    required String? commentId,
    required bool isClassic,
  });
}
