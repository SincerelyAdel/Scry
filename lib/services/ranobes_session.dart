import 'package:shared_preferences/shared_preferences.dart';

/// ranobes.net shows an image-matching "are you human" check to clients it
/// doesn't trust, and answers 429 until it's passed. The person passes it
/// once in an in-app browser; this keeps that browser's identity (its
/// user agent and the site's cookies) so the app's own requests are
/// recognised as the same, already checked visitor.
///
/// Saved in shared preferences, so the background chapter check (another
/// isolate) uses it too.
abstract final class RanobesSession {
  static const _kUserAgent = 'ranobes.userAgent';
  static const _kCookies = 'ranobes.cookies';

  /// Used until a check has been passed: an ordinary mobile Chrome, since
  /// the site is stricter with clients that don't look like a browser.
  static const fallbackUserAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// How long to stop asking the site after it shows its check, unless
  /// the check is passed sooner. Asking again meanwhile only gets more
  /// 429s and can make the block last longer.
  static const cooldown = Duration(minutes: 10);

  static String? _userAgent;
  static String? _cookies;
  static DateTime? _blockedAt;

  static String get userAgent => _userAgent ?? fallbackUserAgent;
  static String? get cookies => _cookies;

  /// True for any ranobes.net address, covers included.
  static bool appliesTo(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'ranobes.net' || host.endsWith('.ranobes.net');
  }

  /// Headers that make a request look like the browser that passed the
  /// check.
  static Map<String, String> headers() => {
    'User-Agent': userAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    if (_cookies != null && _cookies!.isNotEmpty) 'Cookie': _cookies!,
  };

  /// True while the site's check is up and hasn't been passed.
  static bool get blocked {
    final at = _blockedAt;
    return at != null && DateTime.now().difference(at) < cooldown;
  }

  static void markBlocked() => _blockedAt = DateTime.now();

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _userAgent = prefs.getString(_kUserAgent);
    _cookies = prefs.getString(_kCookies);
  }

  /// Stores the browser identity after the check is passed, and lifts the
  /// pause.
  static Future<void> save({
    required String userAgent,
    required String cookies,
  }) async {
    _userAgent = userAgent;
    _cookies = cookies;
    _blockedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserAgent, userAgent);
    await prefs.setString(_kCookies, cookies);
  }

  /// For tests.
  static void reset() {
    _userAgent = null;
    _cookies = null;
    _blockedAt = null;
  }
}
