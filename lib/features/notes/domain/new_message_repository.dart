import 'package:fanotifier/features/notes/domain/new_message_send_result.dart';

typedef NewMessageRepositoryFactory = NewMessageRepository Function();

abstract interface class NewMessageRepository {
  Future<NewMessageSendResult> sendMessage({
    required String recipient,
    required String subject,
    required String message,
  });
}
