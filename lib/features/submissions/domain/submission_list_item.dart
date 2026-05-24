class SubmissionListItem {
  final bool isHeader;
  final String? dateLabel;
  final List<Map<String, dynamic>>? rowImages;
  final bool showDividerAfterGroup;

  SubmissionListItem.header(this.dateLabel, {required this.showDividerAfterGroup})
      : isHeader = true,
        rowImages = null;

  SubmissionListItem.row(this.rowImages, {required this.showDividerAfterGroup})
      : isHeader = false,
        dateLabel = null;
}
