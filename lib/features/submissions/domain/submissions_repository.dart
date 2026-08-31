import 'package:fanotifier/features/submissions/domain/submission_fetch_models.dart';
import 'package:fanotifier/features/submissions/domain/submissions_listing_parse_result.dart';

abstract interface class SubmissionsRepository {
  Future<bool> hasAuthCookies();

  Future<SubmissionsListingParseResult> fetchListing({
    required String? nextPageUrl,
    required String? baseSubmissionsUrl,
    required bool sfwEnabled,
  });

  Future<bool> nukeSubmissions({
    required String? baseSubmissionsUrl,
  });

  Future<bool> deleteSubmissions({
    required String? baseSubmissionsUrl,
    required Iterable<String> submissionIds,
  });

  Future<SubmissionData> fetchSubmissionData(
    String postUrl, {
    bool Function()? isCancelled,
  });
}
