import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_styles.dart';

class ManageSubmissionsBottomOverlay extends StatelessWidget {
  const ManageSubmissionsBottomOverlay({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.detailsVisible,
    required this.currentPage,
    required this.enabled,
    required this.newerEnabled,
    required this.olderEnabled,
    required this.deleteEnabled,
    required this.onToggleDetails,
    required this.onToggleAll,
    required this.onNewer,
    required this.onOlder,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final bool detailsVisible;
  final int currentPage;
  final bool enabled;
  final bool newerEnabled;
  final bool olderEnabled;
  final bool deleteEnabled;
  final VoidCallback onToggleDetails;
  final VoidCallback onToggleAll;
  final VoidCallback onNewer;
  final VoidCallback onOlder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: managementActionsFadeColors,
                  stops: managementActionsFadeStops,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Padding(
            padding: const EdgeInsets.only(
              top: managementActionsFadeCeilingAboveButtons,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 52,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final counterWidth = (constraints.maxWidth - 120)
                          .clamp(72.0, 160.0)
                          .toDouble();
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Material(
                              color: managementCard,
                              elevation: 8,
                              shape: const CircleBorder(
                                side: BorderSide(color: Color(0xFF3A3A3A)),
                              ),
                              child: IconButton(
                                tooltip: detailsVisible
                                    ? 'Hide titles and folder names'
                                    : 'Show titles and folder names',
                                onPressed: enabled ? onToggleDetails : null,
                                icon: Icon(
                                  detailsVisible
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: enabled && detailsVisible
                                      ? managementAccent
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: counterWidth,
                            child: Material(
                              color: managementCard,
                              elevation: 8,
                              shape: const StadiumBorder(
                                side: BorderSide(color: Color(0xFF3A3A3A)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: enabled ? onToggleAll : null,
                                child: SizedBox(
                                  height: 48,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child:
                                            SubmissionManagementShrinkableText(
                                          '$selectedCount selected',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: selectedCount == 0
                                                ? Colors.white70
                                                : managementAccent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        selectedCount == 0
                                            ? Icons.library_add_check_outlined
                                            : Icons.library_add_check,
                                        size: 22,
                                        color: !enabled
                                            ? Colors.grey
                                            : selectedCount == 0
                                                ? Colors.white70
                                                : Colors.white,
                                        semanticLabel: allSelected
                                            ? 'Deselect all'
                                            : 'Select all',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Material(
                              color: managementCard,
                              elevation: 8,
                              shape: const CircleBorder(
                                side: BorderSide(color: Color(0xFF3A3A3A)),
                              ),
                              child: IconButton(
                                tooltip: 'Delete submissions',
                                onPressed:
                                    enabled && deleteEnabled ? onDelete : null,
                                icon: Icon(
                                  Icons.delete_forever_rounded,
                                  color: enabled && deleteEnabled
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _PaginationControls(
                  currentPage: currentPage,
                  newerEnabled: newerEnabled,
                  olderEnabled: olderEnabled,
                  onNewer: onNewer,
                  onOlder: onOlder,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.currentPage,
    required this.newerEnabled,
    required this.olderEnabled,
    required this.onNewer,
    required this.onOlder,
  });

  final int currentPage;
  final bool newerEnabled;
  final bool olderEnabled;
  final VoidCallback onNewer;
  final VoidCallback onOlder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: newerEnabled ? onNewer : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: managementCard,
              disabledBackgroundColor: managementCard,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : const BorderSide(color: managementAccent),
              ),
            ),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const SubmissionManagementShrinkableText('Newer'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SubmissionManagementShrinkableText(
            'Page $currentPage',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: managementAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: olderEnabled ? onOlder : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: managementCard,
              disabledBackgroundColor: managementCard,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : const BorderSide(color: managementAccent),
              ),
            ),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const SubmissionManagementShrinkableText('Older'),
          ),
        ),
      ],
    );
  }
}
