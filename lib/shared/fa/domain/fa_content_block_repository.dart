import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';

abstract interface class FaContentBlockRepository {
  Future<FaContentBlockData?> fetchSubmissionTags({
    required String submissionId,
    required bool Function() isCancelled,
  });
}
