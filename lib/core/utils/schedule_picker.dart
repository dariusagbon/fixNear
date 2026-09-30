import 'package:flutter/material.dart';

/// The default suggested time: an hour from now, rounded up to the next
/// quarter hour.
DateTime suggestedScheduleTime([DateTime? from]) {
  final soon = (from ?? DateTime.now()).add(const Duration(hours: 1));
  final extra = (15 - soon.minute % 15) % 15;
  return DateTime(
    soon.year,
    soon.month,
    soon.day,
    soon.hour,
    soon.minute,
  ).add(Duration(minutes: extra));
}

/// Asks for a date, then a time. Returns null if either is cancelled. The
/// caller checks that the result is in the future.
Future<DateTime?> pickScheduleDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final start = initial != null && initial.isAfter(now)
      ? initial
      : suggestedScheduleTime(now);
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
