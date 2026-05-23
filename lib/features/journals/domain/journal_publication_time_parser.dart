import 'package:intl/intl.dart';

DateTime? parseJournalPublicationTime(
  String rawTime, {
  required bool applyDstCorrection,
}) {
  final trimmed = rawTime.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower.contains('ago')) {
    return null;
  }
  if (!RegExp(r'\d').hasMatch(trimmed)) {
    return null;
  }

  final formats = [
    DateFormat("MMMM d, yyyy h:mm:ss a"),
    DateFormat("MMMM d, yyyy hh:mm:ss a"),
    DateFormat("MMMM d, yyyy h:mm a"),
    DateFormat("MMMM d, yyyy hh:mm a"),
    DateFormat("MMM d, yyyy h:mm a"),
    DateFormat("MMM d, yyyy hh:mm a"),
    DateFormat("MMM d yyyy h:mm a"),
    DateFormat("yyyy-MM-dd HH:mm:ss"),
  ];

  DateTime? parsed;
  for (final fmt in formats) {
    try {
      parsed = fmt.parse(trimmed, true);
      break;
    } catch (_) {}
  }

  parsed ??= DateTime.tryParse(trimmed);
  if (parsed == null) return null;
  if (applyDstCorrection) {
    parsed = parsed.subtract(const Duration(hours: 1));
  }
  return parsed.toUtc();
}
