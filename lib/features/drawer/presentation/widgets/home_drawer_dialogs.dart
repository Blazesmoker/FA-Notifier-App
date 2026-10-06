import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

Widget buildDrawerOpenLinkDialog(
  BuildContext context, {
  required TextEditingController controller,
  required void Function(BuildContext, String) onOpen,
}) {
  return AlertDialog(
    title: const Text('Open Link'),
    content: TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        labelText: 'Enter link',
        labelStyle: TextStyle(color: Colors.white),
        floatingLabelStyle: TextStyle(color: Colors.white),
      ),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (buttonContext, value, child) {
          return TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFE09321),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final String url = controller.text.trim();
              if (url.isEmpty) {
                final clipboardData =
                    await Clipboard.getData(Clipboard.kTextPlain);
                if (!buttonContext.mounted) return;

                final text = clipboardData?.text;
                if (text == null ||
                    text.isEmpty ||
                    controller.text.trim().isNotEmpty) {
                  return;
                }

                controller.value = TextEditingValue(
                  text: text,
                  selection: TextSelection.collapsed(offset: text.length),
                );
                return;
              }

              // Close dialog first, then handle the link
              Navigator.of(context).pop();

              onOpen(context, url);
            },
            child: Text(value.text.trim().isEmpty ? 'Paste' : 'Ok'),
          );
        },
      ),
    ],
  );
}

Widget buildDrawerModeConfirmationDialog(
  BuildContext dialogContext, {
  required String dialogMessage,
  required Color yesColor,
  required bool dontAskAgain,
  required ValueChanged<bool?> onChanged,
}) {
  return Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Confirm Mode Switch",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(dialogMessage, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(backgroundColor: Colors.white),
                child: const Text("No", style: TextStyle(color: Colors.black)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFE09321),
                ),
                child: Text("Yes", style: TextStyle(color: yesColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              CheckboxTheme(
                data: CheckboxThemeData(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(width: 1, color: Colors.white),
                  fillColor: WidgetStateProperty.resolveWith<Color>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFE09321);
                    }
                    return Colors.transparent;
                  }),
                  checkColor: WidgetStateProperty.all(Colors.white),
                ),
                child: Checkbox(value: dontAskAgain, onChanged: onChanged),
              ),
              const SizedBox(width: 1),
              const Text("Don't ask anymore", style: TextStyle(fontSize: 14)),
            ],
          ),
        ],
      ),
    ),
  );
}
