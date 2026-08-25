import 'package:material_ui/material_ui.dart';

typedef ProfileBulkSelectionLayoutChanged = void Function(
  bool active,
  double barHeight,
);

class ProfileBulkSelectionBar extends StatelessWidget {
  const ProfileBulkSelectionBar({
    super.key,
    required this.selectedCount,
    required this.actionLabel,
    required this.actionIcon,
    required this.destructive,
    required this.isApplying,
    required this.onCancel,
    required this.onApply,
  });

  final int selectedCount;
  final String actionLabel;
  final IconData actionIcon;
  final bool destructive;
  final bool isApplying;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final actionColor =
        destructive ? const Color(0xFFD64B4B) : const Color(0xFFE09321);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: const Color(0xFF202020),
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$selectedCount selected',
                  key: const ValueKey('profile-bulk-selection-count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('profile-bulk-selection-cancel'),
                onPressed: isApplying ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const ValueKey('profile-bulk-selection-action'),
                onPressed:
                    isApplying || selectedCount == 0 ? null : onApply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: actionColor.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: isApplying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(actionIcon, size: 20),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
