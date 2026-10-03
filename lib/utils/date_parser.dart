/// Parses the date formats feeds use in practice: RFC 822 for RSS
/// (`Tue, 10 Jun 2025 04:00:00 GMT`) and ISO 8601 for Atom and Dublin Core
/// (`2025-06-10T04:00:00Z`). Returns null for anything unparseable rather
/// than failing the whole feed.
DateTime? parseFeedDate(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc() ?? _parseRfc822(text);
}

final _rfc822 = RegExp(
  r'^(?:[A-Za-z]+,?\s*)?(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{2,4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*(.*)$',
);

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Offsets in hours for the named zones RFC 822 allows.
const _zones = {
  'gmt': 0,
  'ut': 0,
  'utc': 0,
  'z': 0,
  'est': -5,
  'edt': -4,
  'cst': -6,
  'cdt': -5,
  'mst': -7,
  'mdt': -6,
  'pst': -8,
  'pdt': -7,
};

final _numericZone = RegExp(r'^([+-])(\d{2}):?(\d{2})$');

DateTime? _parseRfc822(String text) {
  final m = _rfc822.firstMatch(text);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;

  final day = int.parse(m.group(1)!);
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  final hour = int.parse(m.group(4) ?? '0');
  final minute = int.parse(m.group(5) ?? '0');
  final second = int.parse(m.group(6) ?? '0');

  final utc = DateTime.utc(year, month, day, hour, minute, second);
  return utc.subtract(_zoneOffset(m.group(7)!.trim()));
}

Duration _zoneOffset(String zone) {
  if (zone.isEmpty) return Duration.zero;
  final named = _zones[zone.toLowerCase()];
  if (named != null) return Duration(hours: named);
  final m = _numericZone.firstMatch(zone);
  if (m == null) return Duration.zero;
  final sign = m.group(1) == '-' ? -1 : 1;
  return Duration(
    hours: sign * int.parse(m.group(2)!),
    minutes: sign * int.parse(m.group(3)!),
  );
}
