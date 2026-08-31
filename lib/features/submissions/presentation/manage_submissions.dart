import 'dart:math' as math;

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/manage_submission_folders.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

const Color _managementAccent = Color(0xFFE09321);
const Color _managementBackground = Colors.black;
const Color _managementCard = Color(0xFF1A1A1A);
const Color _fallbackFolderColor = Color(0xFF455A64);
const Color _selectedSubmissionOverlay = Color(0x3AE09321);
const Color _submissionCheckboxBackground = Color(0x66000000);
const double _managementMenuVerticalPadding = 16;
const double _managementActionsFadeCeilingAboveButtons = 50.0;
const double _managementActionsFadeTransitionStart = 0.0;
const double _managementActionsFadeBlackStop = 1.0;
const double _managementActionsFadePosition = 0.20;
const double _managementActionsFadeSmoothness = 1.0;
const int _managementActionsFadeSteps = 64;
const double _managementActionsScrollClearance = 160.0;
const Duration _submissionPreviewAnimationDuration =
    Duration(milliseconds: 180);
const double _submissionPreviewInitialScale = 0.94;
const double _submissionPreviewBarrierOpacity = 0.78;
const double _submissionPreviewScreenPadding = 20.0;
const double _submissionPreviewBorderRadius = 10.0;

final List<double> _managementActionsFadeStops = List<double>.generate(
  _managementActionsFadeSteps + 1,
  (index) => index / _managementActionsFadeSteps,
  growable: false,
);

final List<Color> _managementActionsFadeColors = List<Color>.generate(
  _managementActionsFadeSteps + 1,
  (index) => Color.fromARGB(
    (_managementActionsFadeAlpha(index / _managementActionsFadeSteps) * 255)
        .round(),
    0,
    0,
    0,
  ),
  growable: false,
);

double _managementActionsFadeAlpha(double stop) {
  final transitionStart =
      _managementActionsFadeTransitionStart.clamp(0.0, 0.99).toDouble();
  final blackStop = _managementActionsFadeBlackStop
      .clamp(transitionStart + 0.01, 1.0)
      .toDouble();
  if (stop <= transitionStart) return 0.0;
  if (stop >= blackStop) return 1.0;

  final progress =
      (stop - transitionStart) / (blackStop - transitionStart);
  final position =
      _managementActionsFadePosition.clamp(0.01, 0.99).toDouble();
  final smoothness =
      _managementActionsFadeSmoothness.clamp(0.0, 1.0).toDouble();
  final steepness = 14.0 - (smoothness * 12.0);
  final shiftedProgress = (progress * (1.0 - position)) /
      (position + (progress * (1.0 - (2.0 * position))));

  double sigmoid(double value) {
    return 1.0 / (1.0 + math.exp(-steepness * (value - 0.5)));
  }

  final minimum = sigmoid(0.0);
  final maximum = sigmoid(1.0);
  final normalizedAlpha =
      ((sigmoid(shiftedProgress) - minimum) / (maximum - minimum))
          .clamp(0.0, 1.0)
          .toDouble();
  final edgeSmoothedAlpha =
      normalizedAlpha * normalizedAlpha * (3.0 - (2.0 * normalizedAlpha));
  return (normalizedAlpha +
          ((edgeSmoothedAlpha - normalizedAlpha) * smoothness))
      .clamp(0.0, 1.0)
      .toDouble();
}

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
  late final SubmissionFolderColorRepository _folderColorRepository;
  final Set<String> _selectedIds = <String>{};
  Map<String, Color> _folderColors = const <String, Color>{};

  FaSubmissionManagementPage? _page;
  Object? _loadError;
  bool _loading = true;
  bool _mutating = false;
  bool _allowPop = false;
  bool _titlesEnabled = true;
  bool _changed = false;
  bool _openingFolder = false;
  bool _preparingPreview = false;

  bool get _dirty => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SubmissionManagementRepository>();
    _folderColorRepository = context.read<SubmissionFolderColorRepository>();
    _load(
      navigationAction: widget.initialNavigationAction,
      resetDrafts: true,
    );
  }

  Future<void> _load({
    Uri? uri,
    FaManagementFormAction? navigationAction,
    bool resetDrafts = false,
  }) async {
    if (_loading && _page != null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _repository.loadSubmissions(
        uri: uri,
        navigationAction: navigationAction,
      );
      final folderColors = await _loadFolderColors(page);
      if (!mounted) return;
      _setPage(
        page,
        folderColors: folderColors,
        resetDrafts: resetDrafts,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
      if (_page != null) _showMessage('$error', error: true);
    }
  }

  void _setPage(
    FaSubmissionManagementPage page, {
    required Map<String, Color> folderColors,
    required bool resetDrafts,
  }) {
    setState(() {
      _page = page;
      _folderColors = folderColors;
      _loading = false;
      _loadError = null;
      if (resetDrafts) {
        _selectedIds.clear();
      } else {
        final visibleIds = page.submissions.map((item) => item.id).toSet();
        _selectedIds.removeWhere((id) => !visibleIds.contains(id));
      }
    });
  }

  void _clearDrafts() {
    setState(_selectedIds.clear);
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
    await _load(uri: uri, resetDrafts: true);
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
      await _load(navigationAction: action, resetDrafts: true);
      return;
    }
    await _load(uri: _page?.sourceUri, resetDrafts: false);
  }

  void _toggleSubmission(String id) {
    if (_mutating) return;
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _selectAll() {
    final page = _page;
    if (page == null || _mutating) return;
    final allIds = page.submissions.map((item) => item.id).toSet();
    setState(() {
      _selectedIds.addAll(allIds);
    });
  }

  void _deselectAll() {
    if (_mutating) return;
    setState(_selectedIds.clear);
  }

  bool _allSelected(FaSubmissionManagementPage page) {
    if (page.submissions.isEmpty) return false;
    final allIds = page.submissions.map((submission) => submission.id);
    return _selectedIds.length == page.submissions.length &&
        allIds.every(_selectedIds.contains);
  }

  List<FaManagedSubmission> _selectedSubmissions(
    FaSubmissionManagementPage page,
  ) {
    return page.submissions
        .where((submission) => _selectedIds.contains(submission.id))
        .toList(growable: false);
  }

  Future<Map<String, Color>> _loadFolderColors(
    FaSubmissionManagementPage page,
  ) async {
    final names = page.submissions.expand(
      (submission) => submission.assignedFolders,
    );
    try {
      final storedColors = await _folderColorRepository.colorsFor(names);
      return <String, Color>{
        for (final entry in storedColors.entries)
          entry.key: Color(entry.value),
      };
    } catch (_) {
      return <String, Color>{
        for (final name in names) name: _fallbackFolderColor,
      };
    }
  }

  Future<void> _applyAction(
    SubmissionManagementActionType actionType, {
    String? folderId,
    String? newFolderName,
  }) async {
    final page = _page;
    if (page == null || _mutating) return;
    if (actionType == SubmissionManagementActionType.deleteSubmissions) {
      final confirmed = await _confirmDelete(page);
      if (!mounted || !confirmed) return;
    }
    setState(() => _mutating = true);
    FaContentManagementResult result;
    try {
      result = await _repository.applySubmissionAction(
        page: page,
        actionType: actionType,
        submissionIds: Set<String>.from(_selectedIds),
        folderId: folderId,
        newFolderName: newFolderName,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _mutating = false);
      _showMessage('$error', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _mutating = false);
    if (result.changed) _changed = true;
    if (result.success) {
      _clearDrafts();
      final refreshed = result.submissionPage;
      if (refreshed != null) {
        final folderColors = await _loadFolderColors(refreshed);
        if (!mounted) return;
        _setPage(
          refreshed,
          folderColors: folderColors,
          resetDrafts: true,
        );
      } else {
        await _load(uri: page.sourceUri, resetDrafts: true);
      }
    } else if (result.partial || result.indeterminate) {
      final refreshed = result.submissionPage;
      if (refreshed != null) {
        final folderColors = await _loadFolderColors(refreshed);
        if (!mounted) return;
        _setPage(
          refreshed,
          folderColors: folderColors,
          resetDrafts: false,
        );
      } else {
        await _load(uri: page.sourceUri, resetDrafts: false);
      }
      if (!mounted) return;
      final remaining = result.remainingSubmissionIds;
      if (remaining.isNotEmpty) {
        setState(() {
          _selectedIds
            ..clear()
            ..addAll(remaining.where(
              (id) => _page?.submissions.any((item) => item.id == id) ?? false,
            ));
        });
      }
    }
    if (!mounted) return;
    _showResult(result);
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
    String? selectedFolderId = page.selectedFolderId;
    if (selectedFolderId != null &&
        !page.folders.any((folder) => folder.id == selectedFolderId)) {
      selectedFolderId = null;
    }
    final selected = _selectedSubmissions(page);
    final folderId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              title: const Text('Assign to Existing Folder'),
              content: _SubmissionActionDialogBody(
                submissions: selected,
                folderColors: _folderColors,
                description:
                    'Assign the selected submissions to an existing folder.',
                controls: DropdownButtonFormField<String>(
                  key: ValueKey(selectedFolderId),
                  initialValue: selectedFolderId,
                  isExpanded: true,
                  hint: const SubmissionManagementShrinkableText(
                    '-- select folder --',
                  ),
                  items: [
                    for (final folder in page.folders)
                      DropdownMenuItem<String>(
                        value: folder.id,
                        child: SubmissionManagementShrinkableText(
                          folder.label,
                          maxLines: 2,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedFolderId = value);
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedFolderId == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                            selectedFolderId,
                          ),
                  style: TextButton.styleFrom(
                    foregroundColor: _managementAccent,
                  ),
                  child: const Text('Assign to Folder'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || folderId == null) return;
    await _applyAction(
      SubmissionManagementActionType.assignToFolder,
      folderId: folderId,
    );
  }

  Future<void> _showAssignNewDialog(FaSubmissionManagementPage page) async {
    var folderName = '';
    final selected = _selectedSubmissions(page);
    final newFolderName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              title: const Text('Assign to New Folder'),
              content: _SubmissionActionDialogBody(
                submissions: selected,
                folderColors: _folderColors,
                description:
                    'Create a new folder and assign the selected submissions to it.',
                controls: TextField(
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    label: SubmissionManagementShrinkableText('Folder'),
                    hint: SubmissionManagementShrinkableText(
                      'Enter a new folder name',
                    ),
                  ),
                  onChanged: (value) {
                    folderName = value;
                    setDialogState(() {});
                  },
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty) {
                      Navigator.of(dialogContext).pop(trimmed);
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: folderName.trim().isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                            folderName.trim(),
                          ),
                  style: TextButton.styleFrom(
                    foregroundColor: _managementAccent,
                  ),
                  child: const Text('Create New Folder'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || newFolderName == null) return;
    await _applyAction(
      SubmissionManagementActionType.createFolder,
      newFolderName: newFolderName,
    );
  }

  Future<void> _showUnassignDialog(FaSubmissionManagementPage page) async {
    final selected = _selectedSubmissions(page);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: const Text('Unassign From Folder(s)'),
            content: _SubmissionActionDialogBody(
              submissions: selected,
              folderColors: _folderColors,
              description:
                  'Remove the selected submissions from all folders they are currently assigned to.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: _managementAccent,
                ),
                child: const Text('Unassign from Folders'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    await _applyAction(
      SubmissionManagementActionType.unassignFromFolders,
    );
  }

  Future<void> _showMoveDialog(FaSubmissionManagementPage page) async {
    final selected = _selectedSubmissions(page);
    final action = await showDialog<SubmissionManagementActionType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Move to Gallery or Scraps'),
        content: _SubmissionActionDialogBody(
          submissions: selected,
          folderColors: _folderColors,
          description:
              'Move the selected submissions to your Gallery or Scraps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: page.actions.containsKey(
              SubmissionManagementActionType.moveToScraps,
            )
                ? () => Navigator.of(dialogContext).pop(
                      SubmissionManagementActionType.moveToScraps,
                    )
                : null,
            style: TextButton.styleFrom(
              foregroundColor: _managementAccent,
            ),
            child: const Text('Move to Scraps'),
          ),
          TextButton(
            onPressed: page.actions.containsKey(
              SubmissionManagementActionType.moveToGallery,
            )
                ? () => Navigator.of(dialogContext).pop(
                      SubmissionManagementActionType.moveToGallery,
                    )
                : null,
            style: TextButton.styleFrom(
              foregroundColor: _managementAccent,
            ),
            child: const Text('Move to Gallery'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    await _applyAction(action);
  }

  Future<bool> _confirmDelete(FaSubmissionManagementPage page) async {
    if (_selectedIds.isEmpty) {
      _showMessage('Select at least one submission.', error: true);
      return false;
    }
    final selected = _selectedSubmissions(page);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(
              'Permanently delete ${selected.length} submission${selected.length == 1 ? '' : 's'}?',
            ),
            content: _SubmissionActionDialogBody(
              submissions: selected,
              folderColors: _folderColors,
              description:
                  'This cannot be undone. Only the submissions shown below will be sent to Fur Affinity for deletion.',
              warning:
                  'When removing multiple submissions the page may time out. Progress may still be made. The app will reload the page and keep only any submissions that still remain selected; it will never repeat the request automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete Submissions'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showResult(FaContentManagementResult result) {
    final message = result.message ??
        (result.success ? 'Changes applied.' : 'The change was not applied.');
    _showMessage(
      message,
      success: result.success,
      warning: result.partial || result.indeterminate,
      error: !result.success && !result.partial && !result.indeterminate,
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

  Future<void> _openPost(FaManagedSubmission submission) async {
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
            alpha: _submissionPreviewBarrierOpacity,
          ),
          transitionDuration: _submissionPreviewAnimationDuration,
          reverseTransitionDuration: const Duration(milliseconds: 90),
          pageBuilder: (routeContext, animation, _) => _SubmissionImagePreview(
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
              foregroundColor: _managementAccent,
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
        backgroundColor: _managementBackground,
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
                  color: _managementAccent,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<_SubmissionActionDialog>(
                    value: _SubmissionActionDialog.assignExisting,
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: _managementMenuVerticalPadding,
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
                      vertical: _managementMenuVerticalPadding,
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
                      vertical: _managementMenuVerticalPadding,
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
                      vertical: _managementMenuVerticalPadding,
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
                  color: _managementAccent,
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
      return _ErrorState(error: _loadError!, onRetry: _load);
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    final folderColors = _folderColors;
    final allSelected = _allSelected(page);
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
              color: _managementAccent,
              backgroundColor: Colors.black,
              onRefresh: () => _load(uri: page.sourceUri, resetDrafts: false),
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
                            return _SubmissionSelectionTile(
                              key: ValueKey(submission.id),
                              submission: submission,
                              thumbnailCacheWidth: thumbnailCacheWidth,
                              selected: _selectedIds.contains(submission.id),
                              showDetails: _titlesEnabled,
                              folderColors: folderColors,
                              enabled: !_mutating,
                              onToggle: () => _toggleSubmission(submission.id),
                              onPreview: () =>
                                  _showSubmissionPreview(
                                    submission,
                                    thumbnailCacheWidth,
                                  ),
                              onOpen: () => _openPost(submission),
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
                        SizedBox(height: _managementActionsScrollClearance),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ManageSubmissionsBottomOverlay(
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
                onToggleAll: allSelected ? _deselectAll : _selectAll,
                onNewer: () => _navigateToPage(page.newerUri),
                onOlder: () => _navigateToPage(page.olderUri),
                onDelete: () => _applyAction(
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

class _ManageSubmissionsBottomOverlay extends StatelessWidget {
  const _ManageSubmissionsBottomOverlay({
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
                  colors: _managementActionsFadeColors,
                  stops: _managementActionsFadeStops,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Padding(
            padding: const EdgeInsets.only(
              top: _managementActionsFadeCeilingAboveButtons,
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
                              color: _managementCard,
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
                                      ? _managementAccent
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: counterWidth,
                            child: Material(
                              color: _managementCard,
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
                                                : _managementAccent,
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
                              color: _managementCard,
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

class _SubmissionActionDialogBody extends StatelessWidget {
  const _SubmissionActionDialogBody({
    required this.submissions,
    required this.folderColors,
    required this.description,
    this.controls,
    this.warning,
  });

  final List<FaManagedSubmission> submissions;
  final Map<String, Color> folderColors;
  final String description;
  final Widget? controls;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.32;
    final desiredListHeight = submissions.length * 92.0;
    final listHeight = desiredListHeight < 112
        ? 112.0
        : desiredListHeight > maxListHeight
            ? maxListHeight
            : desiredListHeight;
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(description, style: const TextStyle(color: Colors.white70)),
          if (controls != null) ...[
            const SizedBox(height: 14),
            controls!,
          ],
          const SizedBox(height: 14),
          Text(
            '${submissions.length} selected',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: listHeight,
            child: _SelectedSubmissionsList(
              submissions: submissions,
              folderColors: folderColors,
            ),
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Text(
              warning!,
              style: const TextStyle(
                color: _managementAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedSubmissionsList extends StatelessWidget {
  const _SelectedSubmissionsList({
    required this.submissions,
    required this.folderColors,
  });

  final List<FaManagedSubmission> submissions;
  final Map<String, Color> folderColors;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView.separated(
        primary: false,
        itemCount: submissions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final submission = submissions[index];
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _managementCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FaNetworkImage(
                    submission.thumbnailUri.toString(),
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(
                        color: Color(0xFF2A2A2A),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SubmissionManagementShrinkableText(
                        submission.title,
                        maxLines: 2,
                        minFontSize: 9,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '#${submission.id}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      if (submission.assignedFolders.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final folder in submission.assignedFolders)
                              _FolderNameChip(
                                name: folder,
                                color: folderColors[folder] ?? Colors.grey,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
              backgroundColor: _managementCard,
              disabledBackgroundColor: _managementCard,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : const BorderSide(color: _managementAccent),
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
              color: _managementAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: olderEnabled ? onOlder : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: _managementCard,
              disabledBackgroundColor: _managementCard,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : const BorderSide(color: _managementAccent),
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

class _SubmissionSelectionTile extends StatelessWidget {
  const _SubmissionSelectionTile({
    super.key,
    required this.submission,
    required this.thumbnailCacheWidth,
    required this.selected,
    required this.showDetails,
    required this.folderColors,
    required this.enabled,
    required this.onToggle,
    required this.onPreview,
    required this.onOpen,
    required this.onFolder,
  });

  final FaManagedSubmission submission;
  final int thumbnailCacheWidth;
  final bool selected;
  final bool showDetails;
  final Map<String, Color> folderColors;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onPreview;
  final VoidCallback onOpen;
  final ValueChanged<String> onFolder;

  @override
  Widget build(BuildContext context) {
    final aspect = submission.width / submission.height;
    final thumbnailCacheHeight = math
        .max(1, (thumbnailCacheWidth / aspect).ceil())
        .toInt();
    return Semantics(
      button: true,
      selected: selected,
      label: '${submission.title}, ${selected ? 'selected' : 'not selected'}',
      child: Material(
        color: _managementCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF3A3A3A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: InkWell(
                onTap: enabled ? onToggle : null,
                onLongPress: enabled ? onPreview : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FaThumbnailOutline(
                      rating: submission.rating,
                      borderRadius: 10,
                      child: SizedBox.expand(
                        child: FaNetworkImage(
                          submission.thumbnailUri.toString(),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          cacheWidth: thumbnailCacheWidth,
                          cacheHeight: thumbnailCacheHeight,
                          excludeFromSemantics: true,
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Color(0xFF2A2A2A),
                              child: Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (selected)
                      const ColoredBox(color: _selectedSubmissionOverlay),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: SizedBox.square(
                        dimension: 40,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: _submissionCheckboxBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Checkbox(
                            value: selected,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            activeColor: _managementAccent,
                            onChanged: enabled ? (_) => onToggle() : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showDetails)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: enabled ? onOpen : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (submission.missingTags) ...[
                            const Tooltip(
                              message: 'This submission is missing tags',
                              child: Text('⚠️'),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              submission.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9),
                    child: Divider(
                      height: 16,
                      thickness: 1,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
                    child: submission.assignedFolders.isEmpty
                        ? const Text(
                            'No folders',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          )
                        : Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                              for (final folder
                                  in submission.assignedFolders)
                                _FolderNameChip(
                                  name: folder,
                                  color: folderColors[folder] ??
                                      _fallbackFolderColor,
                                  onTap: enabled
                                      ? () => onFolder(folder)
                                      : null,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionImagePreview extends StatelessWidget {
  const _SubmissionImagePreview({
    required this.submission,
    required this.imageProvider,
    required this.animation,
    required this.onDismiss,
  });

  final FaManagedSubmission submission;
  final ImageProvider imageProvider;
  final Animation<double> animation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final aspect = submission.width / submission.height;
    return SafeArea(
      child: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(_submissionPreviewScreenPadding),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var previewWidth = constraints.maxWidth;
                var previewHeight = previewWidth / aspect;
                if (previewHeight > constraints.maxHeight) {
                  previewHeight = constraints.maxHeight;
                  previewWidth = previewHeight * aspect;
                }
                return Center(
                  child: AnimatedBuilder(
                    animation: animation,
                    child: SizedBox(
                      width: previewWidth,
                      height: previewHeight,
                      child: Semantics(
                        image: true,
                        label: '${submission.title} preview. Tap to close.',
                        child: FaThumbnailOutline(
                          rating: submission.rating,
                          borderRadius: _submissionPreviewBorderRadius,
                          child: SizedBox.expand(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                _submissionPreviewBorderRadius,
                              ),
                              child: ColoredBox(
                                color: _managementCard,
                                child: Image(
                                  image: imageProvider,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  excludeFromSemantics: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white70,
                                        size: 40,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    builder: (context, child) {
                      final progress = Curves.easeOutCubic.transform(
                        animation.value,
                      );
                      final scale = _submissionPreviewInitialScale +
                          ((1.0 - _submissionPreviewInitialScale) * progress);
                      return Transform.scale(scale: scale, child: child);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderNameChip extends StatelessWidget {
  const _FolderNameChip({
    required this.name,
    required this.color,
    this.onTap,
  });

  final String name;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              name,
              softWrap: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
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
