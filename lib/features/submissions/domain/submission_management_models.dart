enum SubmissionManagementActionType {
  assignToFolder,
  createFolder,
  unassignFromFolders,
  moveToScraps,
  moveToGallery,
  deleteSubmissions,
}

class FaManagementFormValue {
  const FaManagementFormValue(this.name, this.value);

  final String name;
  final String value;
}

class FaManagementFormAction {
  FaManagementFormAction({
    required this.uri,
    required Iterable<FaManagementFormValue> fields,
    this.submitName,
    this.submitValue,
  }) : fields = List<FaManagementFormValue>.unmodifiable(fields);

  final Uri uri;
  final List<FaManagementFormValue> fields;
  final String? submitName;
  final String? submitValue;

  List<FaManagementFormValue> buildFields({
    Map<String, String?> overrides = const <String, String?>{},
    Iterable<FaManagementFormValue> additions =
        const <FaManagementFormValue>[],
    bool includeSubmit = true,
  }) {
    final result = <FaManagementFormValue>[
      for (final field in fields)
        if (!overrides.containsKey(field.name)) field,
    ];
    for (final entry in overrides.entries) {
      final value = entry.value;
      if (value != null) result.add(FaManagementFormValue(entry.key, value));
    }
    result.addAll(additions);
    final name = submitName;
    final value = submitValue;
    if (includeSubmit && name != null && value != null) {
      result.add(FaManagementFormValue(name, value));
    }
    return result;
  }
}

class FaSubmissionFolderOption {
  const FaSubmissionFolderOption({
    required this.id,
    required this.label,
    this.groupLabel,
  });

  final String id;
  final String label;
  final String? groupLabel;
}

class FaManagedSubmission {
  FaManagedSubmission({
    required this.id,
    required this.title,
    required this.thumbnailUri,
    required this.postUri,
    required this.rating,
    required this.width,
    required this.height,
    required this.missingTags,
    required Iterable<String> assignedFolders,
  }) : assignedFolders = List<String>.unmodifiable(assignedFolders);

  final String id;
  final String title;
  final Uri thumbnailUri;
  final Uri postUri;
  final String? rating;
  final double width;
  final double height;
  final bool missingTags;
  final List<String> assignedFolders;
}

class FaSubmissionManagementPage {
  FaSubmissionManagementPage({
    required this.sourceUri,
    required Iterable<FaSubmissionFolderOption> folders,
    required Iterable<FaManagedSubmission> submissions,
    required Map<SubmissionManagementActionType, FaManagementFormAction>
        actions,
    this.selectedFolderId,
    this.newerUri,
    this.olderUri,
    this.mainGalleryUri,
    this.scrapsUri,
    this.currentPage = 1,
  })  : folders = List<FaSubmissionFolderOption>.unmodifiable(folders),
        submissions = List<FaManagedSubmission>.unmodifiable(submissions),
        actions = Map<SubmissionManagementActionType,
            FaManagementFormAction>.unmodifiable(actions);

  final Uri sourceUri;
  final List<FaSubmissionFolderOption> folders;
  final List<FaManagedSubmission> submissions;
  final Map<SubmissionManagementActionType, FaManagementFormAction> actions;
  final String? selectedFolderId;
  final Uri? newerUri;
  final Uri? olderUri;
  final Uri? mainGalleryUri;
  final Uri? scrapsUri;
  final int currentPage;
}

class FaContentManagementResult {
  const FaContentManagementResult({
    required this.success,
    this.statusCode,
    this.message,
    this.partial = false,
    this.indeterminate = false,
    this.changed = false,
    this.submissionPage,
    this.remainingSubmissionIds = const <String>{},
  });

  final bool success;
  final int? statusCode;
  final String? message;
  final bool partial;
  final bool indeterminate;
  final bool changed;
  final FaSubmissionManagementPage? submissionPage;
  final Set<String> remainingSubmissionIds;
}

class FaManagedFolderGroup {
  const FaManagedFolderGroup({
    required this.id,
    required this.name,
    this.moveUpAction,
    this.moveDownAction,
    this.deleteAction,
    this.addFolderAction,
  });

  final String id;
  final String name;
  final FaManagementFormAction? moveUpAction;
  final FaManagementFormAction? moveDownAction;
  final FaManagementFormAction? deleteAction;
  final FaManagementFormAction? addFolderAction;
}

class FaManagedFolder {
  const FaManagedFolder({
    required this.id,
    required this.name,
    required this.submissionCount,
    required this.groupId,
    this.description,
    this.galleryUri,
    this.iconUri,
    this.moveUpAction,
    this.moveDownAction,
    this.editAction,
    this.deleteAction,
    this.addSubmissionsAction,
  });

  final String id;
  final String name;
  final int submissionCount;
  final String groupId;
  final String? description;
  final Uri? galleryUri;
  final Uri? iconUri;
  final FaManagementFormAction? moveUpAction;
  final FaManagementFormAction? moveDownAction;
  final FaManagementFormAction? editAction;
  final FaManagementFormAction? deleteAction;
  final FaManagementFormAction? addSubmissionsAction;
}

class FaFolderManagementPage {
  FaFolderManagementPage({
    required this.sourceUri,
    required this.maximumFolders,
    required this.maximumGroups,
    required Iterable<FaManagedFolderGroup> groups,
    required Iterable<FaManagedFolder> folders,
    this.faPlusUri,
    this.faPlusIconUri,
    this.createFolderUri,
    this.createGroupAction,
    this.renameGroupAction,
  })  : groups = List<FaManagedFolderGroup>.unmodifiable(groups),
        folders = List<FaManagedFolder>.unmodifiable(folders);

  final Uri sourceUri;
  final int? maximumFolders;
  final int? maximumGroups;
  final List<FaManagedFolderGroup> groups;
  final List<FaManagedFolder> folders;
  final Uri? faPlusUri;
  final Uri? faPlusIconUri;
  final Uri? createFolderUri;
  final FaManagementFormAction? createGroupAction;
  final FaManagementFormAction? renameGroupAction;
}

class FaFolderEditorOption {
  const FaFolderEditorOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

enum FaFolderEditorFieldType {
  text,
  multiline,
  select,
}

class FaFolderEditorField {
  FaFolderEditorField({
    required this.name,
    required this.label,
    required this.type,
    required Iterable<String> selectedValues,
    required Iterable<FaFolderEditorOption> options,
    this.requiredField = false,
    this.maxLength,
  })  : selectedValues = List<String>.unmodifiable(selectedValues),
        options = List<FaFolderEditorOption>.unmodifiable(options);

  final String name;
  final String label;
  final FaFolderEditorFieldType type;
  final List<String> selectedValues;
  final List<FaFolderEditorOption> options;
  final bool requiredField;
  final int? maxLength;
}

class FaFolderEditorPage {
  FaFolderEditorPage({
    required this.sourceUri,
    required this.title,
    required this.submitLabel,
    required this.isEditing,
    required this.action,
    required Iterable<FaFolderEditorField> fields,
    required Iterable<String> supportingTexts,
  })  : fields = List<FaFolderEditorField>.unmodifiable(fields),
        supportingTexts = List<String>.unmodifiable(supportingTexts);

  final Uri sourceUri;
  final String title;
  final String submitLabel;
  final bool isEditing;
  final FaManagementFormAction action;
  final List<FaFolderEditorField> fields;
  final List<String> supportingTexts;
}

class SubmissionManagementRequestException implements Exception {
  const SubmissionManagementRequestException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
