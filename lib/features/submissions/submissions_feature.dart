import 'package:fanotifier/features/submissions/data/edit_submission_page_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/finalize_submission_service.dart';
import 'package:fanotifier/features/submissions/data/submission_details_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_description_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_favorite_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_folder_color_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_management_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submissions_repository_impl.dart';
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/domain/submissions_repository.dart';
import 'package:fanotifier/shared/fa/domain/submission_comment_repository.dart';
import 'package:fanotifier/shared/fa/domain/fa_content_block_repository.dart';
import 'package:fanotifier/features/submissions/data/submission_content_block_repository_impl.dart';
import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';
import 'package:fanotifier/features/submissions/data/submission_image_service.dart';
import 'package:fanotifier/features/submissions/data/submission_media_export_service.dart';

class SubmissionsFeature {
  const SubmissionsFeature._();

  static FaContentBlockRepository createContentBlockRepository() {
    return const SubmissionContentBlockRepositoryImpl();
  }

  static SubmissionDetailsRepository createSubmissionDetailsRepository({
    required SubmissionCommentRepository submissionCommentRepository,
    required MediaBytesRepository mediaBytesRepository,
  }) {
    return SubmissionDetailsRepositoryImpl(
      submissionCommentRepository: submissionCommentRepository,
      mediaExportService: SubmissionMediaExportService(
        imageService: SubmissionImageService(
          mediaBytesRepository: mediaBytesRepository,
        ),
      ),
    );
  }

  static SubmissionFavoriteRepository createFavoriteRepository() {
    return SubmissionFavoriteRepositoryImpl();
  }

  static SubmissionsRepository createSubmissionsRepository() {
    return SubmissionsRepositoryImpl();
  }

  static SubmissionManagementRepository createManagementRepository() {
    return const SubmissionManagementRepositoryImpl();
  }

  static SubmissionFolderColorRepository createFolderColorRepository() {
    return const SubmissionFolderColorRepositoryImpl();
  }

  static SubmissionDescriptionRepository createDescriptionRepository() {
    return SubmissionDescriptionRepositoryImpl();
  }

  static FinalizeSubmissionRepository createFinalizeRepository() {
    return FinalizeSubmissionService();
  }

  static EditSubmissionPageRepository createEditPageRepository() {
    return const EditSubmissionPageRepositoryImpl();
  }
}
