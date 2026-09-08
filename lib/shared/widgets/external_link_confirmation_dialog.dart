import 'package:material_ui/material_ui.dart';

class ExternalLinkConfirmationDialog {
  static const _accentColor = Color(0xFFE09321);
  static const _troubleTicketsUrl =
      'https://www.furaffinity.net/controls/troubletickets/';
  static const _internetSafetyUrl =
      'https://www.furaffinity.net/fight_spam';

  static Future<String?> show(
    BuildContext context, {
    required String destinationUrl,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        title: Container(
          width: double.infinity,
          color: _accentColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: const Text(
            'ATTENTION',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are leaving Fur Affinity for the below URL:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                destinationUrl,
                style: const TextStyle(color: _accentColor),
              ),
              const SizedBox(height: 18),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Please confirm your destination and if you encounter something suspicious, please report it using a ',
                  ),
                  InkWell(
                    onTap: () => Navigator.of(dialogContext)
                        .pop(_troubleTicketsUrl),
                    child: const Text(
                      'Trouble Ticket',
                      style: TextStyle(color: _accentColor),
                    ),
                  ),
                  const Text('.'),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Also, review our '),
                  InkWell(
                    onTap: () => Navigator.of(dialogContext)
                        .pop(_internetSafetyUrl),
                    child: const Text(
                      'Internet Safety and Scamming',
                      style: TextStyle(color: _accentColor),
                    ),
                  ),
                  const Text(
                    ' page to keep yourself informed and safe while using the web!',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(destinationUrl),
            style: TextButton.styleFrom(foregroundColor: _accentColor),
            child: const Text('Continue to site'),
          ),
        ],
      ),
    );
  }
}
