String extractClassicSubmissionCommentReplyId(String input) {
  final regex = RegExp(r'/replyto/submission/(\d+)/');
  final match = regex.firstMatch(input);
  return match != null ? match.group(1)! : input;
}
