import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/submission_folder_editor_screen.dart';
import 'package:fanotifier/features/submissions/presentation/submission_folder_group_editor_screen.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_cards.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_color_dialog.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_widgets.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class ManageSubmissionFoldersResult {
  const ManageSubmissionFoldersResult({this.openSubmissionsAction});

  final FaManagementFormAction? openSubmissionsAction;
}

class ManageSubmissionFoldersScreen extends StatefulWidget {
  const ManageSubmissionFoldersScreen({super.key});

  static Route<ManageSubmissionFoldersResult> route() {
    return MaterialPageRoute<ManageSubmissionFoldersResult>(
      settings:
          const AnalyticsRouteSettings(AppScreens.manageSubmissionFolders),
      builder: (_) => const ManageSubmissionFoldersScreen(),
    );
  }

  @override
  State<ManageSubmissionFoldersScreen> createState() =>
      _ManageSubmissionFoldersScreenState();
}

class _ManageSubmissionFoldersScreenState
    extends State<ManageSubmissionFoldersScreen> {
  late final SubmissionManagementRepository _repository;
  late final SubmissionFolderColorRepository _folderColorRepository;

  FaFolderManagementPage? _page;
  Map<String, Color> _folderColors = const <String, Color>{};
  Object? _loadError;
  bool _loading = true;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SubmissionManagementRepository>();
    _folderColorRepository = context.read<SubmissionFolderColorRepository>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _repository.loadFolders();
      final folderColors = await _loadFolderColors(page);
      if (!mounted) return;
      setState(() {
        _page = page;
        _folderColors = folderColors;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<Map<String, Color>> _loadFolderColors(
    FaFolderManagementPage page,
  ) async {
    final names = page.folders.map((folder) => folder.name);
    try {
      final storedColors = await _folderColorRepository.colorsFor(names);
      return <String, Color>{
        for (final entry in storedColors.entries)
          entry.key: Color(entry.value),
      };
    } catch (_) {
      return <String, Color>{
        for (final name in names) name: fallbackFolderColor,
      };
    }
  }

  Future<void> _editFolderColor(FaManagedFolder folder) async {
    final currentColor =
        _folderColors[folder.name] ?? fallbackFolderColor;
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (_) => FolderColorDialog(
        folderName: folder.name,
        initialColor: currentColor,
      ),
    );
    if (!mounted || selectedColor == null || selectedColor == currentColor) {
      return;
    }
    try {
      await _folderColorRepository.setColor(
        folder.name,
        selectedColor.toARGB32(),
      );
    } catch (_) {
      if (mounted) _showValidation('Could not save the folder color.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _folderColors = <String, Color>{
        ..._folderColors,
        folder.name: selectedColor,
      };
    });
  }

  void _showResult(FaContentManagementResult result) {
    if (!mounted) return;
    final message = result.message ??
        (result.success ? 'Changes applied.' : 'The change was not applied.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: result.success
            ? Colors.green.shade700
            : result.indeterminate
                ? Colors.orange.shade800
                : Colors.red.shade700,
      ),
    );
  }

  Future<void> _applyAction(
    FaManagementFormAction? action, {
    Map<String, String?> overrides = const <String, String?>{},
  }) async {
    if (action == null || _mutating) return;
    setState(() => _mutating = true);
    final result = await _repository.applyFolderAction(
      action,
      overrides: overrides,
    );
    if (!mounted) return;
    setState(() => _mutating = false);
    _showResult(result);
    if (result.success || result.indeterminate) {
      await _load();
    }
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _confirmDeleteGroup(FaManagedFolderGroup group) async {
    final confirmed = await _confirmDeletion(
      title: 'Delete ${group.name}?',
      message:
          'Removing a Folder Group will not delete any folders it contains. The folders will become ungrouped.',
    );
    if (confirmed && mounted) await _applyAction(group.deleteAction);
  }

  Future<void> _confirmDeleteFolder(FaManagedFolder folder) async {
    final confirmed = await _confirmDeletion(
      title: 'Delete ${folder.name}?',
      message:
          'Deleting this folder will not remove submissions assigned to it.',
    );
    if (confirmed && mounted) await _applyAction(folder.deleteAction);
  }

  Future<bool> _confirmDeletion({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openFolderEditor({
    Uri? uri,
    FaManagementFormAction? navigationAction,
    String? appBarTitle,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      SubmissionFolderEditorScreen.route(
        uri: uri,
        navigationAction: navigationAction,
        appBarTitle: appBarTitle,
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openGroupEditor({FaManagedFolderGroup? group}) async {
    final page = _page;
    if (page == null || _mutating) return;
    final result = await Navigator.of(context).push<FaContentManagementResult>(
      group == null
          ? SubmissionFolderGroupEditorScreen.createRoute(page: page)
          : SubmissionFolderGroupEditorScreen.editRoute(
              page: page,
              group: group,
            ),
    );
    if (!mounted || result == null) return;
    _showResult(result);
    if (result.success || result.indeterminate) await _load();
  }

  Future<void> _openSubmissions(FaManagementFormAction? action) async {
    if (action == null || _mutating) return;
    Navigator.of(context).pop(
      ManageSubmissionFoldersResult(openSubmissionsAction: action),
    );
  }

  Future<void> _openFaPlus() async {
    final uri = _page?.faPlusUri;
    if (uri == null) return;
    var opened = false;
    try {
      opened = await tryLaunchExternalUri(uri);
    } catch (_) {}
    if (!mounted || opened) return;
    _showValidation('Could not open the FA+ page.');
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final createFolderUri = page?.createFolderUri;
    return Scaffold(
      backgroundColor: managementBackground,
      appBar: AppBar(
        title: const SubmissionManagementShrinkableText('Folders'),
        actions: [
          IconButton(
            tooltip: 'Create group',
            color: managementAccent,
            disabledColor: Colors.grey.shade700,
            onPressed: page?.createGroupAction != null && !_mutating
                ? () => _openGroupEditor()
                : null,
            icon: const Icon(Symbols.rectangle_add_rounded),
          ),
          IconButton(
            tooltip: 'Create folder',
            color: managementAccent,
            disabledColor: Colors.grey.shade700,
            onPressed: createFolderUri != null && !_mutating
                ? () => _openFolderEditor(
                    uri: createFolderUri,
                    appBarTitle: 'Create Folder',
                  )
                : null,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _buildBody()),
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
      return ErrorState(error: _loadError!, onRetry: _load);
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();

    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            FolderOverviewCard(
              maximumFolders: page.maximumFolders,
              faPlusIconUri: page.faPlusIconUri,
              onFaPlus: page.faPlusUri == null ? null : _openFaPlus,
            ),
            const SizedBox(height: 20),
            if (page.groups.isNotEmpty) ...[
              const SectionTitle('Folder Groups'),
              for (final group in page.groups) ...[
                GroupCard(
                  group: group,
                  folderColors: _folderColors,
                  folders: page.folders
                      .where((folder) => folder.groupId == group.id)
                      .toList(growable: false),
                  enabled: !_mutating,
                  onMoveUp: () => _applyAction(group.moveUpAction),
                  onMoveDown: () => _applyAction(group.moveDownAction),
                  onEdit: () => _openGroupEditor(group: group),
                  onDelete: () => _confirmDeleteGroup(group),
                  onAddFolder: () => _openFolderEditor(
                    navigationAction: group.addFolderAction,
                    appBarTitle: 'Create Folder',
                  ),
                  onFolderMoveUp: (folder) =>
                      _applyAction(folder.moveUpAction),
                  onFolderMoveDown: (folder) =>
                      _applyAction(folder.moveDownAction),
                  onFolderEdit: (folder) => _openFolderEditor(
                    navigationAction: folder.editAction,
                  ),
                  onFolderEditColor: _editFolderColor,
                  onFolderDelete: _confirmDeleteFolder,
                  onAddSubmissions: (folder) =>
                      _openSubmissions(folder.addSubmissionsAction),
                  onOpenGallery: _openGallery,
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SectionTitle('Ungrouped Folders'),
            if (page.folders.where((folder) => folder.groupId == '0').isEmpty)
              const EmptyCard('No ungrouped folders.')
            else
              for (final folder
                  in page.folders.where((folder) => folder.groupId == '0')) ...[
                FolderCard(
                  folder: folder,
                  color: _folderColors[folder.name] ?? fallbackFolderColor,
                  enabled: !_mutating,
                  onMoveUp: () => _applyAction(folder.moveUpAction),
                  onMoveDown: () => _applyAction(folder.moveDownAction),
                  onEdit: () => _openFolderEditor(
                    navigationAction: folder.editAction,
                  ),
                  onEditColor: () => _editFolderColor(folder),
                  onDelete: () => _confirmDeleteFolder(folder),
                  onAddSubmissions: () =>
                      _openSubmissions(folder.addSubmissionsAction),
                  onOpenGallery: () => _openGallery(folder),
                ),
                const SizedBox(height: 8),
              ],
          ]),
        ),
      ),
    ];
    return Stack(
      children: [
        RefreshIndicator(
          color: managementAccent,
          backgroundColor: Colors.black,
          onRefresh: _load,
          child: CustomScrollView(slivers: slivers),
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
  }

  Future<void> _openGallery(FaManagedFolder folder) async {
    final uri = folder.galleryUri;
    if (uri != null) await handleFALink(context, uri.toString());
  }
}
