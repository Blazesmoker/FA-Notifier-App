import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';

Widget buildMessageDetailHeader({
  required bool isClassic,
  required String folder,
  required String avatarUrl,
  required String sender,
  required String recipient,
  required String senderLink,
  required String recipientLink,
  required String sentDate,
  required TimeDisplayFormat timeFormat,
  required VoidCallback onAvatarTap,
  required VoidCallback onSenderTap,
  required VoidCallback onRecipientTap,
}) {
  return Row(
    children: [
      if (!isClassic)
        GestureDetector(
          onTap: onAvatarTap,
          child: Container(
            width: 60,
            height: 60,
            color: Colors.transparent,
            child: FaNetworkImage(
              'https:$avatarUrl',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Transform.scale(
                  scale: 1.05,
                  child: Image.asset(
                    'assets/images/defaultpic.gif',
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
        )
      else
        const SizedBox.shrink(),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sent by: ',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                folder == 'sent'
                    ? Text(
                        sender.isNotEmpty ? sender : 'Unknown sender',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      )
                    : InkWell(
                        onTap: senderLink.isNotEmpty ? onSenderTap : null,
                        child: Text(
                          sender.isNotEmpty ? sender : 'Unknown sender',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFFE09321),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'To: ',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                folder == 'sent' && recipientLink.isNotEmpty
                    ? InkWell(
                        onTap: onRecipientTap,
                        child: Text(
                          recipient.isNotEmpty
                              ? recipient
                              : 'Unknown recipient',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFFE09321),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    : Text(
                        recipient.isNotEmpty ? recipient : 'Unknown recipient',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Date: ${formatTimeInText(sentDate, format: timeFormat)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
