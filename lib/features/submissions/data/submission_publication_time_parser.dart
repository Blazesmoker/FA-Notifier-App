import 'package:intl/intl.dart';

DateTime? parseSubmissionPublicationTime(
  String rawTime, {
  required bool applyDstCorrection,
}) {
  final trimmed = rawTime.trim();
  final formats = [
    DateFormat('MMMM d, yyyy hh:mm:ss a'),
    DateFormat('MMM d, yyyy hh:mm:ss a'),
    DateFormat('MMM d, yyyy HH:mm:ss'),
    DateFormat('MMM d, yyyy hh:mm a'),
    DateFormat('MMM d, yyyy HH:mm'),
    DateFormat('yyyy-MM-dd HH:mm:ss'),
  ];

  for (final format in formats) {
    try {
      var parsed = format.parse(trimmed);
      if (applyDstCorrection) {
        parsed = parsed.subtract(const Duration(hours: 1));
      }
      return parsed.toUtc();
    } catch (_) {}
  }

  return null;
}
