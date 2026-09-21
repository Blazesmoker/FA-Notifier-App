import 'widgets/submission_management_dialogs.dart';
import 'manage_submissions_controller.dart';
import 'dart:math' as math;

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/manage_submission_folders_screen.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/manage_submissions_bottom_overlay.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_image_preview.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_selection_tile.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

enum _SubmissionActionDialog {
  assignExisting,
  assignNew,
  unassign,
  move,
}

class ManageSubmissionsScreen extends StatefulWidget {
  const ManageSubmissionsScreen({
    super.key,
    this.initialNavigationAction,
  });

  final FaManagementFormAction? initialNavigationAction;

  static Route<bool> route({
    FaManagementFormAction? initialNavigationAction,
  }) {
    return MaterialPageRoute<bool>(
      settings: const AnalyticsRouteSettings(AppScreens.manageSubmissions),
      builder: (_) => ManageSubmissionsScreen(
        initialNavigationAction: initialNavigationAction,
      ),
    );
  }

  @override
  State<ManageSubmissionsScreen> createState() =>
      _ManageSubmissionsScreenState();
}

class _ManageSubmissionsScreenState extends State<ManageSubmissionsScreen> {
  late final SubmissionManagementRepository _repository;
  late final ManageSubmissionsController _controller;
  Set<String> get _selectedIds => _controller.selectedIds;
  Map<String, Color> get _folderColors => _controller.folderColors;

  FaSubmissionManagementPage? get _page => _controller.page;
  Object? get _loadError => _controller.loadError;
  bool get _loading => _controller.loading;
  bool get _mutating => _controller.mutating;
  bool _allowPop = false;
  bool _titlesEnabled = true;
  bool get _changed => _controller.changed;
  bool _openingFolder = false;
  bool _preparingPreview = false;

  bool get _dirty => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SubmissionManagementRepository>();
    _controller = ManageSubmissionsController(
      repository: _repository,
      folderColorRepository: context.read<SubmissionFolderColorRepository>(),
      isMounted: () => mounted,
      updateState: (update) => setState(update),
      confirmDelete: _confirmDelete,
      showMessage: _showMessage,
    );
    _controller.load(
      navigationAction: widget.initialNavigationAction,
      resetDrafts: true,
    );
  }

  Future<void> _requestClose() async {
    if (_mutating) return;
    if (!_dirty) {
      Navigator.of(context).pop(_changed);
      return;
    }
    final discard = await ConfirmCloseDialog.show(
      context,
      title: 'Discard changes?',
      message: 'Your selection has not been applied. Discard it?',
    );
    if (!mounted || !discard) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_changed);
    });
  }

  Future<bool> _confirmDiscardForNavigation(String destination) async {
    if (!_dirty) return true;
    return await ConfirmCloseDialog.show(
      context,
      title: 'Discard changes?',
      message:
          'Your selection has not been applied. Discard it and open $destination?',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _navigateToPage(Uri? uri) async {
    if (uri == null || _mutating || _loading) return;
    final discard = await _confirmDiscardForNavigation('this page');
    if (!mounted || !discard) return;
    await _controller.load(uri: uri, resetDrafts: true);
  }

  Future<void> _openFolders() async {
    if (_mutating) return;
    final result = await Navigator.of(context).push<ManageSubmissionFoldersResult>(
      ManageSubmissionFoldersScreen.route(),
    );
    if (!mounted) return;
    final action = result?.openSubmissionsAction;
    if (action != null) {
      final discard = await _confirmDiscardForNavigation(
        'the selected folder',
      );
      if (!mounted || !discard) return;
      await _controller.load(navigationAction: action, resetDrafts: true);
      return;
    }
    await _controller.load(uri: _page?.sourceUri, resetDrafts: false);
  }

  Future<void> _openActionDialog(_SubmissionActionDialog action) async {
    final page = _page;
    if (page == null || _selectedIds.isEmpty || _mutating) return;
    switch (action) {
      case _SubmissionActionDialog.assignExisting:
        await _showAssignExistingDialog(page);
        return;
      case _SubmissionActionDialog.assignNew:
        await _showAssignNewDialog(page);
        return;
      case _SubmissionActionDialog.unassign:
        await _showUnassignDialog(page);
        return;
      case _SubmissionActionDialog.move:
        await _showMoveDialog(page);
        return;
    }
  }

  Future<void> _showAssignExistingDialog(
    FaSubmissionManagementPage page,
  ) async {
    final selected = _controller.selectedSubmissions(page);
    final folderId = await showAssignExistingSubmissionFolderDialog(
      context: context,
      page: page,
      selected: selected,
      folderColors: () => _folderColors,
    );
    if (!mounted || folderId == null) return;
    await _controller.applyAction(
      SubmissionManagementActionType.assignToFolder,
      folderId: folderId,
    );
  }

  Future<void> _showAssignNewDialog(FaSubmissionManagementPage page) async {
    final selected = _controller.selectedSubmissions(page);
    final newFolderName = await showAssignNewSubmissionFolderDialog(
      context: context,
      page: page,
      selected: selected,
      folderColors: () => _folderColors,
    );
    if (!mounted || newFolderName == null) return;
    await _controller.applyAction(
      SubmissionManagementActionType.createFolder,
      newFolderName: newFolderName,
    );
  }

  Future<void> _showUnassignDialog(FaSubmissionManagementPage page) async {
    final selected = _controller.selectedSubmissions(page);
    final confirmed = await showUnassignSubmissionFolderDialog(
      context: context,
      page: page,
      selected: selected,
      folderColors: () => _folderColors,
    );
    if (!mounted || !confirmed) return;
    await _controller.applyAction(
      SubmissionManagementActionType.unassignFromFolders,
    );
  }

  Future<void> _showMoveDialog(FaSubmissionManagementPage page) async {
    final selected = _controller.selectedSubmissions(page);
    final action = await showMoveSubmissionsDialog(
      context: context,
      page: page,
      selected: selected,
      folderColors: () => _folderColors,
    );
    if (!mounted || action == null) return;
    await _controller.applyAction(action);
  }

  Future<bool> _confirmDelete(FaSubmissionManagementPage page) async {
    if (_selectedIds.isEmpty) {
      _showMessage('Select at least one submission.', error: true);
      return false;
    }
    final selected = _controller.selectedSubmissions(page);
    return await showDeleteSubmissionsDialog(
      context: context,
      page: page,
      selected: selected,
      folderColors: () => _folderColors,
    );
  }

  void _showMessage(
    String message, {
    bool success = false,
    bool warning = false,
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? Colors.green.shade700
            : warning
                ? Colors.orange.shade800
                : error
                    ? Colors.red.shade700
                    : null,
      ),
    );
  }

  Future<void> _openSubmission(FaManagedSubmission submission) async {
    await handleFALink(context, submission.postUri.toString());
  }

  Future<void> _showSubmissionPreview(
    FaManagedSubmission submission,
    int thumbnailCacheWidth,
  ) async {
    if (!mounted || _mutating || _preparingPreview) return;
    _preparingPreview = true;
    try {
      final aspect = submission.width / submission.height;
      final thumbnailCacheHeight = math
          .max(1, (thumbnailCacheWidth / aspect).ceil())
          .toInt();
      final baseImageProvider = await faNetworkImageProvider(
        submission.thumbnailUri.toString(),
      );
      if (!mounted) return;
      final previewImageProvider = ResizeImage.resizeIfNeeded(
        thumbnailCacheWidth,
        thumbnailCacheHeight,
        baseImageProvider,
      );
      await precacheImage(
        previewImageProvider,
        context,
        onError: (error, stackTrace) {},
      );
      if (!mounted ||
          _mutating ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      var dismissing = false;

      await Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: false,
          barrierLabel: 'Close image preview',
          barrierColor: Colors.black.withValues(
            alpha: submissionPreviewBarrierOpacity,
          ),
          transitionDuration: submissionPreviewAnimationDuration,
          reverseTransitionDuration: const Duration(milliseconds: 90),
          pageBuilder: (routeContext, animation, _) => SubmissionImagePreview(
            submission: submission,
            imageProvider: previewImageProvider,
            animation: animation,
            onDismiss: () {
              if (dismissing) return;
              dismissing = true;
              Navigator.of(routeContext).pop();
            },
          ),
        ),
      );
    } finally {
      _preparingPreview = false;
    }
  }

  Future<void> _openFolderGallery(String folderName) async {
    if (_mutating || _openingFolder) return;
    setState(() => _openingFolder = true);
    try {
      final page = _page;
      final normalizedName = folderName.trim().toLowerCase();
      if (normalizedName == 'main gallery' || normalizedName == 'scraps') {
        final galleryUri = normalizedName == 'scraps'
            ? page?.scrapsUri
            : page?.mainGalleryUri;
        if (galleryUri == null) {
          _showMessage('Could not open the $folderName folder.', error: true);
          return;
        }
        await handleFALink(context, galleryUri.toString());
        return;
      }
      final foldersPage = await _repository.loadFolders();
      if (!mounted) return;
      final groupNames = <String, String>{
        for (final group in foldersPage.groups) group.id: group.name,
      };
      final matches = foldersPage.folders.where((folder) {
        if (folder.name.trim().toLowerCase() == normalizedName) return true;
        final groupName = groupNames[folder.groupId];
        if (groupName == null) return false;
        return '$groupName -- ${folder.name}'.trim().toLowerCase() ==
            normalizedName;
      });
      final galleryUri = matches.isEmpty ? null : matches.first.galleryUri;
      if (galleryUri == null) {
        _showMessage('Could not open the $folderName folder.', error: true);
        return;
      }
      await handleFALink(context, galleryUri.toString());
    } catch (error) {
      if (mounted) _showMessage('$error', error: true);
    } finally {
      if (mounted) setState(() => _openingFolder = false);
    }
  }

  Future<void> _showHints() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hints'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Warning icon ⚠️ next to submission titles means that submission is missing tags.',
              ),
              SizedBox(height: 12),
              Text('Press and hold an image to preview it.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(
              foregroundColor: managementAccent,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final hasSelection = _selectedIds.isNotEmpty;
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: managementBackground,
        appBar: AppBar(
          title: const SubmissionManagementShrinkableText(
            'Manage Submissions',
          ),
          actions: [
            IconButton(
              tooltip: 'Hints',
              onPressed: _showHints,
              icon: const Icon(
                Icons.info_outline_rounded,
                color: Colors.white,
              ),
            ),
            if (hasSelection)
              PopupMenuButton<_SubmissionActionDialog>(
                tooltip: 'Submission actions',
                position: PopupMenuPosition.under,
                offset: const Offset(0, 8),
                menuPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF3A3A3A)),
                ),
                enabled: !_loading && !_mutating && page != null,
                onSelected: _openActionDialog,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: managementAccent,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<_SubmissionActionDialog>(
                    value: _SubmissionActionDialog.assignExisting,
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: managementMenuVerticalPadding,
                    ),
                    enabled: page?.actions.containsKey(
                              SubmissionManagementActionType.assignToFolder,
                            ) ==
                            true &&
                        (page?.folders.isNotEmpty ?? false),
                    child: const Text('Assign to Existing Folder'),
                  ),
                  const PopupMenuItem<_SubmissionActionDialog>(
                    enabled: false,
                    height: 1,
                    padding: EdgeInsets.zero,
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  PopupMenuItem<_SubmissionActionDialog>(
                    value: _SubmissionActionDialog.assignNew,
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: managementMenuVerticalPadding,
                    ),
                    enabled: page?.actions.containsKey(
                          SubmissionManagementActionType.createFolder,
                        ) ==
                        true,
                    child: const Text('Assign to New Folder'),
                  ),
                  const PopupMenuItem<_SubmissionActionDialog>(
                    enabled: false,
                    height: 1,
                    padding: EdgeInsets.zero,
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  PopupMenuItem<_SubmissionActionDialog>(
                    value: _SubmissionActionDialog.unassign,
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: managementMenuVerticalPadding,
                    ),
                    enabled: page?.actions.containsKey(
                          SubmissionManagementActionType.unassignFromFolders,
                        ) ==
                        true,
                    child: const Text('Unassign From Folder(s)'),
                  ),
                  const PopupMenuItem<_SubmissionActionDialog>(
                    enabled: false,
                    height: 1,
                    padding: EdgeInsets.zero,
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  PopupMenuItem<_SubmissionActionDialog>(
                    value: _SubmissionActionDialog.move,
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: managementMenuVerticalPadding,
                    ),
                    enabled: page?.actions.containsKey(
                              SubmissionManagementActionType.moveToGallery,
                            ) ==
                            true ||
                        page?.actions.containsKey(
                              SubmissionManagementActionType.moveToScraps,
                            ) ==
                            true,
                    child: const Text('Move to Gallery or Scraps'),
                  ),
                ],
              )
            else
              IconButton(
                tooltip: 'Manage folders',
                onPressed: _loading || _mutating ? null : _openFolders,
                icon: const Icon(
                  Icons.folder_open_rounded,
                  color: managementAccent,
                ),
              ),
          ],
        ),
        body: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _page == null) {
      return Center(
        child: PulsatingLoadingIndicator(
          size: 72,
          assetPath: 'assets/icons/fathemed.png',
        ),
      );
    }
    if (_loadError != null && _page == null) {
      return _ErrorState(error: _loadError!, onRetry: _controller.load);
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    final folderColors = _folderColors;
    final allSelected = _controller.allSelected(page);
    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        final width =
            math.max(1.0, viewportConstraints.maxWidth - 20.0).toDouble();
        final columns = width >= 900
            ? 4
            : width >= 600
                ? 3
                : 2;
        final tileWidth = math
            .max(1.0, (width - ((columns - 1) * 8)) / columns)
            .toDouble();
        final thumbnailCacheWidth = math
            .max(
              1,
              (tileWidth * MediaQuery.devicePixelRatioOf(context)).ceil(),
            )
            .toInt();
        return Stack(
          children: [
            RefreshIndicator(
              color: managementAccent,
              backgroundColor: Colors.black,
              onRefresh: () => _controller.load(uri: page.sourceUri, resetDrafts: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (page.submissions.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: Text(
                            'No submissions on this page.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                      sliver: SliverMasonryGrid(
                        gridDelegate:
                            SliverSimpleGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                        ),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final submission = page.submissions[index];
                            return SubmissionSelectionTile(
                              key: ValueKey(submission.id),
                              submission: submission,
                              thumbnailCacheWidth: thumbnailCacheWidth,
                              selected: _selectedIds.contains(submission.id),
                              showDetails: _titlesEnabled,
                              folderColors: folderColors,
                              enabled: !_mutating,
                              onToggle: () => _controller.toggleSubmission(submission.id),
                              onPreview: () =>
                                  _showSubmissionPreview(
                                    submission,
                                    thumbnailCacheWidth,
                                  ),
                              onOpen: () => _openSubmission(submission),
                              onFolder: _openFolderGallery,
                            );
                          },
                          childCount: page.submissions.length,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child:
                        SizedBox(height: managementActionsScrollClearance),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ManageSubmissionsBottomOverlay(
                selectedCount: _selectedIds.length,
                allSelected: allSelected,
                detailsVisible: _titlesEnabled,
                currentPage: page.currentPage,
                enabled: !_mutating,
                newerEnabled: page.newerUri != null && !_mutating,
                olderEnabled: page.olderUri != null && !_mutating,
                deleteEnabled: _selectedIds.isNotEmpty &&
                    page.actions.containsKey(
                      SubmissionManagementActionType.deleteSubmissions,
                    ),
                onToggleDetails: () {
                  setState(() => _titlesEnabled = !_titlesEnabled);
                },
                onToggleAll: allSelected ? _controller.deselectAll : _controller.selectAll,
                onNewer: () => _navigateToPage(page.newerUri),
                onOlder: () => _navigateToPage(page.olderUri),
                onDelete: () => _controller.applyAction(
                  SubmissionManagementActionType.deleteSubmissions,
                ),
              ),
            ),
            if (_mutating)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const SubmissionManagementShrinkableText('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
