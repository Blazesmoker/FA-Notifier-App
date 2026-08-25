import 'package:flutter/gestures.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

const Color _managementAccent = Color(0xFFE09321);
const Color _managementBackground = Colors.black;
const Color _managementCard = Color(0xFF1A1A1A);
const Color _fallbackFolderColor = Color(0xFF455A64);

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
        for (final name in names) name: _fallbackFolderColor,
      };
    }
  }

  Future<void> _editFolderColor(FaManagedFolder folder) async {
    final currentColor =
        _folderColors[folder.name] ?? _fallbackFolderColor;
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (_) => _FolderColorDialog(
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
      backgroundColor: _managementBackground,
      appBar: AppBar(
        title: const SubmissionManagementShrinkableText('Folders'),
        actions: [
          IconButton(
            tooltip: 'Create group',
            color: _managementAccent,
            disabledColor: Colors.grey.shade700,
            onPressed: page?.createGroupAction != null && !_mutating
                ? () => _openGroupEditor()
                : null,
            icon: const Icon(Symbols.rectangle_add_rounded),
          ),
          IconButton(
            tooltip: 'Create folder',
            color: _managementAccent,
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
      return _ErrorState(error: _loadError!, onRetry: _load);
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();

    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            _FolderOverviewCard(
              maximumFolders: page.maximumFolders,
              faPlusIconUri: page.faPlusIconUri,
              onFaPlus: page.faPlusUri == null ? null : _openFaPlus,
            ),
            const SizedBox(height: 20),
            if (page.groups.isNotEmpty) ...[
              const _SectionTitle('Folder Groups'),
              for (final group in page.groups) ...[
                _GroupCard(
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
            const _SectionTitle('Ungrouped Folders'),
            if (page.folders.where((folder) => folder.groupId == '0').isEmpty)
              const _EmptyCard('No ungrouped folders.')
            else
              for (final folder
                  in page.folders.where((folder) => folder.groupId == '0')) ...[
                _FolderCard(
                  folder: folder,
                  color: _folderColors[folder.name] ?? _fallbackFolderColor,
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
          color: _managementAccent,
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

class SubmissionFolderEditorScreen extends StatefulWidget {
  const SubmissionFolderEditorScreen({
    super.key,
    this.uri,
    this.navigationAction,
    this.appBarTitle,
  });

  final Uri? uri;
  final FaManagementFormAction? navigationAction;
  final String? appBarTitle;

  static Route<bool> route({
    Uri? uri,
    FaManagementFormAction? navigationAction,
    String? appBarTitle,
  }) {
    return MaterialPageRoute<bool>(
      settings: const AnalyticsRouteSettings(AppScreens.editSubmissionFolder),
      builder: (_) => SubmissionFolderEditorScreen(
        uri: uri,
        navigationAction: navigationAction,
        appBarTitle: appBarTitle,
      ),
    );
  }

  @override
  State<SubmissionFolderEditorScreen> createState() =>
      _SubmissionFolderEditorScreenState();
}

class _SubmissionFolderEditorScreenState
    extends State<SubmissionFolderEditorScreen> {
  late final SubmissionManagementRepository _repository;
  final Map<String, List<String>> _values = <String, List<String>>{};
  final Map<String, List<String>> _initialValues = <String, List<String>>{};
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  FaFolderEditorPage? _page;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _saveOutcomeUnknown = false;
  bool _allowPop = false;
  bool _settingControllers = false;

  bool get _dirty {
    final names = <String>{..._initialValues.keys, ..._values.keys};
    for (final name in names) {
      final initial = _initialValues[name] ?? const <String>[];
      final current = _values[name] ?? const <String>[];
      if (initial.length != current.length) return true;
      for (var index = 0; index < initial.length; index++) {
        if (initial[index] != current[index]) return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _repository = context.read<SubmissionManagementRepository>();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _repository.loadFolderEditor(
        uri: widget.uri,
        navigationAction: widget.navigationAction,
      );
      if (!mounted) return;
      _applyPage(page);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _applyPage(FaFolderEditorPage page) {
    _page = page;
    _saveOutcomeUnknown = false;
    _values.clear();
    _initialValues.clear();
    _settingControllers = true;
    for (final field in page.fields) {
      final values = List<String>.from(field.selectedValues);
      _values[field.name] = values;
      _initialValues[field.name] = List<String>.from(values);
      if (const <FaFolderEditorFieldType>{
        FaFolderEditorFieldType.text,
        FaFolderEditorFieldType.multiline,
      }.contains(field.type)) {
        final text = values.isEmpty ? '' : values.first;
        final controller = _controllers[field.name];
        if (controller == null) {
          final created = TextEditingController(text: text);
          created.addListener(() {
            if (!mounted || _settingControllers) return;
            setState(() => _values[field.name] = <String>[created.text]);
          });
          _controllers[field.name] = created;
        } else {
          controller.text = text;
        }
      }
    }
    _settingControllers = false;
  }

  Future<void> _save() async {
    final page = _page;
    if (page == null || !_dirty || _saving || _saveOutcomeUnknown) return;
    final folderNames = _values['folder_name'] ?? const <String>[];
    final folderName = folderNames.isEmpty ? '' : folderNames.first.trim();
    if (folderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a folder name.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final result = await _repository.saveFolderEditor(
      page: page,
      values: _values,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.success) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return;
    }
    if (result.indeterminate) {
      setState(() => _saveOutcomeUnknown = true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'The folder was not saved.'),
        backgroundColor: result.indeterminate
            ? Colors.orange.shade800
            : Colors.red.shade700,
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (_saveOutcomeUnknown) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return;
    }
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final close = await ConfirmCloseDialog.show(
      context,
      title: 'Discard changes?',
      message: 'Your folder changes have not been saved.',
    );
    if (!mounted || !close) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: _managementBackground,
        appBar: AppBar(
          title: SubmissionManagementShrinkableText(
            widget.appBarTitle ?? page?.title ?? 'Folder',
          ),
          actions: [
            IconButton(
              tooltip: page?.submitLabel ?? 'Save folder',
              onPressed:
                  _dirty && !_saving && !_saveOutcomeUnknown ? _save : null,
              icon: Icon(
                Icons.check_rounded,
                color: _dirty && !_saveOutcomeUnknown
                    ? _managementAccent
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
        body: SafeArea(top: false, child: _buildEditorBody()),
      ),
    );
  }

  Widget _buildEditorBody() {
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
    final group = _editorField(page, 'group_id');
    final createGroup = _editorField(page, 'create_group_name');
    final folderName = _editorField(page, 'folder_name');
    final description = _editorField(page, 'folder_description');
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            if (_saveOutcomeUnknown) ...[
              _ManagementCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'The save result is unknown. To prevent a duplicate folder, this form cannot be submitted again. Return to Folders and review the reloaded list.',
                      style: TextStyle(
                        color: _managementAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _requestClose,
                      child: const Text('Return to Folders'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardHeading('Put in Group'),
                  const SizedBox(height: 14),
                  const Text(
                    'Assign to an existing group:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  _buildGroupSelector(group),
                  const SizedBox(height: 18),
                  const Text(
                    'Or create new group named:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(createGroup),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardHeading('Folder Name'),
                  const SizedBox(height: 12),
                  _buildTextField(folderName),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardHeading('Folder Description'),
                  const SizedBox(height: 12),
                  _buildTextField(description),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _dirty &&
                            !_saving &&
                            !_saveOutcomeUnknown
                        ? _save
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _managementAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: SubmissionManagementShrinkableText(
                      page.submitLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_saving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  FaFolderEditorField _editorField(
    FaFolderEditorPage page,
    String name,
  ) {
    return page.fields.firstWhere((field) => field.name == name);
  }

  Widget _buildGroupSelector(FaFolderEditorField field) {
    final values = _values[field.name] ?? const <String>[];
    final selected = values.isEmpty ? null : values.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('${field.name}-$selected-${field.options.length}'),
      initialValue: field.options.any((option) => option.value == selected)
          ? selected
          : null,
      isExpanded: true,
      items: [
        for (final option in field.options)
          DropdownMenuItem<String>(
            value: option.value,
            child: SubmissionManagementShrinkableText(
              option.label,
              maxLines: 2,
            ),
          ),
      ],
      onChanged: _saving || _saveOutcomeUnknown
          ? null
          : (value) {
              if (value == null) return;
              setState(() => _values[field.name] = <String>[value]);
            },
    );
  }

  Widget _buildTextField(FaFolderEditorField field) {
    final multiline = field.type == FaFolderEditorFieldType.multiline;
    return TextField(
      controller: _controllers[field.name],
      enabled: !_saving && !_saveOutcomeUnknown,
      keyboardType:
          multiline ? TextInputType.multiline : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      minLines: multiline ? 6 : 1,
      maxLines: multiline ? 12 : 1,
      maxLength: field.maxLength,
      decoration: InputDecoration(
        hint: SubmissionManagementShrinkableText(
          field.name == 'folder_name'
              ? 'Enter a folder name'
              : field.name == 'folder_description'
                  ? 'Describe this folder'
                  : 'Leave empty to use the selected group',
        ),
      ),
    );
  }
}

class SubmissionFolderGroupEditorScreen extends StatefulWidget {
  const SubmissionFolderGroupEditorScreen.create({
    super.key,
    required this.page,
  }) : group = null;

  const SubmissionFolderGroupEditorScreen.edit({
    super.key,
    required this.page,
    required this.group,
  });

  final FaFolderManagementPage page;
  final FaManagedFolderGroup? group;

  static Route<FaContentManagementResult> createRoute({
    required FaFolderManagementPage page,
  }) {
    return MaterialPageRoute<FaContentManagementResult>(
      settings:
          const AnalyticsRouteSettings(AppScreens.manageSubmissionFolders),
      builder: (_) => SubmissionFolderGroupEditorScreen.create(page: page),
    );
  }

  static Route<FaContentManagementResult> editRoute({
    required FaFolderManagementPage page,
    required FaManagedFolderGroup group,
  }) {
    return MaterialPageRoute<FaContentManagementResult>(
      settings:
          const AnalyticsRouteSettings(AppScreens.manageSubmissionFolders),
      builder: (_) => SubmissionFolderGroupEditorScreen.edit(
        page: page,
        group: group,
      ),
    );
  }

  @override
  State<SubmissionFolderGroupEditorScreen> createState() =>
      _SubmissionFolderGroupEditorScreenState();
}

class _SubmissionFolderGroupEditorScreenState
    extends State<SubmissionFolderGroupEditorScreen> {
  late final SubmissionManagementRepository _repository;
  late final TextEditingController _nameController;
  bool _mutating = false;
  bool _allowPop = false;
  String _previousGroupId = '0';

  bool get _editing => widget.group != null;

  bool get _dirty {
    if (_editing) {
      return _nameController.text.trim() != widget.group!.name.trim();
    }
    return _nameController.text.trim().isNotEmpty || _previousGroupId != '0';
  }

  bool get _canSubmit {
    return !_mutating &&
        _nameController.text.trim().isNotEmpty &&
        (!_editing || _dirty);
  }

  @override
  void initState() {
    super.initState();
    _repository = context.read<SubmissionManagementRepository>();
    _nameController = TextEditingController(text: widget.group?.name ?? '');
    _nameController.selection = TextSelection.collapsed(
      offset: _nameController.text.length,
    );
    _nameController.addListener(_draftChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_draftChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final action = _editing
        ? widget.page.renameGroupAction
        : widget.page.createGroupAction;
    if (action == null) {
      _showMessage('This folder group action is unavailable.', false);
      return;
    }
    setState(() => _mutating = true);
    final result = await _repository.applyFolderAction(
      action,
      overrides: _editing
          ? <String, String?>{
              'group_id': widget.group!.id,
              'group_name': _nameController.text.trim(),
            }
          : <String, String?>{
              'group_name': _nameController.text.trim(),
              'prev_group': _previousGroupId,
            },
    );
    if (!mounted) return;
    setState(() => _mutating = false);
    if (result.success || result.indeterminate) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
      return;
    }
    _showMessage(result.message ?? 'The group change was not applied.', false);
  }

  void _showMessage(String message, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_mutating) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final close = await ConfirmCloseDialog.show(
      context,
      title: 'Discard changes?',
      message: _editing
          ? 'Your folder group rename has not been applied.'
          : 'Your new folder group has not been created.',
    );
    if (!mounted || !close) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _openFaPlus() async {
    final uri = widget.page.faPlusUri;
    if (uri == null) return;
    var opened = false;
    try {
      opened = await tryLaunchExternalUri(uri);
    } catch (_) {}
    if (!mounted || opened) return;
    _showMessage('Could not open the FA+ page.', false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: _managementBackground,
        appBar: AppBar(
          title: SubmissionManagementShrinkableText(
            _editing ? 'Edit Group' : 'Create Group',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  if (_editing)
                    _GroupRenameCard(
                      group: widget.group!,
                      controller: _nameController,
                      enabled: !_mutating,
                      canSubmit: _canSubmit,
                      onRename: _submit,
                    )
                  else
                    _GroupCreateCard(
                      groups: widget.page.groups,
                      maximumGroups: widget.page.maximumGroups,
                      faPlusIconUri: widget.page.faPlusIconUri,
                      controller: _nameController,
                      previousGroupId: _previousGroupId,
                      enabled: !_mutating,
                      canSubmit: _canSubmit,
                      onPreviousChanged: (value) {
                        setState(() => _previousGroupId = value ?? '0');
                      },
                      onCreate: _submit,
                      onFaPlus:
                          widget.page.faPlusUri == null ? null : _openFaPlus,
                    ),
                ],
              ),
              if (_mutating)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderOverviewCard extends StatelessWidget {
  const _FolderOverviewCard({
    required this.maximumFolders,
    required this.faPlusIconUri,
    required this.onFaPlus,
  });

  final int? maximumFolders;
  final Uri? faPlusIconUri;
  final VoidCallback? onFaPlus;

  @override
  Widget build(BuildContext context) {
    return _ManagementCard(
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
          _FaPlusPerkLink(
            text: 'Members get an additional increase to their max folder limit.',
            iconUri: faPlusIconUri,
            onTap: onFaPlus,
          ),
        ],
      ),
    );
  }
}

class _GroupCreateCard extends StatelessWidget {
  const _GroupCreateCard({
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
    return _ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeading('Folder Groups'),
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
          _FaPlusPerkLink(
            text:
                'Members get an additional increase to their max folder group limit.',
            iconUri: faPlusIconUri,
            onTap: onFaPlus,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller,
            enabled: enabled,
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
              backgroundColor: _managementAccent,
              foregroundColor: Colors.black,
            ),
            child: const SubmissionManagementShrinkableText('Create Group'),
          ),
        ],
      ),
    );
  }
}

class _GroupRenameCard extends StatelessWidget {
  const _GroupRenameCard({
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
    return _ManagementCard(
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
            decoration: const InputDecoration(
              label: SubmissionManagementShrinkableText('New group name'),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onRename(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: canSubmit ? onRename : null,
            style: OutlinedButton.styleFrom(foregroundColor: _managementAccent),
            child: const SubmissionManagementShrinkableText('Rename Group'),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
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
    return _ManagementCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_copy_outlined, color: _managementAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Material(
                        color: _managementAccent.withValues(alpha: 0.16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: const BorderSide(color: _managementAccent),
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
                                color: _managementAccent,
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
          if (folders.isNotEmpty) ...[
            const Divider(height: 24),
            for (var index = 0; index < folders.length; index++) ...[
              _FolderCard(
                folder: folders[index],
                color: folderColors[folders[index].name] ??
                    _fallbackFolderColor,
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
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
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
              color: _managementAccent,
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
    return _ManagementCard(child: content);
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

class _FolderColorDialog extends StatefulWidget {
  const _FolderColorDialog({
    required this.folderName,
    required this.initialColor,
  });

  final String folderName;
  final Color initialColor;

  @override
  State<_FolderColorDialog> createState() => _FolderColorDialogState();
}

class _FolderColorDialogState extends State<_FolderColorDialog> {
  static const List<Color> _presets = <Color>[
    Color(0xFFE53935),
    Color(0xFFE09321),
    Color(0xFFF9A825),
    Color(0xFF43A047),
    Color(0xFF00897B),
    Color(0xFF0097A7),
    Color(0xFF1E88E5),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
  ];

  late HSVColor _hsvColor;
  late final TextEditingController _hexController;
  String? _hexError;

  Color get _color => _hsvColor.toColor();

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _selectColor(Color color) {
    setState(() {
      _hsvColor = HSVColor.fromColor(color);
      _hexController.text = _hexFor(color);
      _hexController.selection = TextSelection.collapsed(
        offset: _hexController.text.length,
      );
      _hexError = null;
    });
  }

  void _updateSaturationAndValue(double saturation, double value) {
    setState(() {
      _hsvColor = _hsvColor.withSaturation(saturation).withValue(value);
      _hexController.text = _hexFor(_color);
      _hexError = null;
    });
  }

  void _updateHue(double hue) {
    setState(() {
      _hsvColor = _hsvColor.withHue(hue);
      _hexController.text = _hexFor(_color);
      _hexError = null;
    });
  }

  void _updateHex(String value) {
    final color = _parseHex(value);
    setState(() {
      _hexError = color == null
          ? 'Use #RRGGBB or Flutter 0xAARRGGBB format.'
          : null;
      if (color != null) _hsvColor = HSVColor.fromColor(color);
    });
  }

  String _hexFor(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  Color? _parseHex(String input) {
    var value = input.trim();
    if (value.startsWith('Color(') && value.endsWith(')')) {
      value = value.substring(6, value.length - 1).trim();
    }
    if (value.startsWith('#')) value = value.substring(1);
    if (value.toLowerCase().startsWith('0x')) value = value.substring(2);
    if (value.length == 3) {
      value = value.split('').map((character) => '$character$character').join();
    }
    if (value.length == 8) value = value.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) return null;
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final foreground =
        _color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
    final mediaQuery = MediaQuery.of(context);
    final dialogWidth =
        (mediaQuery.size.width - 36).clamp(244.0, 408.0).toDouble();
    final dialogHeight = (mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            48)
        .clamp(300.0, 680.0)
        .toDouble();
    final pickerWidth = dialogWidth - 40;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: _managementCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit folder color',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: foreground.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: SubmissionManagementShrinkableText(
                            widget.folderName,
                            maxLines: 2,
                            minFontSize: 10,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Drag anywhere below. The floating preview stays away from your finger.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SaturationValuePicker(
                        width: pickerWidth,
                        hsvColor: _hsvColor,
                        onChanged: _updateSaturationAndValue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hue',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _HuePicker(
                        width: pickerWidth,
                        hue: _hsvColor.hue,
                        onChanged: _updateHue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick colors',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _presets)
                            _ColorPresetButton(
                              color: preset,
                              selected:
                                  preset.toARGB32() == _color.toARGB32(),
                              onTap: () => _selectColor(preset),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _hexController,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Paste or enter a color',
                          hintText: '#E09321',
                          helperText: '#RRGGBB, RGB, or 0xAARRGGBB',
                          errorText: _hexError,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _updateHex,
                        onSubmitted: (_) {
                          if (_hexError == null) {
                            FocusScope.of(context).unfocus();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _hexError == null
                        ? () => Navigator.of(context).pop(_color)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: foreground,
                    ),
                    child: const Text('Save color'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EagerPointerDragArea extends StatelessWidget {
  const _EagerPointerDragArea({
    required this.onPositionChanged,
    required this.child,
  });

  final ValueChanged<Offset> onPositionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => onPositionChanged(event.localPosition),
        onPointerMove: (event) => onPositionChanged(event.localPosition),
        child: child,
      ),
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.width,
    required this.hsvColor,
    required this.onChanged,
  });

  final double width;
  final HSVColor hsvColor;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    const height = 190.0;
    final selection = Offset(
      hsvColor.saturation * width,
      (1 - hsvColor.value) * height,
    );
    final bubbleX =
        selection.dx.clamp(22.0, width - 22.0).toDouble() - 22;
    final bubbleCenterY =
        selection.dy > 70 ? selection.dy - 52 : selection.dy + 52;
    final bubbleY =
        bubbleCenterY.clamp(22.0, height - 22.0).toDouble() - 22;

    void update(Offset position) {
      onChanged(
        (position.dx / width).clamp(0.0, 1.0).toDouble(),
        (1 - position.dy / height).clamp(0.0, 1.0).toDouble(),
      );
    }

    return _EagerPointerDragArea(
      onPositionChanged: update,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SaturationValuePainter(hue: hsvColor.hue),
                ),
              ),
              Positioned(
                left: selection.dx.clamp(0.0, width).toDouble() - 10,
                top: selection.dy.clamp(0.0, height).toDouble() - 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black87, blurRadius: 3),
                      ],
                    ),
                    child: const SizedBox(width: 20, height: 20),
                  ),
                ),
              ),
              Positioned(
                left: bubbleX,
                top: bubbleY,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: hsvColor.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 44, height: 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) {
    return hue != oldDelegate.hue;
  }
}

class _HuePicker extends StatelessWidget {
  const _HuePicker({
    required this.width,
    required this.hue,
    required this.onChanged,
  });

  final double width;
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset position) {
      onChanged((position.dx / width).clamp(0.0, 1.0).toDouble() * 360);
    }

    return _EagerPointerDragArea(
      onPositionChanged: update,
      child: SizedBox(
        width: width,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                  border: Border.all(color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              left: (hue / 360 * width).clamp(0.0, width).toDouble() - 5,
              top: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 3),
                    ],
                  ),
                  child: const SizedBox(width: 10, height: 36),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPresetButton extends StatelessWidget {
  const _ColorPresetButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: _colorLabel(color),
      child: Material(
        color: color,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? Colors.white : Colors.white38,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    color: color.computeLuminance() > 0.42
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _colorLabel(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return 'Color ${value.substring(2).toUpperCase()}';
  }
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

class _FaPlusPerkLink extends StatefulWidget {
  const _FaPlusPerkLink({
    required this.text,
    required this.iconUri,
    required this.onTap,
  });

  final String text;
  final Uri? iconUri;
  final VoidCallback? onTap;

  @override
  State<_FaPlusPerkLink> createState() => _FaPlusPerkLinkState();
}

class _FaPlusPerkLinkState extends State<_FaPlusPerkLink> {
  late final TapGestureRecognizer _linkRecognizer;

  static const TextStyle _linkStyle = TextStyle(
    color: _managementAccent,
    fontWeight: FontWeight.w700,
  );

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = widget.onTap;
  }

  @override
  void didUpdateWidget(_FaPlusPerkLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    _linkRecognizer.onTap = widget.onTap;
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      link: widget.onTap != null,
      label: 'FA+ Member Perk: ${widget.text}',
      child: Text.rich(
        TextSpan(
          style: const TextStyle(color: Colors.white70, height: 1.3),
          children: [
            TextSpan(
              text: 'FA+',
              style: _linkStyle,
              recognizer: _linkRecognizer,
            ),
            if (widget.iconUri != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.translucent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FaNetworkImage(
                      widget.iconUri.toString(),
                      width: 14,
                      height: 14,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 14, height: 14),
                    ),
                  ),
                ),
              ),
            if (widget.iconUri == null) const TextSpan(text: ' '),
            TextSpan(
              text: 'Member Perk: ',
              style: _linkStyle,
              recognizer: _linkRecognizer,
            ),
            TextSpan(text: widget.text),
          ],
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _managementCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SubmissionManagementShrinkableText(
      text,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: SubmissionManagementShrinkableText(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return _ManagementCard(
      child: SubmissionManagementShrinkableText(
        text,
        style: const TextStyle(color: Colors.white60),
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
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: _managementAccent,
                foregroundColor: Colors.black,
              ),
              child: const SubmissionManagementShrinkableText('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
