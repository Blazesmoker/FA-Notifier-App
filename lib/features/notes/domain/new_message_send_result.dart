class NewMessageSendResult {
  const NewMessageSendResult({
    required this.success,
    this.message,
    this.retryAfterSeconds,
  });

  final bool success;
  final String? message;
  final int? retryAfterSeconds;
}
