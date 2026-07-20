import 'package:fanotifier/features/submissions/data/edit_submission_page_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/finalize_submission_service.dart';
import 'package:fanotifier/features/submissions/data/openpost_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_description_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submission_favorite_repository_impl.dart';
import 'package:fanotifier/features/submissions/data/submissions_repository_impl.dart';
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_repository.dart';
import 'package:fanotifier/features/submissions/domain/openpost_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submissions_repository.dart';
import 'package:fanotifier/shared/fa/domain/submission_comment_repository.dart';

class SubmissionsFeature {
  const SubmissionsFeature._();

  static OpenPostRepository createOpenPostRepository({
    required SubmissionCommentRepository submissionCommentRepository,
  }) {
    return OpenPostRepositoryImpl(
      submissionCommentRepository: submissionCommentRepository,
    );
  }

  static SubmissionFavoriteRepository createFavoriteRepository() {
    return SubmissionFavoriteRepositoryImpl();
  }

  static SubmissionsRepository createSubmissionsRepository() {
    return SubmissionsRepositoryImpl();
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
