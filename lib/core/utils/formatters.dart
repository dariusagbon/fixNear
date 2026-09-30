import '../models/marketplace_models.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a date and time as, for example, `Mar 4, 2026 · 2:05 PM`.
String formatDateTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour < 12 ? 'AM' : 'PM';
  return '${_months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} '
      '· $hour:$minute $period';
}

/// Formats a whole-peso amount with thousands separators, e.g. `₱1,200`.
String formatPeso(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}₱$buffer';
}

String requestStatusLabel(String status) => switch (status) {
  RequestStatus.requested => 'Requested',
  RequestStatus.quoted => 'Quotes received',
  RequestStatus.accepted => 'Accepted',
  RequestStatus.onTheWay => 'On the way',
  RequestStatus.arrived => 'Arrived',
  RequestStatus.inProgress => 'In progress',
  RequestStatus.providerCompleted => 'Awaiting confirmation',
  RequestStatus.completed => 'Completed',
  RequestStatus.cancelled => 'Cancelled',
  '' => 'Unknown',
  _ => status[0].toUpperCase() + status.substring(1).replaceAll('_', ' '),
};

String initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

/// Turns an exception into a message that is safe to show to users.
String friendlyErrorMessage(Object error, String fallback) {
  if (error is StateError) return error.message;
  if (error is ArgumentError && error.message is String) {
    return error.message as String;
  }
  return fallback;
}
