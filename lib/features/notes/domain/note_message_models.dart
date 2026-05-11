class NoteMessageDetails {
  const NoteMessageDetails({
    required this.isClassic,
    required this.messageId,
    required this.pageNumber,
    required this.subject,
    required this.sender,
    required this.recipient,
    required this.sentDate,
    required this.avatarUrl,
    required this.messageContent,
    required this.messageContentHtml,
    required this.senderLink,
    required this.senderUsername,
    required this.recipientLink,
    required this.recipientUsername,
  });

  final bool isClassic;
  final String messageId;
  final int pageNumber;
  final String subject;
  final String sender;
  final String recipient;
  final String sentDate;
  final String avatarUrl;
  final String messageContent;
  final String messageContentHtml;
  final String senderLink;
  final String senderUsername;
  final String recipientLink;
  final String recipientUsername;
}

class NoteMessageFetchResult {
  const NoteMessageFetchResult({
    this.details,
    this.statusCode,
    this.redirected = false,
  });

  final NoteMessageDetails? details;
  final int? statusCode;
  final bool redirected;
}
