import 'package:fanotifier/features/journals/domain/journal_not_found_exception.dart';

String journalLoadFailureMessage(Object error) {
  final lower = error.toString().toLowerCase();
  final isNotFound = error is JournalNotFoundException ||
      lower.contains('not in our database') ||
      lower.contains('does not exist') ||
      lower.contains('deleted') ||
      lower.contains('not found');
  return isNotFound
      ? 'This journal does not exist or has been deleted'
      : 'Failed to load journal';
}
