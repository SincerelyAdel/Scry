import 'package:intl/intl.dart';

/// "just now", "5m ago", "3h ago", "2d ago", then a plain date.
String relativeDate(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final diff = (now ?? DateTime.now()).difference(local);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMMMd().format(local);
}

/// "Jun 10, 2025, 4:00 PM" in the device's time zone.
String fullDate(DateTime date) =>
    DateFormat.yMMMd().add_jm().format(date.toLocal());
