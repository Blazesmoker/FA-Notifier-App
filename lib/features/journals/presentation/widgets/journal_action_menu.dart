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
