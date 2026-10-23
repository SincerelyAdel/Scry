import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ranobes_session.dart';

/// A downloaded document.
class FetchedDocument {
  const FetchedDocument({required this.body, required this.url});

  final String body;

  /// URL after redirects.
  final String url;
}

/// Network access used by the repository. An interface so tests can serve
/// canned responses.
abstract class FeedFetcher {
  Future<FetchedDocument> fetchText(String url);

  /// Returns null on any failure; used for best-effort extras like favicons.
  Future<Uint8List?> fetchBytes(String url);

  /// Downloads the start of a page, stopping once [done] says the text so
  /// far is enough, or after [maxBytes]. For finding a page's preview image
  /// without downloading all of it.
  Future<FetchedDocument> fetchPrefix(
    String url, {
    int maxBytes = 400 * 1024,
    bool Function(String textSoFar)? done,
  });
}

/// Thrown for network failures, with a message fit to show the user.
class FetchException implements Exception {
  FetchException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status, when the server answered with an error.
  final int? statusCode;

  @override
  String toString() => message;
}

/// ranobes.net is showing its "are you human" check. The person has to pass
/// it in the in-app browser (see HumanCheckScreen) before the site will
/// answer again.
class HumanCheckRequired extends FetchException {
  HumanCheckRequired(this.url)
    : super("ranobes.net wants to check you're human", statusCode: 429);

  /// The page that showed the check; the browser opens it.
  final String url;
}

class DioFeedFetcher implements FeedFetcher {
  DioFeedFetcher([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              // Some hosts reject requests without a browser-ish UA.
              headers: {
                'User-Agent': 'Scry/0.1 (Flutter RSS reader)',
                'Accept':
                    'application/rss+xml, application/atom+xml, '
                    'application/xml;q=0.9, text/xml;q=0.9, text/html;q=0.8, '
                    '*/*;q=0.5',
              },
            ),
          );

  final Dio _dio;

  @override
  Future<FetchedDocument> fetchText(String url) =>
      _guard(url, () => _fetchText(url));

  Future<FetchedDocument> _fetchText(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: _siteHeaders(url),
        ),
      );
      final bytes = response.data ?? const <int>[];
      final body = utf8.decode(bytes, allowMalformed: true);
      if (_isHumanCheck(url, body)) throw HumanCheckRequired(url);
      return FetchedDocument(
        // Feeds are overwhelmingly UTF-8; tolerate the odd bad byte rather
        // than failing the whole refresh.
        body: body,
        url: response.realUri.toString(),
      );
    } on DioException catch (e) {
      throw _failure(url, e);
    }
  }

  @override
  Future<FetchedDocument> fetchPrefix(
    String url, {
    int maxBytes = 400 * 1024,
    bool Function(String textSoFar)? done,
  }) => _guard(url, () => _fetchPrefix(url, maxBytes: maxBytes, done: done));

  Future<FetchedDocument> _fetchPrefix(
    String url, {
    required int maxBytes,
    bool Function(String textSoFar)? done,
  }) async {
    final cancel = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers:
              _siteHeaders(url) ??
              {'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5'},
        ),
      );
      final bytes = <int>[];
      var checked = 0;
      await for (final chunk in response.data!.stream) {
        bytes.addAll(chunk);
        // Check roughly every 16 KB rather than on every small chunk.
        if (bytes.length >= maxBytes ||
            (done != null &&
                bytes.length - checked >= 16 * 1024 &&
                done(utf8.decode(bytes, allowMalformed: true)))) {
          cancel.cancel();
          break;
        }
        if (bytes.length - checked >= 16 * 1024) checked = bytes.length;
      }
      return FetchedDocument(
        body: utf8.decode(bytes, allowMalformed: true),
        url: response.realUri.toString(),
      );
    } on DioException catch (e) {
      throw _failure(url, e);
    }
  }

  @override
  Future<Uint8List?> fetchBytes(String url) async {
    if (RanobesSession.appliesTo(url) && RanobesSession.blocked) return null;
    try {
      return await _paced(url, () => _fetchBytes(url));
    } on DioException catch (e) {
      _failure(url, e); // Notes a human check, if that's what it was.
      return null;
    }
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 10),
        headers: _siteHeaders(url),
      ),
    );
    final data = response.data;
    return data == null || data.isEmpty ? null : Uint8List.fromList(data);
  }

  // ------------------------------------------------------------ ranobes.net

  /// Gap between requests to ranobes.net. The site rate-limits, and a
  /// burst (a library check plus covers plus a prefetched chapter) is
  /// what brings up its human check.
  static const ranobesGap = Duration(milliseconds: 1200);

  static Future<void> _queue = Future.value();
  static DateTime _lastRanobes = DateTime.fromMillisecondsSinceEpoch(0);

  /// Runs [run] directly for most sites. For ranobes.net: fails straight
  /// away while its check is up, and otherwise runs requests one at a
  /// time, [ranobesGap] apart.
  Future<T> _guard<T>(String url, Future<T> Function() run) {
    if (!RanobesSession.appliesTo(url)) return run();
    if (RanobesSession.blocked) {
      return Future.error(HumanCheckRequired(url));
    }
    return _paced(url, run);
  }

  Future<T> _paced<T>(String url, Future<T> Function() run) {
    if (!RanobesSession.appliesTo(url)) return run();
    final previous = _queue;
    final turn = Completer<void>();
    _queue = turn.future;
    return previous.then((_) async {
      try {
        // A check that came up while this request waited its turn.
        if (RanobesSession.blocked) throw HumanCheckRequired(url);
        final wait = ranobesGap - DateTime.now().difference(_lastRanobes);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        return await run();
      } finally {
        _lastRanobes = DateTime.now();
        turn.complete();
      }
    });
  }

  /// Browser headers and the passed check's cookies, for ranobes.net only.
  static Map<String, String>? _siteHeaders(String url) =>
      RanobesSession.appliesTo(url) ? RanobesSession.headers() : null;

  /// The check page can also come back with a 200; it's small and talks
  /// about a captcha, where real pages are large and don't.
  static bool _isHumanCheck(String url, String body) {
    if (!RanobesSession.appliesTo(url) || body.length > 60 * 1024) {
      return false;
    }
    final text = body.toLowerCase();
    final isCheck = text.contains('captcha') || text.contains('are you human');
    if (isCheck) RanobesSession.markBlocked();
    return isCheck;
  }

  /// The exception to throw for [e]. ranobes.net answers its human check
  /// with 429 (sometimes 403 or 503); that pauses requests to the site.
  static FetchException _failure(String url, DioException e) {
    final status = e.response?.statusCode;
    if (RanobesSession.appliesTo(url) &&
        (status == 429 || status == 403 || status == 503)) {
      RanobesSession.markBlocked();
      return HumanCheckRequired(url);
    }
    return FetchException(_describe(e), statusCode: status);
  }

  static String _describe(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.transformTimeout => 'Timed out',
      DioExceptionType.badResponse =>
        'Server returned ${e.response?.statusCode ?? 'an error'}',
      DioExceptionType.connectionError => 'Could not connect',
      DioExceptionType.badCertificate => 'Bad TLS certificate',
      DioExceptionType.cancel => 'Cancelled',
      DioExceptionType.unknown => e.message ?? 'Network error',
    };
  }
}
