class SubmissionData {
  final String hqUrl;
  final bool isFav;
  final String favUrl;
  final String unfavUrl;

  SubmissionData({
    required this.hqUrl,
    required this.isFav,
    required this.favUrl,
    required this.unfavUrl,
  });
}

class SubmissionQueueItem {
  final int indexInFlatList;
  final String uniqueNumber;
  final String postUrl;

  SubmissionQueueItem({
    required this.indexInFlatList,
    required this.uniqueNumber,
    required this.postUrl,
  });
}
