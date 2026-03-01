import 'package:flutter/material.dart';

/// Reusable dialog shown when user tries to leave a screen with unsaved text
/// (comments, notes, replies, shouts, etc.). Returns true if user chose to close.
class ConfirmCloseDialog {
  static const String _defaultTitle = 'Confirm closing';
  static const String _defaultMessage = 'Are you sure you want to close?';

  /// Shows the dialog. Returns [true] if user tapped "Close", [false] if "Cancel".
  static Future<bool> show(
    BuildContext context, {
    String title = _defaultTitle,
    String message = _defaultMessage,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
