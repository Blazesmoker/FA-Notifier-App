import 'package:material_ui/material_ui.dart';

const EdgeInsets _profileBulkSelectionBarSafeAreaMinimum =
    EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0);
const EdgeInsets _profileBulkSelectionBarContentPadding =
    EdgeInsets.fromLTRB(8.0, 10.0, 12.0, 10.0);
const EdgeInsets _profileBulkSelectionBarCancelPadding =
    EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0);
const EdgeInsets _profileBulkSelectionBarSelectAllPadding =
    EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0);
const EdgeInsets _profileBulkSelectionBarActionButtonPadding =
    EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 0.0);

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
    required this.onToggleAll,
    required this.onCancel,
    required this.onApply,
  });

  final int selectedCount;
  final String actionLabel;
  final IconData actionIcon;
  final bool destructive;
  final bool isApplying;
  final VoidCallback onToggleAll;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final actionColor =
        destructive ? const Color(0xFFD64B4B) : const Color(0xFFE09321);
    return SafeArea(
      minimum: _profileBulkSelectionBarSafeAreaMinimum,
      child: Material(
        color: const Color(0xFF202020),
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: _profileBulkSelectionBarContentPadding,
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('profile-bulk-selection-cancel'),
                tooltip: 'Cancel selection',
                onPressed: isApplying ? null : onCancel,
                padding: _profileBulkSelectionBarCancelPadding,
                icon: const Icon(Icons.close, color: Colors.red),
              ),
              IconButton(
                key: const ValueKey('profile-bulk-selection-toggle-all'),
                tooltip: 'Select or deselect all displayed items',
                onPressed: isApplying ? null : onToggleAll,
                padding: _profileBulkSelectionBarSelectAllPadding,
                color: const Color(0xFFE09321),
                disabledColor: const Color(0x59E09321),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: Icon(
                  selectedCount == 0
                      ? Icons.library_add_check_outlined
                      : Icons.library_add_check,
                  size: 22,
                ),
              ),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$selectedCount selected',
                    key: const ValueKey('profile-bulk-selection-count'),
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
                key: const ValueKey('profile-bulk-selection-action'),
                onPressed:
                    isApplying || selectedCount == 0 ? null : onApply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: actionColor.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white54,
                  padding: _profileBulkSelectionBarActionButtonPadding,
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
