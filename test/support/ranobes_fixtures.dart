// Small copies of ranobes.net pages, keeping the markup the parser reads.

const novelUrl = 'https://ranobes.net/novels/1205249-shadow-slave-v741610.html';
const chapterListUrl = 'https://ranobes.net/chapters/1205249/';
const chapter2Url =
    'https://ranobes.net/shadow-slave-v741610-1205249/2001.html';
const chapter3Url =
    'https://ranobes.net/shadow-slave-v741610-1205249/3001.html';
const chapter1Url =
    'https://ranobes.net/shadow-slave-v741610-1205249/1001.html';

const searchPage = '''<!DOCTYPE html><html><body>
<div class="search_result_num grey"><div class="block story searchpage">Found 1 responses</div></div>
<article class="block story shortstory mod-poster">
  <div class="short-cont">
    <h2 class="title"><a href="https://ranobes.net/novels/1205249-shadow-slave-v741610.html">Shadow Slave</a></h2>
    <div class="cont showcont"><div class="cont-in">
      <a href="https://ranobes.net/novels/1205249-shadow-slave-v741610.html" class="poster"><figure class="cover" style="background-image: url(https://ranobes.net/uploads/posts/2022-06/thumbs/shadow-slave.jpg);"></figure></a>
      <div style="color: #bdbdbd">
        Growing up in poverty, Sunny never expected anything good from life.
      </div>
    </div></div>
    <div class="r-rate"><div class="rate-drop ellipses"><div class="grey ellipses small">
      Action, Fantasy
    </div></div></div>
  </div>
</article>
<aside><a href="https://ranobes.net/novels/1207224-my-strange-life.html">Not a result</a></aside>
</body></html>''';

const novelPage = '''<!DOCTYPE html><html><head>
<meta property="og:title" content="Shadow Slave">
<meta property="og:url" content="https://ranobes.net/novels/1205249-shadow-slave-v741610.html">
<meta property="og:description" content="Growing up in poverty...">
<meta property="og:image" content="https://ranobes.net/uploads/posts/2022-06/shadow-slave.jpg">
</head><body>
<h1 class="title">Shadow Slave</h1>
<div class="moreless cont-text showcont-h">
  Growing up in poverty, Sunny never expected anything good from life.<br/><br/>Transported into a ruined magical world.
</div>
<div class="r-fullstory-spec"><ul>
  <li title="Original status">Status in COO: <span class="grey"><a href="#">Ongoing</a></span></li>
  <li>Available: <span class="grey">3 chapters</li>
  <li>Authors: <span class="tag_list"><a href="#">Guiltythree</a></span></li>
</ul></div>
</body></html>''';

/// The chapter list's single page, newest first, with [count] chapters.
String chapterListPage({int count = 3}) {
  final rows = [
    if (count >= 4) '{"id":"4001","title":"Chapter 4: Later","date":"2026-10-23 10:00:00","link":"https://ranobes.net/shadow-slave-v741610-1205249/4001.html"}',
    '{"id":"3001","title":"Chapter 3: Dead Ends","date":"2026-10-22 10:00:00","link":"$chapter3Url"}',
    '{"id":"2001","title":"Chapter 2: Liberation","date":"2026-10-21 10:00:00","link":"$chapter2Url"}',
    '{"id":"1001","title":"Chapter 1: Nightmare","date":"2026-10-20 10:00:00","link":"$chapter1Url"}',
  ];
  return '''<!DOCTYPE html><html><body>
<script>window.__DATA__ = {"book_title":"Shadow Slave","book_link":"$novelUrl","book_id":1205249,"chapters":[${rows.join(',')}],"pages_count":1,"count_all":$count,"cstart":1,"limit":25,"search":""}</script>
</body></html>''';
}

/// A chapter page. Ads sit inside the text the way the site puts them.
String chapterPage({
  required String title,
  required List<String> paragraphs,
  String? prev,
  String? next,
}) {
  final nav =
      '''
<div class="center">
  ${prev == null ? '' : '<a href="$prev" class="btn" id="prev">Back</a>'}
  <a href="/chapters/1205249/" class="btn" id="btn-toc">Chapters list</a>
  ${next == null ? '' : '<a href="$next" class="btn" id="next">Next</a>'}
</div>''';
  final first = paragraphs.first;
  // The site breaks paragraphs for ads between words.
  final half = first.contains(' ')
      ? first.lastIndexOf(' ', first.length ~/ 2)
      : first.length;
  return '''<!DOCTYPE html><html><body><article>
$nav
<div class="block story shortstory">
  <h1 class="h4 title" itemprop="headline">
    $title<span hidden> | </span><div class="category grey ellipses"><a href="$novelUrl" rel="up">Shadow Slave</a></div>
  </h1>
  <div class="text" id="arrticle">
    <p>${first.substring(0, half)}
<div class="free-support-top"><div id="bg-ssp-pre-10448"></div>
<div id="bg-ssp-10448">
<script data-cfasync="false">var adx_id_10448 = document.getElementById('bg-ssp-10448');</script>
</div></div>${first.substring(half)}</p>${paragraphs.skip(1).map((p) => '<p>$p</p>').join()}
<div id="bg-ssp-pre-10534"></div>
<div id="bg-ssp-10534">
<script>window.pubadxtag = window.pubadxtag || [];</script>
</div> </div><p>The end of the chapter.</p>
  </div>
  <div class="category grey ellipses"><a href="$novelUrl">Shadow Slave</a></div>
</div>
$nav
</article></body></html>''';
}
