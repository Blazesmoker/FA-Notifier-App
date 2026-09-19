import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_widgets.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

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
        backgroundColor: managementBackground,
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
                    ? managementAccent
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
      return ErrorState(error: _loadError!, onRetry: _load);
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
              ManagementCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'The save result is unknown. To prevent a duplicate folder, this form cannot be submitted again. Return to Folders and review the reloaded list.',
                      style: TextStyle(
                        color: managementAccent,
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
            ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardHeading('Put in Group'),
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
            ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardHeading('Folder Name'),
                  const SizedBox(height: 12),
                  _buildTextField(folderName),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ManagementCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardHeading('Folder Description'),
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
                      backgroundColor: managementAccent,
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
      style: const TextStyle(color: Colors.white),
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
