import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';

abstract interface class SubmissionManagementRepository {
  Future<FaSubmissionManagementPage> loadSubmissions({
    Uri? uri,
    FaManagementFormAction? navigationAction,
  });

  Future<FaContentManagementResult> applySubmissionAction({
    required FaSubmissionManagementPage page,
    required SubmissionManagementActionType actionType,
    required Set<String> submissionIds,
    String? folderId,
    String? newFolderName,
  });

  Future<FaContentManagementResult> moveProfileScrapsToGallery(
    Set<String> submissionIds,
  );

  Future<FaFolderManagementPage> loadFolders();

  Future<FaContentManagementResult> applyFolderAction(
    FaManagementFormAction action, {
    Map<String, String?> overrides,
  });

  Future<FaFolderEditorPage> loadFolderEditor({
    Uri? uri,
    FaManagementFormAction? navigationAction,
  });

  Future<FaContentManagementResult> saveFolderEditor({
    required FaFolderEditorPage page,
    required Map<String, List<String>> values,
  });
}
