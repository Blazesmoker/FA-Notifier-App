class NoteReplyForm {
  NoteReplyForm({
    required this.action,
    required this.documentUri,
    required Map<String, String> hiddenFields,
  }) : hiddenFields = Map<String, String>.unmodifiable(hiddenFields);

  final Uri action;
  final Uri documentUri;
  final Map<String, String> hiddenFields;
}

class NoteReplyContext {
  const NoteReplyContext({
    required this.recipient,
    required this.isClassicTheme,
    this.form,
  });

  final String recipient;
  final bool isClassicTheme;
  final NoteReplyForm? form;
}

class NoteReplySendResult {
  const NoteReplySendResult({
    required this.success,
    this.errorMessage,
    this.retryAfterSeconds,
    this.replyContext,
    this.requiresContextRefresh = false,
  });

  final bool success;
  final String? errorMessage;
  final int? retryAfterSeconds;
  final NoteReplyContext? replyContext;
  final bool requiresContextRefresh;
}
