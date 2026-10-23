import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/feed_repository.dart';
import 'package:scry/models/article.dart';
import 'package:scry/models/article_sort.dart';
import 'package:scry/models/topic.dart';
import 'package:scry/utils/html_text.dart';
import 'package:scry/utils/readable.dart';

import 'support/fakes.dart';

String _para(int n, String word) =>
    '<p>${List.filled(30, word).join(' ')} number $n.</p>';

/// A blog page: menus, a share bar, the article, comments and a footer.
final _page =
    '''<html><head>
<meta property="og:image" content="/cover.png"><title>Post</title></head>
<body class="has-sidebar">
<nav><a href="/">Home</a> <a href="/about">About</a></nav>
<header><a href="/">My Blog</a></header>
<div class="layout">
  <article>
    <a href="/blog">Back to articles</a>
    <h1>The Post Title</h1>
    <div class="meta"><span>5 upvotes</span></div>
    <div class="entry-content no-share">
      ${_para(1, 'transistor')}
      <h2>Results</h2>
      ${_para(2, 'silicon')}
      <figure><img src="/fig1.png" width="600"><figcaption>A chart</figcaption></figure>
      ${_para(3, 'wafer')}
      <pre><code><span>x</span> = <span>"quoted"</span></code></pre>
      ${_para(4, 'lithography')}
      ${_para(5, 'yield')}
      <p>See <a href="/other">the other post</a> and <a href="#notes">notes</a>.</p>
    </div>
    <div class="share-buttons"><a href="https://x.com/share">Share</a></div>
  </article>
  <div class="comments">${_para(9, 'comment')}${_para(10, 'comment')}</div>
  <aside>${_para(11, 'sidebar')}</aside>
</div>
<footer>Copyright</footer>
</body></html>''';

void main() {
  group('reader mode', () {
    const url = 'https://blog.example.com/posts/1';

    test('keeps the article and drops the page around it', () {
      final html = extractArticle(_page, pageUrl: url)!;
      final text = htmlToPlainText(html);
      for (final word in ['transistor', 'silicon', 'wafer', 'yield']) {
        expect(text, contains(word));
      }
      expect(text, contains('Results'));
      expect(text, contains('"quoted"'), reason: 'code is kept whole');
      for (final junk in [
        'Home',
        'My Blog',
        'Back to articles',
        'The Post Title',
        'upvotes',
        'Share',
        'comment',
        'sidebar',
        'Copyright',
      ]) {
        expect(text, isNot(contains(junk)), reason: junk);
      }
    });

    test('links and images become absolute', () {
      final html = extractArticle(_page, pageUrl: url)!;
      expect(html, contains('src="https://blog.example.com/fig1.png"'));
      expect(html, contains('href="https://blog.example.com/other"'));
      expect(html, isNot(contains('href="#notes"')));
    });

    test('pages without an article give nothing', () {
      const page =
          '<html><body><nav><a href="/">Home</a></nav>'
          '<p>Just a short note.</p></body></html>';
      expect(extractArticle(page, pageUrl: url), isNull);
    });

    test('words are counted in any script', () {
      expect(countWords('Hello, world! Ça va? 3.5 GHz'), 6);
    });
  });

  group('tags', () {
    test('feeds are guessed from arXiv categories', () {
      expect(guessTopics('https://rss.arxiv.org/rss/cs.AR', 'cs.AR'), {
        Topic.ic,
      });
      expect(guessTopics('https://rss.arxiv.org/rss/cs.LG', 'cs.LG'), {
        Topic.ml,
      });
      expect(guessTopics('https://rss.arxiv.org/rss/cs.LG+cs.AR', 'x'), {
        Topic.ml,
        Topic.ic,
      });
      expect(guessTopics('https://rss.arxiv.org/rss/math.CO', 'x'), isEmpty);
    });

    test('feeds are guessed from names', () {
      expect(guessTopics('https://semiengineering.com/feed/', 'Semi'), {
        Topic.ic,
      });
      expect(guessTopics('https://huggingface.co/blog/feed.xml', 'HF'), {
        Topic.ml,
      });
      expect(guessTopics('https://www.anthropic.com/news/rss', 'News'), {
        Topic.claude,
      });
      expect(guessTopics('https://cooking.example/feed', 'Recipes'), isEmpty);
    });

    test('articles earn tags from their title or repeated words', () {
      expect(tagsInText('Does Your Model Run on AWS Trainium?', ''), {
        Topic.ic,
      });
      expect(tagsInText('Cut EDA license cost with Stratos AI', ''), {
        Topic.ml,
        Topic.ic,
      });
      expect(tagsInText('Building agents with Claude', ''), {Topic.claude});
      // One passing mention in the text isn't enough.
      expect(tagsInText('A post', 'We trained it on a GPU.'), isEmpty);
      expect(tagsInText('A post', 'GPU GPU HBM wafer and more GPUs'), {
        Topic.ic,
      });
      // Names aren't chips.
      expect(tagsInText('Notes from Chip Huyen', ''), isEmpty);
    });

    test('tag lists round-trip in a fixed order', () {
      expect(topicsToString({Topic.claude, Topic.ml}), 'ml,claude');
      expect(topicsFromString('claude,ml,nope'), {Topic.ml, Topic.claude});
      expect(topicsToString({}), isNull);
    });
  });

  test('read time needs more than a teaser', () {
    expect(readMinutesFor(40), isNull);
    expect(readMinutesFor(230), 1);
    expect(readMinutesFor(2300), 10);
  });

  test('read-time sorts put unknown lengths last', () async {
    final db = await openTestDatabase();
    String body(int words) =>
        '&lt;p&gt;${List.filled(words, 'word').join(' ')}&lt;/p&gt;';
    const url = 'https://long.example.com/feed.xml';
    final fetcher = FakeFetcher({
      url:
          '<?xml version="1.0"?><rss version="2.0"><channel><title>L</title>'
          '<item><title>Short</title><link>https://l.com/1</link>'
          '<description>${body(300)}</description></item>'
          '<item><title>Teaser</title><link>https://l.com/2</link>'
          '<description>Just a line.</description></item>'
          '<item><title>Long</title><link>https://l.com/3</link>'
          '<description>${body(3000)}</description></item>'
          '</channel></rss>',
    });
    final repo = FeedRepository(db, fetcher);
    await repo.addFeed(url);
    Future<List<String>> titles(ArticleSort sort) async =>
        (await repo.listArticles(sort: sort)).map((a) => a.title).toList();
    expect(await titles(ArticleSort.shortest), ['Short', 'Long', 'Teaser']);
    expect(await titles(ArticleSort.longest), ['Long', 'Short', 'Teaser']);
    await db.close();
  });

  group('repository', () {
    late AppDatabase db;
    late FakeFetcher fetcher;
    late FeedRepository repo;

    const feedUrl = 'https://blog.example.com/feed.xml';
    const feed = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>Semi Blog</title><link>https://blog.example.com/</link>
  <item><title>Teaser</title><link>https://blog.example.com/posts/1</link>
    <description>Only the first line.</description></item>
</channel></rss>''';

    setUp(() async {
      db = await openTestDatabase();
      fetcher = FakeFetcher({feedUrl: feed});
      repo = FeedRepository(db, fetcher);
    });

    tearDown(() => db.close());

    test('new feeds get tags, and their articles carry them', () async {
      final added = await repo.addFeed(feedUrl);
      expect(added.topics, {Topic.ic});
      final article = (await repo.listArticles()).single;
      expect(article.tags, [Topic.ic]);
      expect(await repo.listArticles(topic: Topic.ml), isEmpty);
      expect(await repo.listArticles(topic: Topic.ic), hasLength(1));

      await repo.setFeedTopics(added.id!, {Topic.ml, Topic.ic});
      expect((await repo.listArticles(topic: Topic.ml)).single.tags, [
        Topic.ml,
        Topic.ic,
      ]);
    });

    test('chosen tags beat the guess', () async {
      final added = await repo.addFeed(feedUrl, topics: {Topic.ml});
      expect(added.topics, {Topic.ml});
    });

    test("an article's own words add tags and filter", () async {
      const tagged = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>Semi Blog</title><link>https://blog.example.com/</link>
  <item><title>Running Claude on custom silicon</title>
    <link>https://blog.example.com/posts/2</link></item>
  <item><title>Teaser</title><link>https://blog.example.com/posts/1</link>
    <description>Only the first line.</description></item>
</channel></rss>''';
      fetcher.responses[feedUrl] = tagged;
      await repo.addFeed(feedUrl);
      final claude = await repo.listArticles(topic: Topic.claude);
      expect(claude.single.title, 'Running Claude on custom silicon');
      expect(claude.single.tags, [Topic.ic, Topic.claude]);
    });

    test('mark all read follows the filter and can be undone', () async {
      await repo.addFeed(feedUrl);
      expect(await repo.markAllRead(topic: Topic.ml), isEmpty);
      final ids = await repo.markAllRead(topic: Topic.ic);
      expect(ids, hasLength(1));
      expect(await repo.unreadCount(), 0);
      await repo.markUnread(ids);
      expect(await repo.unreadCount(), 1);
    });

    test("a teaser's full text is fetched from its page and kept", () async {
      fetcher.responses['https://blog.example.com/posts/1'] = _page;
      await repo.addFeed(feedUrl);
      final teaser = (await repo.listArticles()).single;
      expect(FeedRepository.isTeaser(teaser), isTrue);
      expect(teaser.readMinutes, isNull);

      final check = await repo.checkPage(teaser);
      expect(check.imageUrl, 'https://blog.example.com/cover.png');
      expect(check.wordCount, greaterThan(150));

      final full = (await repo.getArticle(teaser.id!))!;
      expect(htmlToPlainText(full.fullContent), contains('lithography'));
      expect(full.readMinutes, isNotNull);
      expect(full.imageChecked, isTrue);
    });
  });
}
