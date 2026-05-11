class NewMessageSendResult {
  const NewMessageSendResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}
