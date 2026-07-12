class EditCommentLoadResult {
  const EditCommentLoadResult({
    this.textarea,
    this.errorMessage,
  });

  final String? textarea;
  final String? errorMessage;
}

class EditCommentSubmitResult {
  const EditCommentSubmitResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

class FaEditCommentFormData {
  const FaEditCommentFormData({
    required this.action,
    required this.commentId,
    required this.csrfKey,
    this.fValue,
  });

  final String action;
  final String commentId;
  final String csrfKey;
  final String? fValue;
}
