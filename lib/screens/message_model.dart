// lib/hotel_booking/message_model.dart

class Message {
  late final String id;
  final String subject;
  final String sender;
  final String date;
  final String link;
  bool isUnread;

  Message({
    required this.id,
    required this.subject,
    required this.sender,
    required this.date,
    required this.link,
    required this.isUnread,
  });
}
