import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

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
  Future<FetchedDocument> fetchText(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data ?? const <int>[];
      return FetchedDocument(
        // Feeds are overwhelmingly UTF-8; tolerate the odd bad byte rather
        // than failing the whole refresh.
        body: utf8.decode(bytes, allowMalformed: true),
        url: response.realUri.toString(),
      );
    } on DioException catch (e) {
      throw FetchException(_describe(e), statusCode: e.response?.statusCode);
    }
  }

  @override
  Future<FetchedDocument> fetchPrefix(
    String url, {
    int maxBytes = 400 * 1024,
    bool Function(String textSoFar)? done,
  }) async {
    final cancel = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
          },
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
      throw FetchException(_describe(e), statusCode: e.response?.statusCode);
    }
  }

  @override
  Future<Uint8List?> fetchBytes(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = response.data;
      return data == null || data.isEmpty ? null : Uint8List.fromList(data);
    } on DioException {
      return null;
    }
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
