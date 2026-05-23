import 'package:FANotifier/features/submissions/domain/submission_image_group.dart';

class SubmissionsListingParseResult {
  final bool isClassicStyle;
  final String? baseSubmissionsUrl;
  final List<DateImageGroup> dateGroups;
  final String? nextPageUrl;

  const SubmissionsListingParseResult({
    required this.isClassicStyle,
    required this.baseSubmissionsUrl,
    required this.dateGroups,
    required this.nextPageUrl,
  });
}
