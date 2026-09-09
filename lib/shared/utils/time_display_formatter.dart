import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:intl/intl.dart';

final RegExp _timeInTextPattern = RegExp(
  r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AP]M))?(?!\d)',
  caseSensitive: false,
);

String formatTimeInText(
  String value, {
  required TimeDisplayFormat format,
}) {
  return value.replaceAllMapped(_timeInTextPattern, (match) {
    final parsedHour = int.tryParse(match.group(1) ?? '');
    final minute = match.group(2);
    final second = match.group(3);
    final period = match.group(4)?.toUpperCase();
    final parsedMinute = int.tryParse(minute ?? '');
    final parsedSecond = second == null ? null : int.tryParse(second);
    if (parsedHour == null ||
        minute == null ||
        parsedMinute == null ||
        parsedHour > 23 ||
        parsedMinute > 59 ||
        (second != null && (parsedSecond == null || parsedSecond > 59))) {
      return match.group(0) ?? '';
    }

    var hour = parsedHour;
    if (period != null) {
      if (hour < 1 || hour > 12) return match.group(0) ?? '';
      if (period == 'AM') {
        hour = hour == 12 ? 0 : hour;
      } else {
        hour = hour == 12 ? 12 : hour + 12;
      }
    }

    final secondsText = format.showSeconds && second != null ? ':$second' : '';
    if (format.use24HourTime) {
      return '${hour.toString().padLeft(2, '0')}:$minute$secondsText';
    }

    if (period != null) {
      return '$parsedHour:$minute$secondsText $period';
    }

    final displayPeriod = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute$secondsText $displayPeriod';
  });
}

String formatLocalDateTime(
  DateTime value, {
  required TimeDisplayFormat format,
}) {
  final localValue = value.toLocal();
  final date = DateFormat.yMMMd().format(localValue);
  final timePattern = switch ((format.use24HourTime, format.showSeconds)) {
    (true, true) => 'HH:mm:ss',
    (true, false) => 'HH:mm',
    (false, true) => 'h:mm:ss a',
    (false, false) => 'h:mm a',
  };
  final time = DateFormat(timePattern).format(localValue);
  return '$date $time';
}

String formatCurrentPhoneTime(
  DateTime value, {
  required TimeDisplayFormat format,
}) {
  final timePattern = switch ((format.use24HourTime, format.showSeconds)) {
    (true, true) => 'HH:mm:ss',
    (true, false) => 'HH:mm',
    (false, true) => 'h:mm:ss a',
    (false, false) => 'h:mm a',
  };
  return DateFormat(timePattern).format(value.toLocal());
}
