import 'package:material_ui/material_ui.dart';

List<PopupMenuEntry<String>> buildJournalActionMenu({
  required bool isOwner,
}) {
  return <PopupMenuEntry<String>>[
    const PopupMenuItem<String>(value: 'share', child: Text('Share')),
    if (isOwner)
      const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
    if (isOwner)
      PopupMenuItem<String>(
        value: 'delete',
        child: const Text('Delete', style: TextStyle(color: Colors.red)),
      ),
    const PopupMenuItem<String>(value: 'translate', child: Text('Translate')),
  ];
}

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
