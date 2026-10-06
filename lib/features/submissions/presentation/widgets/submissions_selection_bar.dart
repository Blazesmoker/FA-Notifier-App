import 'package:material_ui/material_ui.dart';

class SubmissionsSelectionBar extends StatelessWidget {
  const SubmissionsSelectionBar({
    super.key,
    required this.selectedCount,
    required this.isApplying,
    required this.deleteIcon,
    required this.onToggleAll,
    required this.onCancel,
    required this.onDelete,
  });

  final int selectedCount;
  final bool isApplying;
  final Widget deleteIcon;
  final VoidCallback onToggleAll;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const actionColor = Color(0xFFD64B4B);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: const Color(0xFF202020),
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel selection',
                onPressed: isApplying ? null : onCancel,
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              IconButton(
                tooltip: 'Select or deselect all displayed submissions',
                onPressed: isApplying ? null : onToggleAll,
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFE09321),
                disabledColor: const Color(0x59E09321),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: const Icon(Icons.library_add_check, size: 22),
              ),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$selectedCount selected',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed:
                    isApplying || selectedCount == 0 ? null : onDelete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: actionColor.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: deleteIcon,
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
