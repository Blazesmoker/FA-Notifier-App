import 'package:FANotifier/features/submissions/domain/finalize_submission_options.dart';
import 'package:FANotifier/features/submissions/domain/finalize_submission_request.dart';

typedef FinalizeSubmissionRepositoryFactory =
    FinalizeSubmissionRepository Function();

abstract interface class FinalizeSubmissionRepository {
  Future<FinalizeSubmissionOptions> fetchOptions();

  Future<void> finalizeSubmission(FinalizeSubmissionRequest request);
}
