import 'package:fanotifier/features/submissions/data/submission_management_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_management_remote_data_source.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';

class SubmissionManagementRepositoryImpl
    implements SubmissionManagementRepository {
  const SubmissionManagementRepositoryImpl({
    SubmissionManagementRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource = remoteDataSource ??
            const SubmissionManagementRemoteDataSource();

  static final Uri _submissionsUri =
      Uri.parse('https://www.furaffinity.net$faSubmissionManagementPath');
  static final Uri _foldersUri =
      Uri.parse('https://www.furaffinity.net$faFolderManagementPath');

  final SubmissionManagementRemoteDataSource _remoteDataSource;

  @override
  Future<FaSubmissionManagementPage> loadSubmissions({
    Uri? uri,
    FaManagementFormAction? navigationAction,
  }) async {
    if (navigationAction != null) {
      _requireSubmissionNavigationAction(navigationAction);
      final response = await _remoteDataSource.postAuthenticated(
        navigationAction.uri,
        referer: _foldersUri,
        fields: navigationAction.buildFields(),
      );
      if (response.statusCode == 302) {
        final redirect = _safeRedirect(
          navigationAction.uri,
          response.headers['location'],
          _isSubmissionPageUri,
        );
        return loadSubmissions(uri: redirect ?? _submissionsUri);
      }
      _requireOk(response);
      return parseSubmissionManagementPage(
        response.body,
        sourceUri: navigationAction.uri,
      );
    }

    final target = uri ?? _submissionsUri;
    if (!_isSubmissionPageUri(target)) {
      throw const SubmissionManagementRequestException(
        'Fur Affinity returned an unsafe submissions management URL.',
      );
    }
    final response = await _remoteDataSource.getAuthenticated(target);
    _requireOk(response);
    return parseSubmissionManagementPage(response.body, sourceUri: target);
  }

  @override
  Future<FaContentManagementResult> applySubmissionAction({
    required FaSubmissionManagementPage page,
    required SubmissionManagementActionType actionType,
    required Set<String> submissionIds,
    String? folderId,
    String? newFolderName,
  }) async {
    final action = page.actions[actionType];
    if (action == null || !_isExactSubmissionFormAction(action, actionType)) {
      return const FaContentManagementResult(
        success: false,
        message: 'Fur Affinity did not provide a valid action for this request.',
      );
    }
    final pageIds = page.submissions.map((item) => item.id).toSet();
    if (!pageIds.containsAll(submissionIds)) {
      return const FaContentManagementResult(
        success: false,
        message: 'The selected submissions are no longer on this page. Reload and try again.',
      );
    }
    if (actionType != SubmissionManagementActionType.createFolder &&
        submissionIds.isEmpty) {
      return const FaContentManagementResult(
        success: false,
        message: 'Select at least one submission.',
      );
    }

    final overrides = <String, String?>{};
    if (actionType == SubmissionManagementActionType.assignToFolder) {
      final selectedFolder = folderId?.trim() ?? '';
      if (selectedFolder.isEmpty ||
          !page.folders.any((folder) => folder.id == selectedFolder)) {
        return const FaContentManagementResult(
          success: false,
          message: 'Select a valid folder.',
        );
      }
      overrides['assign_folder_id'] = selectedFolder;
    }
    if (actionType == SubmissionManagementActionType.createFolder) {
      final name = newFolderName?.trim() ?? '';
      if (name.isEmpty) {
        return const FaContentManagementResult(
          success: false,
          message: 'Enter a folder name.',
        );
      }
      overrides['create_folder_name'] = name;
    }
    final selectedFields = submissionIds
        .map((id) => FaManagementFormValue('submission_ids[]', id));
    try {
      final response = await _remoteDataSource.postAuthenticated(
        action.uri,
        referer: page.sourceUri,
        fields: action.buildFields(
          overrides: overrides,
          additions: selectedFields,
        ),
      );
      if (response.statusCode == 302) {
        final refreshed = await _tryReloadSubmissions(
          page,
          response.headers['location'],
        );
        return FaContentManagementResult(
          success: true,
          statusCode: 302,
          changed: true,
          submissionPage: refreshed,
        );
      }
      if (actionType == SubmissionManagementActionType.deleteSubmissions &&
          const <int>{408, 500, 502, 503, 504}
              .contains(response.statusCode)) {
        return await _verifyDeletion(page, submissionIds);
      }
      return FaContentManagementResult(
        success: false,
        statusCode: response.statusCode,
        message: extractSubmissionManagementResponseMessage(response.body) ??
            'Fur Affinity returned HTTP ${response.statusCode} without confirming the action.',
      );
    } catch (error) {
      if (actionType == SubmissionManagementActionType.deleteSubmissions &&
          _remoteDataSource.isRecoverable(error)) {
        return _verifyDeletion(page, submissionIds);
      }
      if (_remoteDataSource.isRecoverable(error)) {
        return const FaContentManagementResult(
          success: false,
          indeterminate: true,
          message:
              'The request was interrupted. Fur Affinity may have processed it. Do not repeat the action until you have reloaded and reviewed the page.',
        );
      }
      return FaContentManagementResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaContentManagementResult> moveProfileScrapsToGallery(
    Set<String> submissionIds,
  ) async {
    if (submissionIds.isEmpty) {
      return const FaContentManagementResult(
        success: false,
        message: 'Select at least one scrap.',
      );
    }
    if (submissionIds.any((id) => !RegExp(r'^\d+$').hasMatch(id))) {
      return const FaContentManagementResult(
        success: false,
        message: 'The scrap selection contains an invalid ID.',
      );
    }
    final sortedIds = submissionIds.toList()..sort();
    try {
      final result = await _remoteDataSource.getThenPostAuthenticated(
        _submissionsUri,
        buildPostRequest: (response) {
          _requireOk(response);
          final page = parseSubmissionManagementPage(
            response.body,
            sourceUri: _submissionsUri,
          );
          final action =
              page.actions[SubmissionManagementActionType.moveToGallery];
          if (action == null ||
              !_isExactSubmissionFormAction(
                action,
                SubmissionManagementActionType.moveToGallery,
              )) {
            throw const SubmissionManagementRequestException(
              'Fur Affinity did not provide a valid Move to Gallery action.',
            );
          }
          return FaManagementPostRequest(
            uri: action.uri,
            referer: page.sourceUri,
            fields: action.buildFields(
              additions: [
                for (final id in sortedIds)
                  FaManagementFormValue('submission_ids[]', id),
              ],
            ),
          );
        },
      );
      final response = result.postResponse;
      if (response.statusCode == 302) {
        return const FaContentManagementResult(
          success: true,
          statusCode: 302,
          changed: true,
        );
      }
      if (const <int>{408, 500, 502, 503, 504}
          .contains(response.statusCode)) {
        return FaContentManagementResult(
          success: false,
          statusCode: response.statusCode,
          indeterminate: true,
          message:
              'Fur Affinity returned HTTP ${response.statusCode} after the request was sent and may have moved some scraps. Refresh and review them before trying again.',
        );
      }
      return FaContentManagementResult(
        success: false,
        statusCode: response.statusCode,
        message: extractSubmissionManagementResponseMessage(response.body) ??
            'Fur Affinity returned HTTP ${response.statusCode} without confirming the action.',
      );
    } catch (error) {
      if (error is FaManagementGetPostException) {
        if (error.postAttempted && _remoteDataSource.isRecoverable(error)) {
          return const FaContentManagementResult(
            success: false,
            indeterminate: true,
            message:
                'The request was interrupted. Fur Affinity may have moved some scraps. Refresh and review them before trying again.',
          );
        }
        return FaContentManagementResult(
          success: false,
          message: error.postAttempted
              ? '${error.cause}'
              : 'Could not load a fresh Fur Affinity form. Nothing was sent. ${error.cause}',
        );
      }
      return FaContentManagementResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaFolderManagementPage> loadFolders() async {
    final response = await _remoteDataSource.getAuthenticated(_foldersUri);
    _requireOk(response);
    return parseFolderManagementPage(response.body, sourceUri: _foldersUri);
  }

  @override
  Future<FaContentManagementResult> applyFolderAction(
    FaManagementFormAction action, {
    Map<String, String?> overrides = const <String, String?>{},
  }) async {
    if (!_isFolderMutationAction(action, overrides)) {
      return const FaContentManagementResult(
        success: false,
        message: 'Fur Affinity did not provide a valid folder action.',
      );
    }
    try {
      final response = await _remoteDataSource.postAuthenticated(
        action.uri,
        referer: _foldersUri,
        fields: action.buildFields(overrides: overrides),
      );
      if (response.statusCode == 302) {
        return const FaContentManagementResult(
          success: true,
          statusCode: 302,
          changed: true,
        );
      }
      return FaContentManagementResult(
        success: false,
        statusCode: response.statusCode,
        message: extractSubmissionManagementResponseMessage(response.body) ??
            'Fur Affinity returned HTTP ${response.statusCode} without confirming the action.',
      );
    } catch (error) {
      if (_remoteDataSource.isRecoverable(error)) {
        return const FaContentManagementResult(
          success: false,
          indeterminate: true,
          message:
              'The request was interrupted. Fur Affinity may have processed it; reload before trying again.',
        );
      }
      return FaContentManagementResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaFolderEditorPage> loadFolderEditor({
    Uri? uri,
    FaManagementFormAction? navigationAction,
  }) async {
    if (navigationAction != null) {
      _requireFolderEditorNavigationAction(navigationAction);
      final response = await _remoteDataSource.postAuthenticated(
        navigationAction.uri,
        referer: _foldersUri,
        fields: navigationAction.buildFields(),
      );
      if (response.statusCode == 302) {
        final redirect = _safeRedirect(
          navigationAction.uri,
          response.headers['location'],
          _isFolderEditorUri,
        );
        if (redirect != null) return loadFolderEditor(uri: redirect);
      }
      _requireOk(response);
      return parseFolderEditorPage(
        response.body,
        sourceUri: navigationAction.uri,
      );
    }

    final target = uri;
    if (target == null || !_isFolderEditorUri(target)) {
      throw const SubmissionManagementRequestException(
        'Fur Affinity returned an unsafe folder editor URL.',
      );
    }
    final response = await _remoteDataSource.getAuthenticated(target);
    _requireOk(response);
    return parseFolderEditorPage(response.body, sourceUri: target);
  }

  @override
  Future<FaContentManagementResult> saveFolderEditor({
    required FaFolderEditorPage page,
    required Map<String, List<String>> values,
  }) async {
    const expectedFieldNames = <String>{
      'group_id',
      'create_group_name',
      'folder_name',
      'folder_description',
    };
    final actionPath = _normalizePath(page.action.uri.path);
    final expectedPath = page.isEditing ? faFolderEditPath : faFolderAddPath;
    final actionFields = page.action.fields;
    final formFieldNames = page.fields.map((field) => field.name).toSet();
    if (!_isFolderEditorUri(page.action.uri) ||
        actionPath != expectedPath ||
        page.action.submitName != 'key' ||
        !_isFaFormKey(page.action.submitValue) ||
        actionFields.length != 1 ||
        actionFields.single.name != 'folder_id' ||
        (page.isEditing &&
            !RegExp(r'^\d+$').hasMatch(actionFields.single.value)) ||
        (!page.isEditing && actionFields.single.value.isNotEmpty) ||
        formFieldNames.length != expectedFieldNames.length ||
        !formFieldNames.containsAll(expectedFieldNames) ||
        values.length != expectedFieldNames.length ||
        !values.keys.toSet().containsAll(expectedFieldNames)) {
      return const FaContentManagementResult(
        success: false,
        message: 'The folder form changed. Reload it before saving.',
      );
    }
    final groupValues = values['group_id'] ?? const <String>[];
    final folderNames = values['folder_name'] ?? const <String>[];
    final groupField = page.fields.firstWhere(
      (field) => field.name == 'group_id',
    );
    if (groupValues.length != 1 ||
        !RegExp(r'^\d+$').hasMatch(groupValues.single) ||
        !groupField.options.any(
          (option) => option.value == groupValues.single,
        ) ||
        folderNames.length != 1 ||
        folderNames.single.trim().isEmpty ||
        folderNames.single.length > 64 ||
        values.values.any((submitted) => submitted.length != 1)) {
      return const FaContentManagementResult(
        success: false,
        message: 'Check the folder name and group before saving.',
      );
    }
    for (final field in page.fields) {
      final submitted = values[field.name] ?? const <String>[];
      if (field.requiredField &&
          submitted.every((value) => value.trim().isEmpty)) {
        return FaContentManagementResult(
          success: false,
          message: '${field.label} is required.',
        );
      }
    }
    final additions = <FaManagementFormValue>[
      for (final field in page.fields)
        for (final value in values[field.name] ?? const <String>[])
          FaManagementFormValue(field.name, value),
    ];
    try {
      final response = await _remoteDataSource.postAuthenticated(
        page.action.uri,
        referer: page.sourceUri,
        fields: page.action.buildFields(additions: additions),
      );
      if (response.statusCode == 302) {
        return const FaContentManagementResult(
          success: true,
          statusCode: 302,
          changed: true,
        );
      }
      return FaContentManagementResult(
        success: false,
        statusCode: response.statusCode,
        message: extractSubmissionManagementResponseMessage(response.body) ??
            'Fur Affinity returned HTTP ${response.statusCode} without confirming the change.',
      );
    } catch (error) {
      if (_remoteDataSource.isRecoverable(error)) {
        return const FaContentManagementResult(
          success: false,
          indeterminate: true,
          message:
              'The request was interrupted. Fur Affinity may have saved the folder; reload before trying again.',
        );
      }
      return FaContentManagementResult(success: false, message: '$error');
    }
  }

  Future<FaContentManagementResult> _verifyDeletion(
    FaSubmissionManagementPage page,
    Set<String> submittedIds,
  ) async {
    try {
      final refreshed = await loadSubmissions(uri: page.sourceUri);
      final currentIds = refreshed.submissions.map((item) => item.id).toSet();
      final remaining = submittedIds.intersection(currentIds);
      final removedCount = submittedIds.length - remaining.length;
      if (remaining.isEmpty) {
        return FaContentManagementResult(
          success: true,
          message: 'Deletion completed even though Fur Affinity timed out.',
          changed: true,
          submissionPage: refreshed,
        );
      }
      if (removedCount > 0) {
        return FaContentManagementResult(
          success: false,
          partial: true,
          message:
              'Fur Affinity made progress before timing out. $removedCount removed, ${remaining.length} still remain. Review the selection and repeat Delete Submissions to continue.',
          changed: true,
          submissionPage: refreshed,
          remainingSubmissionIds: remaining,
        );
      }
      return FaContentManagementResult(
        success: false,
        indeterminate: true,
        message:
            'Fur Affinity timed out and did not confirm deletion. Nothing visible on this page changed; reload before deciding whether to retry.',
        submissionPage: refreshed,
        remainingSubmissionIds: remaining,
      );
    } catch (_) {
      return FaContentManagementResult(
        success: false,
        indeterminate: true,
        message:
            'Fur Affinity timed out and may have deleted some submissions. Reload the page before trying again.',
        remainingSubmissionIds: submittedIds,
      );
    }
  }

  Future<FaSubmissionManagementPage?> _tryReloadSubmissions(
    FaSubmissionManagementPage page,
    String? location,
  ) async {
    try {
      final redirect = _safeRedirect(
        page.sourceUri,
        location,
        _isSubmissionPageUri,
      );
      return await loadSubmissions(uri: redirect ?? page.sourceUri);
    } catch (_) {
      return null;
    }
  }

  void _requireOk(FaManagementHttpResponse response) {
    if (response.statusCode == 200) return;
    throw SubmissionManagementRequestException(
      extractSubmissionManagementResponseMessage(response.body) ??
          'Fur Affinity returned HTTP ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  void _requireSubmissionNavigationAction(FaManagementFormAction action) {
    if (!_isSafeFaUri(action.uri) ||
        _normalizePath(action.uri.path) != faSubmissionManagementPath ||
        action.submitName != null ||
        action.submitValue != null ||
        action.fields.length != 1 ||
        action.fields.any((field) {
          return field.name != 'folder_id' ||
              !RegExp(r'^\d+$').hasMatch(field.value);
        })) {
      throw const SubmissionManagementRequestException(
        'Fur Affinity returned an unsafe folder submissions action.',
      );
    }
  }

  void _requireFolderEditorNavigationAction(FaManagementFormAction action) {
    if (!_isFolderEditorUri(action.uri) ||
        action.submitName != null ||
        action.submitValue != null ||
        action.fields.length != 1 ||
        action.fields.any((field) {
          return !const <String>{'folder_id', 'group_id'}.contains(field.name) ||
              !RegExp(r'^\d+$').hasMatch(field.value);
        })) {
      throw const SubmissionManagementRequestException(
        'Fur Affinity returned an unsafe folder editor action.',
      );
    }
  }

  bool _isExactSubmissionFormAction(
    FaManagementFormAction action,
    SubmissionManagementActionType type,
  ) {
    const expectedNames = <SubmissionManagementActionType, String>{
      SubmissionManagementActionType.assignToFolder: 'assign_folder_submit',
      SubmissionManagementActionType.createFolder: 'create_folder_submit',
      SubmissionManagementActionType.unassignFromFolders:
          'remove_from_folders_submit',
      SubmissionManagementActionType.moveToScraps: 'move_to_scraps_submit',
      SubmissionManagementActionType.moveToGallery:
          'move_from_scraps_submit',
      SubmissionManagementActionType.deleteSubmissions:
          'delete_submissions_submit',
    };
    final submitValue = action.submitValue;
    final hasExpectedSubmitValue =
        type == SubmissionManagementActionType.deleteSubmissions
            ? submitValue == 'Delete Submission'
            : _isFaFormKey(submitValue);
    return _isSafeFaUri(action.uri) &&
        _normalizePath(action.uri.path) == faSubmissionManagementPath &&
        action.submitName == expectedNames[type] &&
        hasExpectedSubmitValue &&
        action.fields.length == 2 &&
        action.fields.map((field) => field.name).toSet().length == 2 &&
        action.fields.any((field) {
          return field.name == 'assign_folder_id' &&
              RegExp(r'^\d+$').hasMatch(field.value);
        }) &&
        action.fields.any((field) => field.name == 'create_folder_name');
  }

  bool _isFolderMutationAction(
    FaManagementFormAction action,
    Map<String, String?> overrides,
  ) {
    if (!_isSafeFaUri(action.uri) ||
        action.submitName != 'key' ||
        !_isFaFormKey(action.submitValue)) {
      return false;
    }
    final path = _normalizePath(action.uri.path);
    if (path == '/controls/folders/submissions/group/add/') {
      return _hasExactActionFields(
            action,
            const <String>{'group_name', 'prev_group'},
          ) &&
          overrides.keys.toSet().containsAll(
            const <String>{'group_name', 'prev_group'},
          ) &&
          overrides.length == 2 &&
          (overrides['group_name']?.trim().isNotEmpty ?? false) &&
          RegExp(r'^\d+$').hasMatch(overrides['prev_group'] ?? '');
    }
    if (path == '/controls/folders/submissions/group/edit/') {
      return _hasExactActionFields(
            action,
            const <String>{'group_id', 'group_name'},
          ) &&
          overrides.keys.toSet().containsAll(
            const <String>{'group_id', 'group_name'},
          ) &&
          overrides.length == 2 &&
          RegExp(r'^\d+$').hasMatch(overrides['group_id'] ?? '') &&
          (overrides['group_name']?.trim().isNotEmpty ?? false);
    }
    if (overrides.isNotEmpty) return false;
    if (path == '/controls/folders/submissions/group/delete/') {
      return _hasExactActionFields(action, const <String>{'group_id'}) &&
          RegExp(r'^\d+$').hasMatch(
            _actionFieldValue(action, 'group_id') ?? '',
          );
    }
    if (path == '/controls/folders/submissions/folder/delete/') {
      return _hasExactActionFields(action, const <String>{'folder_id'}) &&
          RegExp(r'^\d+$').hasMatch(
            _actionFieldValue(action, 'folder_id') ?? '',
          );
    }
    if (path == '/controls/folders/submissions/group/move-to/') {
      return _isExactMoveAction(action, 'group_id');
    }
    if (path == '/controls/folders/submissions/folder/move-to/') {
      return _isExactMoveAction(action, 'folder_id');
    }
    return false;
  }

  bool _isExactMoveAction(FaManagementFormAction action, String idName) {
    final direction = _actionFieldValue(action, 'direction');
    return _hasExactActionFields(
          action,
          <String>{'direction', idName},
        ) &&
        const <String>{'up', 'down'}.contains(direction) &&
        RegExp(r'^\d+$').hasMatch(_actionFieldValue(action, idName) ?? '');
  }

  bool _hasExactActionFields(
    FaManagementFormAction action,
    Set<String> expectedNames,
  ) {
    final names = action.fields.map((field) => field.name).toSet();
    return action.fields.length == expectedNames.length &&
        names.length == expectedNames.length &&
        names.containsAll(expectedNames);
  }

  String? _actionFieldValue(FaManagementFormAction action, String name) {
    for (final field in action.fields) {
      if (field.name == name) return field.value;
    }
    return null;
  }

  bool _isFaFormKey(String? value) {
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value ?? '');
  }

  bool _isSubmissionPageUri(Uri uri) {
    if (!_isSafeFaUri(uri)) return false;
    final path = _normalizePath(uri.path);
    return path == faSubmissionManagementPath ||
        RegExp(r'^/controls/submissions/\d+/$').hasMatch(path);
  }

  bool _isFolderEditorUri(Uri uri) {
    if (!_isSafeFaUri(uri)) return false;
    final path = _normalizePath(uri.path);
    return path == faFolderAddPath || path == faFolderEditPath;
  }

  bool _isSafeFaUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() == 'https' &&
        (host == 'www.furaffinity.net' || host == 'furaffinity.net') &&
        (!uri.hasPort || uri.port == 443) &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Uri? _safeRedirect(
    Uri base,
    String? location,
    bool Function(Uri uri) validator,
  ) {
    final raw = location?.trim() ?? '';
    if (raw.isEmpty) return null;
    final uri = base.resolve(raw);
    return validator(uri) ? uri : null;
  }

  String _normalizePath(String path) {
    return path.endsWith('/') ? path : '$path/';
  }
}
