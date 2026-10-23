import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/services/feed_fetcher.dart';
import 'package:scry/services/ranobes_session.dart';
import 'package:scry/state/novels_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Answers every request with [status] and [body], recording what was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = '<html>ok</html>']);

  int status;
  String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(utf8.encode(body), status);
  }

  @override
  void close({bool force = false}) {}
}

DioFeedFetcher _fetcher(_Adapter adapter) =>
    DioFeedFetcher(Dio()..httpClientAdapter = adapter);

const _chapterList = 'https://ranobes.net/chapters/1205249/';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RanobesSession.reset();
  });

  test('a 429 from ranobes.net means its human check, and pauses it', () async {
    final adapter = _Adapter(429);
    final fetcher = _fetcher(adapter);
    await expectLater(
      fetcher.fetchText(_chapterList),
      throwsA(
        isA<HumanCheckRequired>().having((e) => e.url, 'url', _chapterList),
      ),
    );
    expect(RanobesSession.blocked, isTrue);

    // Further requests fail straight away instead of hitting the site.
    await expectLater(
      fetcher.fetchText('https://ranobes.net/novels/1-x.html'),
      throwsA(isA<HumanCheckRequired>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(await fetcher.fetchBytes('https://ranobes.net/c.jpg'), isNull);
    expect(adapter.requests, hasLength(1));
  });

  test('other sites keep their own errors and aren\'t paused', () async {
    final fetcher = _fetcher(_Adapter(429));
    await expectLater(
      fetcher.fetchText('https://example.com/feed'),
      throwsA(
        isA<FetchException>()
            .having((e) => e is HumanCheckRequired, 'human check', isFalse)
            .having((e) => e.statusCode, 'status', 429),
      ),
    );
    expect(RanobesSession.blocked, isFalse);
  });

  test('a small captcha page with a 200 is the check too', () async {
    final fetcher = _fetcher(
      _Adapter(200, '<html><div class="captcha">Match the image</div></html>'),
    );
    await expectLater(
      fetcher.fetchText(_chapterList),
      throwsA(isA<HumanCheckRequired>()),
    );
  });

  test(
    'ranobes.net gets the passed browser\'s identity; feeds don\'t',
    () async {
      await RanobesSession.save(userAgent: 'TestBrowser/1', cookies: 'pass=1');
      expect(RanobesSession.blocked, isFalse);
      final adapter = _Adapter(200);
      final fetcher = _fetcher(adapter);
      await fetcher.fetchText(_chapterList);
      await fetcher.fetchText('https://example.com/feed');

      final site = adapter.requests[0].headers;
      expect(site['User-Agent'], 'TestBrowser/1');
      expect(site['Cookie'], 'pass=1');
      final feed = adapter.requests[1].headers;
      expect(feed['User-Agent'], isNot('TestBrowser/1'));
      expect(feed.containsKey('Cookie'), isFalse);

      // Saved for the background check, which starts from scratch.
      RanobesSession.reset();
      await RanobesSession.load();
      expect(RanobesSession.userAgent, 'TestBrowser/1');
      expect(RanobesSession.cookies, 'pass=1');
    },
  );

  test('ranobes.net requests are spaced out', () async {
    final adapter = _Adapter(200);
    final fetcher = _fetcher(adapter);
    final watch = Stopwatch()..start();
    await Future.wait([
      fetcher.fetchText(_chapterList),
      fetcher.fetchText(_chapterList),
    ]);
    expect(watch.elapsed, greaterThanOrEqualTo(DioFeedFetcher.ranobesGap));
  });

  test('checking for chapters stops at the human check', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    for (var i = 1; i <= 3; i++) {
      await db.insertNovel(
        Novel(
          url: 'https://ranobes.net/novels/$i-n.html',
          bookId: i,
          title: 'Novel $i',
          addedDate: DateTime(2026),
        ),
      );
    }
    final fetcher = _CheckFetcher();
    final provider = NovelsProvider(NovelRepository(db, fetcher));
    await provider.load();

    final failed = await provider.checkAll();
    expect(fetcher.calls, 1, reason: 'no requests after the check shows');
    expect(failed, 3);
    expect(provider.humanCheck, isNotNull);

    provider.humanCheckPassed();
    expect(provider.humanCheck, isNull);
  });
}

/// The site shows its check on every request.
class _CheckFetcher extends FakeFetcher {
  int calls = 0;

  @override
  Future<FetchedDocument> fetchText(String url) async {
    calls++;
    throw HumanCheckRequired(url);
  }
}
