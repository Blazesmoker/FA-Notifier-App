import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/shared/navigation/detachable_webview_route_registry.dart';

class ExternalLinkConfirmationDialog {
  static const _accentColor = Color(0xFFE09321);
  static const _troubleTicketsUrl =
      'https://www.furaffinity.net/controls/troubletickets/';
  static const _internetSafetyUrl =
      'https://www.furaffinity.net/fight_spam';

  static Future<String?> show(
    BuildContext context, {
    required String destinationUrl,
  }) async {
    final troubleTicketRecognizer = TapGestureRecognizer();
    final internetSafetyRecognizer = TapGestureRecognizer();
    try {
      return await DetachableWebViewRouteRegistry.withoutRouteDetach(
        () => showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            clipBehavior: Clip.antiAlias,
            titlePadding: EdgeInsets.zero,
            insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
            contentPadding: EdgeInsets.fromLTRB(
              16,
              Theme.of(context).useMaterial3 ? 16 : 20,
              16,
              24,
            ),
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
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Please confirm your destination and if you encounter something suspicious, please report it using a ',
                        ),
                        TextSpan(
                          text: 'Trouble Ticket',
                          style: const TextStyle(color: _accentColor),
                          recognizer: troubleTicketRecognizer
                            ..onTap = () => Navigator.of(dialogContext)
                                .pop(_troubleTicketsUrl),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Also, review our '),
                        TextSpan(
                          text: 'Internet Safety and Scamming',
                          style: const TextStyle(color: _accentColor),
                          recognizer: internetSafetyRecognizer
                            ..onTap = () => Navigator.of(dialogContext)
                                .pop(_internetSafetyUrl),
                        ),
                        const TextSpan(
                          text: ' page to keep yourself informed and safe while using the web!',
                        ),
                      ],
                    ),
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
        ),
      );
    } finally {
      troubleTicketRecognizer.dispose();
      internetSafetyRecognizer.dispose();
    }
  }
}
