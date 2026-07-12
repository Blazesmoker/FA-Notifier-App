import 'package:FANotifier/features/submissions/data/submissions_service.dart';
import 'package:FANotifier/features/submissions/domain/submission_fetch_models.dart';
import 'package:FANotifier/features/submissions/domain/submissions_listing_parse_result.dart';
import 'package:FANotifier/features/submissions/domain/submissions_repository.dart';

class SubmissionsRepositoryImpl implements SubmissionsRepository {
  SubmissionsRepositoryImpl({SubmissionsService? service})
      : _service = service ?? SubmissionsService();

  final SubmissionsService _service;

  @override
  Future<bool> hasAuthCookies() {
    return _service.hasAuthCookies();
  }

  @override
  Future<SubmissionsListingParseResult> fetchListing({
    required String? nextPageUrl,
    required String? baseSubmissionsUrl,
    required bool sfwEnabled,
  }) {
    return _service.fetchListing(
      nextPageUrl: nextPageUrl,
      baseSubmissionsUrl: baseSubmissionsUrl,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<bool> nukeSubmissions({
    required String? baseSubmissionsUrl,
  }) {
    return _service.nukeSubmissions(baseSubmissionsUrl: baseSubmissionsUrl);
  }

  @override
  Future<bool> deleteSubmissions({
    required String? baseSubmissionsUrl,
    required Iterable<String> submissionIds,
  }) {
    return _service.deleteSubmissions(
      baseSubmissionsUrl: baseSubmissionsUrl,
      submissionIds: submissionIds,
    );
  }

  @override
  Future<SubmissionData> fetchSubmissionData(String postUrl) {
    return _service.fetchSubmissionData(postUrl);
  }
}
