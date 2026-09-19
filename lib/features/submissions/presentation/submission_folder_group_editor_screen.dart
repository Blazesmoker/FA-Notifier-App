import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_cards.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';

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
        backgroundColor: managementBackground,
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
                    GroupRenameCard(
                      group: widget.group!,
                      controller: _nameController,
                      enabled: !_mutating,
                      canSubmit: _canSubmit,
                      onRename: _submit,
                    )
                  else
                    GroupCreateCard(
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
