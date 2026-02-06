import 'package:flutter/material.dart';

/// Reusable dialog shown when user tries to leave a screen with unsaved text
/// (comments, notes, replies, shouts, etc.). Returns true if user chose to close.
class ConfirmCloseDialog {
  static const String _title = 'Confirm closing';
  static const String _message = 'Are you sure you want to close?';

  /// Shows the dialog. Returns [true] if user tapped "Close", [false] if "Cancel".
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_title),
        content: const Text(_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
