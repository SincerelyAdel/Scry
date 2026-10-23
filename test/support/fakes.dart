import 'dart:typed_data';

import 'package:snippefy/data/app_database.dart';
import 'package:snippefy/services/feed_fetcher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serves canned responses keyed by URL. Unknown URLs fail like a 404.
class FakeFetcher implements FeedFetcher {
  FakeFetcher([Map<String, String>? responses]) : responses = responses ?? {};

  final Map<String, String> responses;

  /// URL -> final URL after a pretend redirect.
  final Map<String, String> redirects = {};

  final List<String> requested = [];

  @override
  Future<FetchedDocument> fetchText(String url) async {
    requested.add(url);
    final target = redirects[url] ?? url;
    final body = responses[target];
    if (body == null) throw FetchException('Server returned 404');
    return FetchedDocument(body: body, url: target);
  }

  @override
  Future<Uint8List?> fetchBytes(String url) async => null;
}

/// A fresh in-memory database per call.
Future<AppDatabase> openTestDatabase() {
  sqfliteFfiInit();
  return AppDatabase.open(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}
