import 'package:material_ui/material_ui.dart';

PopupMenuItem<T> buildMessageDetailMenuItem<T>({
  required T action,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  return PopupMenuItem<T>(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, color: enabled ? Colors.white : Colors.grey, size: 21),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}
