import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_group_section.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_widgets.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';

class FolderOverviewCard extends StatelessWidget {
  const FolderOverviewCard({
    super.key,
    required this.maximumFolders,
    required this.faPlusIconUri,
    required this.onFaPlus,
  });

  final int? maximumFolders;
  final Uri? faPlusIconUri;
  final VoidCallback? onFaPlus;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Folders can be combined into groups (creating a two-level hierarchy). It is possible to assign a submission into multiple folders. Deleting folders WILL NOT remove submissions assigned to it.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          SubmissionManagementShrinkableText(
            'Maximum Folders Allowed: ${maximumFolders?.toString() ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FaPlusPerkLink(
            text: 'Members get an additional increase to their max folder limit.',
            iconUri: faPlusIconUri,
            onTap: onFaPlus,
          ),
        ],
      ),
    );
  }
}

class GroupCreateCard extends StatelessWidget {
  const GroupCreateCard({
    super.key,
    required this.groups,
    required this.maximumGroups,
    required this.faPlusIconUri,
    required this.controller,
    required this.previousGroupId,
    required this.enabled,
    required this.canSubmit,
    required this.onPreviousChanged,
    required this.onCreate,
    required this.onFaPlus,
  });

  final List<FaManagedFolderGroup> groups;
  final int? maximumGroups;
  final Uri? faPlusIconUri;
  final TextEditingController controller;
  final String previousGroupId;
  final bool enabled;
  final bool canSubmit;
  final ValueChanged<String?> onPreviousChanged;
  final VoidCallback onCreate;
  final VoidCallback? onFaPlus;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeading('Folder Groups'),
          const SizedBox(height: 14),
          const SubmissionManagementShrinkableText(
            'Create New Folder Group',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Removing a Folder Group will not delete any folders it contains. Instead, the assigned folders will simply become un-grouped.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          SubmissionManagementShrinkableText(
            'Maximum Groups Allowed: ${maximumGroups?.toString() ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FaPlusPerkLink(
            text:
                'Members get an additional increase to their max folder group limit.',
            iconUri: faPlusIconUri,
            onTap: onFaPlus,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller,
            enabled: enabled,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              label: SubmissionManagementShrinkableText(
                'Folder Group name',
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onCreate(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('create-after-$previousGroupId-${groups.length}'),
            initialValue: previousGroupId,
            isExpanded: true,
            decoration: const InputDecoration(
              label: SubmissionManagementShrinkableText('Create after'),
            ),
            items: [
              const DropdownMenuItem(
                value: '0',
                child: SubmissionManagementShrinkableText(
                  '- the last group -',
                ),
              ),
              for (final group in groups)
                DropdownMenuItem(
                  value: group.id,
                  child: SubmissionManagementShrinkableText(group.name),
                ),
            ],
            onChanged: enabled ? onPreviousChanged : null,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: canSubmit ? onCreate : null,
            style: FilledButton.styleFrom(
              backgroundColor: managementAccent,
              foregroundColor: Colors.black,
            ),
            child: const SubmissionManagementShrinkableText('Create Group'),
          ),
        ],
      ),
    );
  }
}

class GroupRenameCard extends StatelessWidget {
  const GroupRenameCard({
    super.key,
    required this.group,
    required this.controller,
    required this.enabled,
    required this.canSubmit,
    required this.onRename,
  });

  final FaManagedFolderGroup group;
  final TextEditingController controller;
  final bool enabled;
  final bool canSubmit;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SubmissionManagementShrinkableText(
            'Rename Folder Group',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SubmissionManagementShrinkableText(
            group.name,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              label: SubmissionManagementShrinkableText('New group name'),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onRename(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: canSubmit ? onRename : null,
            style: OutlinedButton.styleFrom(foregroundColor: managementAccent),
            child: const SubmissionManagementShrinkableText('Rename Group'),
          ),
        ],
      ),
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.folderColors,
    required this.folders,
    required this.enabled,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onAddFolder,
    required this.onFolderMoveUp,
    required this.onFolderMoveDown,
    required this.onFolderEdit,
    required this.onFolderEditColor,
    required this.onFolderDelete,
    required this.onAddSubmissions,
    required this.onOpenGallery,
  });

  final FaManagedFolderGroup group;
  final Map<String, Color> folderColors;
  final List<FaManagedFolder> folders;
  final bool enabled;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddFolder;
  final ValueChanged<FaManagedFolder> onFolderMoveUp;
  final ValueChanged<FaManagedFolder> onFolderMoveDown;
  final ValueChanged<FaManagedFolder> onFolderEdit;
  final ValueChanged<FaManagedFolder> onFolderEditColor;
  final ValueChanged<FaManagedFolder> onFolderDelete;
  final ValueChanged<FaManagedFolder> onAddSubmissions;
  final ValueChanged<FaManagedFolder> onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_copy_outlined, color: managementAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Material(
                      color: managementAccent.withValues(alpha: 0.16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: const BorderSide(color: managementAccent),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: enabled ? onEdit : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: SubmissionManagementShrinkableText(
                            group.name,
                            maxLines: 1,
                            minFontSize: 6,
                            style: const TextStyle(
                              color: managementAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '(Group)',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            _MoveButtons(
              enabled: enabled,
              onUp: onMoveUp,
              onDown: onMoveDown,
            ),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? onEdit : null,
                style: _compactActionStyle(),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: enabled ? onAddFolder : null,
                style: _compactActionStyle(),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add Sub-Folder'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: enabled ? onDelete : null,
                style: _compactActionStyle(
                  foregroundColor: Colors.red,
                  borderColor: Colors.red.withValues(alpha: 0.65),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ],
    );
    if (folders.isEmpty) return ManagementCard(child: header);
    return RoundedGroupSection(
      key: ValueKey('folder-group-${group.id}'),
      header: header,
      nested: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < folders.length; index++) ...[
            FolderCard(
              folder: folders[index],
              color:
                  folderColors[folders[index].name] ?? fallbackFolderColor,
              enabled: enabled,
              nested: true,
              onMoveUp: () => onFolderMoveUp(folders[index]),
              onMoveDown: () => onFolderMoveDown(folders[index]),
              onEdit: () => onFolderEdit(folders[index]),
              onEditColor: () => onFolderEditColor(folders[index]),
              onDelete: () => onFolderDelete(folders[index]),
              onAddSubmissions: () => onAddSubmissions(folders[index]),
              onOpenGallery: () => onOpenGallery(folders[index]),
            ),
            if (index != folders.length - 1) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class FolderCard extends StatelessWidget {
  const FolderCard({
    super.key,
    required this.folder,
    required this.color,
    required this.enabled,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onEditColor,
    required this.onDelete,
    required this.onAddSubmissions,
    required this.onOpenGallery,
    this.nested = false,
  });

  final FaManagedFolder folder;
  final Color color;
  final bool enabled;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onEditColor;
  final VoidCallback onDelete;
  final VoidCallback onAddSubmissions;
  final VoidCallback onOpenGallery;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final buttonForeground =
        color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              nested ? Icons.subdirectory_arrow_right : Icons.folder_outlined,
              color: managementAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: _AdaptiveFolderColorControl(
                      name: folder.name,
                      color: color,
                      foregroundColor: buttonForeground,
                      onNameTap: !enabled || folder.galleryUri == null
                          ? null
                          : onOpenGallery,
                      onPaletteTap: enabled ? onEditColor : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '(Folder)',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            _MoveButtons(
              enabled: enabled,
              onUp: onMoveUp,
              onDown: onMoveDown,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32, top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubmissionManagementShrinkableText(
                '${folder.submissionCount} ${folder.submissionCount == 1 ? 'Submission' : 'Submissions'}',
                style: const TextStyle(color: Colors.white60),
              ),
              if (folder.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  folder.description!,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? onEdit : null,
                style: _compactActionStyle(),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: enabled ? onAddSubmissions : null,
                style: _compactActionStyle(),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add Submissions'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: enabled ? onDelete : null,
                style: _compactActionStyle(
                  foregroundColor: Colors.red,
                  borderColor: Colors.red.withValues(alpha: 0.65),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ],
    );
    if (nested) return content;
    return ManagementCard(child: content);
  }
}

class _AdaptiveFolderColorControl extends StatelessWidget {
  const _AdaptiveFolderColorControl({
    required this.name,
    required this.color,
    required this.foregroundColor,
    required this.onNameTap,
    required this.onPaletteTap,
  });

  static const EdgeInsets _namePadding = EdgeInsets.fromLTRB(8, 8, 8, 8);
  static const EdgeInsets _palettePadding = EdgeInsets.fromLTRB(6, 8, 8, 8);
  static const double _iconSize = 17;

  final String name;
  final Color color;
  final Color foregroundColor;
  final VoidCallback? onNameTap;
  final VoidCallback? onPaletteTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: foregroundColor,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: name, style: textStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final naturalNameWidth = textPainter.width + _namePadding.horizontal;
    final naturalNameHeight = textPainter.height + _namePadding.vertical;
    textPainter.dispose();
    final paletteWidth = _iconSize + _palettePadding.horizontal;
    final paletteHeight = _iconSize + _palettePadding.vertical;
    final height = naturalNameHeight > paletteHeight
        ? naturalNameHeight
        : paletteHeight;
    final naturalWidth = naturalNameWidth + paletteWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : naturalWidth;
        final width = naturalWidth.clamp(0.0, availableWidth).toDouble();
        final nameWidth = (width - paletteWidth)
            .clamp(0.0, naturalNameWidth)
            .toDouble();

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Tooltip(
                  message: 'Edit color',
                  child: Material(
                    color: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: foregroundColor.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onPaletteTap,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: _palettePadding,
                          child: Icon(
                            Icons.palette_outlined,
                            size: _iconSize,
                            color: foregroundColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: nameWidth,
                child: Material(
                  color: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: foregroundColor.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onNameTap,
                    child: Padding(
                      padding: _namePadding,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          style: textStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

ButtonStyle _compactActionStyle({
  Color? backgroundColor,
  Color? foregroundColor,
  Color? borderColor,
}) {
  return OutlinedButton.styleFrom(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    side: BorderSide(color: borderColor ?? const Color(0xFF5A5A5A)),
    minimumSize: Size.zero,
    padding: const EdgeInsets.all(12),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _MoveButtons extends StatelessWidget {
  const _MoveButtons({
    required this.enabled,
    required this.onUp,
    required this.onDown,
  });

  final bool enabled;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Move up',
          onPressed: enabled ? onUp : null,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Move down',
          onPressed: enabled ? onDown : null,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }
}
