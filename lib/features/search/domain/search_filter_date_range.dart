import 'package:intl/intl.dart';

DateTime? parseSearchFilterDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateFormat('yyyy-MM-dd').parse(value);
}

String formatSearchFilterDate(DateTime? date) {
  return date != null ? DateFormat('yyyy-MM-dd').format(date) : '';
}

String formatSearchFilterDateLabel(DateTime? date) {
  return date != null ? DateFormat('dd.MM.yyyy').format(date) : 'Not set';
}

String formatSearchFilterDatePickerLabel(DateTime? date) {
  return date != null ? DateFormat('dd.MM.yyyy').format(date) : 'Select Date';
}
