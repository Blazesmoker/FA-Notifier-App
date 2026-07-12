import 'package:intl/intl.dart';

Map<String, dynamic> buildOptimisticJournalComment({
  required String text,
  required DateTime now,
}) {
  return {
    'profileImage': null,
    'username': 'You',
    'text': text,
    'width': 100.0,
    'isOP': false,
    'popupDateFull': DateFormat('MMM d, yyyy hh:mm a').format(now),
    'commentId': null,
    'deleted': false,
  };
}
