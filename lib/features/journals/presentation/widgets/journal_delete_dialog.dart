import 'package:material_ui/material_ui.dart';

Widget buildJournalDeleteDialog(
  BuildContext ctx, {
  required String titleForDialog,
}) {
  return AlertDialog(
    title: const Text('Confirm deletion'),
    content: Text('Are you sure you want to delete journal "$titleForDialog"?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(false),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        child: const Text('Delete', style: TextStyle(color: Colors.red)),
      ),
    ],
  );
}
