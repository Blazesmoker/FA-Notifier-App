import 'dart:collection';
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'widgets/submission_management_styles.dart';

class ManageSubmissionsController {
  ManageSubmissionsController({
    required this._repository,
    required this._folderColorRepository,
    required this._isMounted,
    required this._updateState,
    required this._confirmDelete,
    required this._showMessage,
  });

  final SubmissionManagementRepository _repository;
  final SubmissionFolderColorRepository _folderColorRepository;
  final bool Function() _isMounted;
  final void Function(VoidCallback) _updateState;
  final Future<bool> Function(FaSubmissionManagementPage) _confirmDelete;
  final void Function(String, {bool success, bool warning, bool error})
  _showMessage;
  final Set<String> _selectedIds = <String>{};
  Map<String, Color> _folderColors = const <String, Color>{};
  FaSubmissionManagementPage? _page;
  Object? _loadError;
  bool _loading = true;
  bool _mutating = false;
  bool _changed = false;

  Set<String> get selectedIds => UnmodifiableSetView(_selectedIds);

  Map<String, Color> get folderColors => UnmodifiableMapView(_folderColors);

  FaSubmissionManagementPage? get page => _page;

  Object? get loadError => _loadError;

  bool get loading => _loading;

  bool get mutating => _mutating;

  bool get changed => _changed;

  Future<void> load({
    Uri? uri,
    FaManagementFormAction? navigationAction,
    bool resetDrafts = false,
  }) async {
    if (_loading && _page != null) return;
    _updateState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _repository.loadSubmissions(
        uri: uri,
        navigationAction: navigationAction,
      );
      final folderColors = await _loadFolderColors(page);
      if (!_isMounted()) return;
      _setPage(page, folderColors: folderColors, resetDrafts: resetDrafts);
    } catch (error) {
      if (!_isMounted()) return;
      _updateState(() {
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
    _updateState(() {
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
    _updateState(_selectedIds.clear);
  }

  void toggleSubmission(String id) {
    if (_mutating) return;
    _updateState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void selectAll() {
    final page = _page;
    if (page == null || _mutating) return;
    final allIds = page.submissions.map((item) => item.id).toSet();
    _updateState(() {
      _selectedIds.addAll(allIds);
    });
  }

  void deselectAll() {
    if (_mutating) return;
    _updateState(_selectedIds.clear);
  }

  bool allSelected(FaSubmissionManagementPage page) {
    if (page.submissions.isEmpty) return false;
    final allIds = page.submissions.map((submission) => submission.id);
    return _selectedIds.length == page.submissions.length &&
        allIds.every(_selectedIds.contains);
  }

  List<FaManagedSubmission> selectedSubmissions(
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
        for (final entry in storedColors.entries) entry.key: Color(entry.value),
      };
    } catch (_) {
      return <String, Color>{
        for (final name in names) name: fallbackFolderColor,
      };
    }
  }

  Future<void> applyAction(
    SubmissionManagementActionType actionType, {
    String? folderId,
    String? newFolderName,
  }) async {
    final page = _page;
    if (page == null || _mutating) return;
    if (actionType == SubmissionManagementActionType.deleteSubmissions) {
      final confirmed = await _confirmDelete(page);
      if (!_isMounted() || !confirmed) return;
    }
    _updateState(() => _mutating = true);
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
      if (!_isMounted()) return;
      _updateState(() => _mutating = false);
      _showMessage('$error', error: true);
      return;
    }
    if (!_isMounted()) return;
    _updateState(() => _mutating = false);
    if (result.changed) _changed = true;
    if (result.success) {
      _clearDrafts();
      final refreshed = result.submissionPage;
      if (refreshed != null) {
        final folderColors = await _loadFolderColors(refreshed);
        if (!_isMounted()) return;
        _setPage(refreshed, folderColors: folderColors, resetDrafts: true);
      } else {
        await load(uri: page.sourceUri, resetDrafts: true);
      }
    } else if (result.partial || result.indeterminate) {
      final refreshed = result.submissionPage;
      if (refreshed != null) {
        final folderColors = await _loadFolderColors(refreshed);
        if (!_isMounted()) return;
        _setPage(refreshed, folderColors: folderColors, resetDrafts: false);
      } else {
        await load(uri: page.sourceUri, resetDrafts: false);
      }
      if (!_isMounted()) return;
      final remaining = result.remainingSubmissionIds;
      if (remaining.isNotEmpty) {
        _updateState(() {
          _selectedIds
            ..clear()
            ..addAll(
              remaining.where(
                (id) =>
                    _page?.submissions.any((item) => item.id == id) ?? false,
              ),
            );
        });
      }
    }
    if (!_isMounted()) return;
    _showResult(result);
  }

  void _showResult(FaContentManagementResult result) {
    final message =
        result.message ??
        (result.success ? 'Changes applied.' : 'The change was not applied.');
    _showMessage(
      message,
      success: result.success,
      warning: result.partial || result.indeterminate,
      error: !result.success && !result.partial && !result.indeterminate,
    );
  }
}
