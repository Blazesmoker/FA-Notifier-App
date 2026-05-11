class NoteReplyContext {
  const NoteReplyContext({
    required this.recipient,
    required this.isClassicTheme,
  });

  final String recipient;
  final bool isClassicTheme;
}

class NoteReplySendResult {
  const NoteReplySendResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}
