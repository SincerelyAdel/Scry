const rss2Feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Example &amp; Co Blog</title>
    <link>https://example.com/</link>
    <description>Posts</description>
    <item>
      <title>Second post</title>
      <link>/posts/2</link>
      <guid isPermaLink="false">post-2</guid>
      <pubDate>Tue, 10 Jun 2025 16:00:00 +0200</pubDate>
      <dc:creator>Ada</dc:creator>
      <description>&lt;p&gt;Short summary&lt;/p&gt;</description>
      <content:encoded><![CDATA[<p>Full <b>body</b> here.</p><ul><li>one</li><li>two</li></ul>]]></content:encoded>
    </item>
    <item>
      <title>First post</title>
      <link>https://example.com/posts/1</link>
      <pubDate>Mon, 09 Jun 2025 08:00:00 GMT</pubDate>
      <description>Plain summary</description>
    </item>
  </channel>
</rss>''';

const atomFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Example</title>
  <link href="https://atom.example.org/" rel="alternate" type="text/html"/>
  <link href="https://atom.example.org/feed.xml" rel="self"/>
  <author><name>Feed Author</name></author>
  <updated>2025-06-11T12:00:00Z</updated>
  <entry>
    <title type="html">Entry &amp;amp; more</title>
    <id>tag:atom.example.org,2025:1</id>
    <link href="https://atom.example.org/1" rel="alternate"/>
    <published>2025-06-11T12:00:00Z</published>
    <summary>Entry summary</summary>
    <content type="html">&lt;p&gt;Entry content&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>Updated only</title>
    <id>tag:atom.example.org,2025:2</id>
    <link href="https://atom.example.org/2"/>
    <author><name>Entry Author</name></author>
    <updated>2025-06-10T09:30:00+01:00</updated>
  </entry>
</feed>''';

const rdfFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns="http://purl.org/rss/1.0/"
         xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel rdf:about="https://rdf.example.net/">
    <title>RDF Example</title>
    <link>https://rdf.example.net/</link>
    <description>RSS 1.0</description>
  </channel>
  <item rdf:about="https://rdf.example.net/a">
    <title>RDF item</title>
    <link>https://rdf.example.net/a</link>
    <description>RDF summary</description>
    <dc:creator>Grace</dc:creator>
    <dc:date>2025-06-08T10:00:00Z</dc:date>
  </item>
</rdf:RDF>''';

const htmlPageWithFeedLink = '''<!doctype html>
<html><head>
  <title>Example</title>
  <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml">
  <link rel="stylesheet" href="/style.css">
</head><body><p>Hello</p></body></html>''';

const htmlPageWithoutFeed =
    '<!doctype html><html><head><title>x</title></head><body></body></html>';

/// Builds an RSS document with [count] items, newest first.
String rssWithItems(String title, int count, {int startId = 0}) {
  final items = StringBuffer();
  for (var i = count - 1; i >= 0; i--) {
    final id = startId + i;
    final day = (id % 28) + 1;
    items.write('''
    <item>
      <title>$title item $id</title>
      <link>https://example.com/$title/$id</link>
      <guid>$title-$id</guid>
      <pubDate>${day.toString().padLeft(2, '0')} Jan 2025 10:00:00 GMT</pubDate>
    </item>''');
  }
  return '''<?xml version="1.0"?>
<rss version="2.0"><channel><title>$title</title>
<link>https://example.com/$title</link>$items
</channel></rss>''';
}
