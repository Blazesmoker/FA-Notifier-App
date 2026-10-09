import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';

class SubmissionData {
  final String hqUrl;
  final bool isFav;
  final String favUrl;
  final String unfavUrl;
  final FaContentBlockData contentBlock;

  SubmissionData({
    required this.hqUrl,
    required this.isFav,
    required this.favUrl,
    required this.unfavUrl,
    this.contentBlock = const FaContentBlockData(),
  });
}

class SubmissionQueueItem {
  final int indexInFlatList;
  final String submissionId;
  final String postUrl;

  SubmissionQueueItem({
    required this.indexInFlatList,
    required this.submissionId,
    required this.postUrl,
  });
}
