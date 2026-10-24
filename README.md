# Scry

A calm, offline-first RSS/Atom reader for Android and iOS, built with Flutter.
It shares its look with its sibling app, RepoViewer: near-black and gold (or
warm cream in light mode), serif headings, rounded cards and a soft gold glow
around the screen edge.
Subscribe to tech blogs and paper feeds, read everything in one inbox, and
keep reading without a connection. A second side, **Novels**, reads web
novels from ranobes.net and remembers your place.

The name comes from scrying: looking into a crystal ball to see what's coming.
The icon is that ball, painted in gold and purple brush strokes.

> This repo used to be `snippefy`, a small PyQt tool for making VS Code
> snippets. It was rewritten from scratch as this RSS reader and renamed to
> Scry. Old `github.com/SincerelyAdel/snippefy` links redirect here.

## Features

- **Feeds**: add by feed URL *or* by a site's homepage (the app finds the
  advertised feed); RSS 2.0, RSS 1.0 (RDF) and Atom. The feed list shows the
  favicon, topic, article and unread counts, the last update time, and any
  refresh error.
- **Tags**: **ML** (purple), **IC** (chips and IC design, teal), **UVM**
  (UVM and verification, blue; suggested feeds: AMIQ Consulting, VLSI
  Verify), **Bio** (biology and medicine, pink; suggested feeds: Quanta
  biology, The Transmitter, MIT Technology Review biotech, New Scientist
  health, Science News life, Asimov Press) and **Claude** (clay). A feed can have several, guessed when it's added (from
  arXiv categories and names) and changed from its menu (**Tags**). Each
  article carries its feed's tags plus any its own words earn: a match in
  the title, or several in the text (`tagsInText` in `lib/models/topic.dart`;
  a new tag is one more value there). Chips at the top of the inbox show one
  tag at a time.
- **Coloured cards**: inbox cards are coloured by their tags instead of
  carrying badges. The outline runs through the tag colours and a wash of
  them is brushed in from the left with a bright stroke passing over, one
  card after another, replayed when the filter or sort changes. **Paper**
  and the read time sit in the card's grey line; the reader shows badges.
  **Link only** marks an article with nothing to read in the app: the feed
  sent only its link and its page gave no article text.
- **Unified inbox**: every feed's articles merged into one list, newest first,
  with unread dots. Under the title: the tag chips, an **All / Unread /
  Starred** switch, and the sort (newest, by feed, unread first, or by read
  time: quick or long reads first, with papers and unfetched teasers last).
  On tablets the feed list sits beside the articles: tap a feed to see only
  its articles, and combine it with the tag chips. Under a tag, the list
  shows every feed with articles that have it, counting only those.
- **Stars**: tap the star on a card or in the reader to keep an article for
  later; **Starred** lists them. Reading an article doesn't unstar it.
- **Gestures**: in the inbox, swipe right to toggle read, swipe left to
  delete (with undo). Deleted articles don't come back on the next refresh.
  Pinch out (zoom out) with two fingers anywhere on a page to close it: the
  page shrinks with your fingers and closes once it's small enough. In an
  article, swipe left for the next one in the inbox and right for the one
  before; in a novel chapter, left is the next chapter and right the
  previous one.
- **Sample images**: every inbox card shows a picture when the article has
  one: from the feed (Media RSS, image enclosures or the first image in the
  post), else the article page's preview image (`og:image`), else for arXiv
  papers the first figure. Lookups run in the background as cards scroll
  into view, read only the start of each page, and are stored, so each
  article is checked once.
- **Full text**: many feeds send only a teaser or a link. For those, Scry
  downloads the article's page and keeps just the article (reader mode:
  menus, share buttons, comments and sidebars are dropped), in the
  background as cards scroll into view, or when the article is opened.
- **Reader**: title, author, date, feed, badges, and the body (the fetched
  full text, else the feed's content, else its summary), shown with its
  formatting:
  headings, links, lists, quotes, code, tables and images. Tap an image to
  zoom. Text is selectable. Buttons to open in the browser, share, and mark
  read or unread. Opening an article marks it read.
- **arXiv papers**: the id and announcement type are shown as tags with a
  PDF button, the abstract on its own, and a **Figures** section with every
  figure and caption from the paper's HTML version on arXiv. Papers without
  an HTML version point to the PDF.
- **Offline**: feeds, articles, read state, fetched full text and figures
  live in
  SQLite, and images are cached on disk, so anything opened once is
  readable without a connection.
- **Customization**: dark (default), light or system theme, switchable from
  the header; article text size; default sort. All saved with
  `shared_preferences`.
- **Background refresh** (Android): Workmanager refreshes feeds every 2 or 4
  hours (or never), only on a network and when the battery isn't low. Feeds
  also refresh when the app opens and when you pull down in the inbox.

## Novels

The **Feeds | Novels** switch in the top bar flips the whole app between
the two sides; the choice is remembered.

- **Library**: your novels, most recently read first, each with its cover,
  the chapter you're on and how many are left. Novels with chapters
  released since you last read come first, with a gold glow and
  "N new chapters". Opening the library (at most every
  half hour) or pulling down checks for new chapters.
- **New chapter alerts** (Android): about once an hour, in the background,
  the novels you've started are checked and a notification says how many
  chapters came out since you last read. Each chapter is announced once;
  tapping the notification opens the novel where you left it. Turn it off
  in Settings → Novels.
- **Adding**: search ranobes.net by name, or paste a link to a novel, one of
  its chapters or its chapter list.
- **Novel page**: details and every chapter, oldest first, loaded from the
  site 25 at a time as they scroll into view. **Show in list** jumps to the
  chapter you're on; the 123 button goes to any chapter number. Chapters
  seen once stay listed offline. Pinching out of a chapter always lands
  here.
- **Whole novels offline**: download the novel with
  [QuickNovel](https://github.com/LagradOst/QuickNovel), then on the
  novel's page choose ⋮ → **Add chapters from EPUB**. The book's chapters
  are matched to ranobes.net's by the number in each title (parts of one
  chapter are joined; gaps, unnumbered extras and numbering that restarts
  each volume are listed after adding). Those chapters are read from the
  phone, even from a ranobes.net link, so the site is only asked for the
  list's newest page (new chapters) and for chapters the book doesn't
  have. Reading past the book's last chapter carries on from the site.
  **Import EPUB** in the library adds a book on its own instead, with no
  site at all.
- **Reader**: the chapter's text only (the ads the site puts inside it are
  removed), with its own text size, line spacing and serif or sans font
  (the Aa button). It keeps the screen on, remembers how far down the
  chapter you are, saves the next chapter ahead of time, and keeps the last
  60 chapters of each novel for offline reading. **Next chapter** at the end;
  at the latest chapter, **Check again** looks for a new one.
- **Cats** (the cat button in the reader, off by default): realistic cats
  seen from above wander about the margins either side of the text (a
  strip along each edge on a phone), over the page but never in the way of
  touches, at a walk, trot or run, with paws that plant and step. They sit, wash and look around; tap
  one and it puffs up and bolts off the page (its neighbours too), then
  creeps back. The cat button opens every option: cats on or off, Rest
  (they sit or lie down) and Shoo away (to the edges, where only their
  heads peek in).

Parsing lives in `lib/services/ranobes.dart` (search results, the novel
page, the chapter list's embedded JSON, chapter text); the site's markup is
what it reads, so a redesign there would need changes here.

## Getting started

```sh
flutter pub get
flutter run
```

Tap **Add feed** and pick a suggestion, or paste any feed or blog URL. The
suggestions are grouped by topic and chosen for long reads:

- **ML**: Ahead of AI (Sebastian Raschka), Interconnects, Import AI, Berkeley
  AI Research, Google Research, Google DeepMind, Eugene Yan, Lil'Log, Chip
  Huyen, Jay Alammar, MIT News (machine learning), the Hugging Face blog, and
  arXiv cs.LG, cs.CL, cs.AI and stat.ML.
- **IC**: SemiAnalysis, Semiconductor Engineering, Chips and Cheese, The Chip
  Letter, Fabricated Knowledge, IEEE Spectrum (semiconductors), SemiWiki,
  Electronics Weekly, and arXiv cs.AR (hardware architecture).

Papers with Code shut down in 2025 and Anthropic doesn't publish an RSS feed,
so neither is listed.

### Getting the APK

This repo doesn't build APKs itself. They come from
[SincerelyAdel/apk-builder](https://github.com/SincerelyAdel/apk-builder):
in RepoViewer, open **APKs → Build APK**, pick `SincerelyAdel/Scry`, and leave
the branch blank to build `main`. Choose **GitHub** as the runner: Scry needs a
recent Flutter stable, which the GitHub runner installs. The APK is published
as a release on apk-builder and signed with the same key as every other build,
so new versions install as updates. The Android package is
`com.sincerelyadel.scry`.

### Tests

```sh
flutter analyze
flutter test
```

The tests use an in-memory SQLite database through `sqflite_common_ffi`, so
they need the system SQLite library (`libsqlite3-dev` on Debian/Ubuntu;
macOS already has it). CI runs format, analyze and tests on every push.

## Architecture

```
lib/
  main.dart                 opens prefs + DB, schedules background sync
  app.dart                  Provider wiring, Material 3 themes
  models/                   Feed, Article, ArticleSort, Topic (tags), Novel
  data/
    app_database.dart       sqflite schema and every SQL query
    feed_repository.dart    fetch → parse → store; used by the UI and the worker
    novel_repository.dart   novels: search, add, chapters (saved), progress
  services/
    feed_fetcher.dart       Dio HTTP (interface, so tests use a fake)
    feed_parser.dart        RSS/Atom/RDF → ParsedFeed, plus feed discovery in HTML
    background_sync.dart    Workmanager dispatcher and scheduling (feeds,
                            new chapter checks); opens its own DB connection
    chapter_alerts.dart     new chapter notifications
    ranobes.dart            reading ranobes.net pages
  state/                    ChangeNotifiers: settings, feeds, articles (inbox),
                            article images (background picture lookups),
                            novels (the library)
  screens/                  home shell, inbox, article detail, feeds, settings
    novels/                 library, add novel, novel page, chapter reader
  widgets/                  article tile, add-feed dialog, HTML renderer,
                            cached images with a zoomable viewer
  utils/                    date parsing, HTML → text, date formatting,
                            arXiv (summaries, figures), finding page images,
                            reader mode (an article out of its web page)
tool/
  icon/                     the app icon's source SVG and the scripts that
                            draw it and render every Android and iOS size
```

- **State**: `provider` with three `ChangeNotifier`s. `FeedsProvider` and
  `ArticlesProvider` notify each other through callbacks set in `app.dart`
  (a new feed reloads the inbox; marking articles read updates the feed
  counts).
- **Database**: `feeds` and `articles` tables. Articles are unique per
  `(feedId, guid)` and inserted with `INSERT OR IGNORE`, so refreshes never
  reset read state. Swiped-away articles are soft-deleted (`isDeleted`) for
  the same reason. Deleting a feed removes its articles through a foreign key
  cascade.
- **Scrolling**: the inbox loads 100 rows at a time and leaves out the
  summary and content columns. The reader loads the full article by id.

### Data model

| feeds | | articles | |
|---|---|---|---|
| id | int PK | id | int PK |
| url | text, unique | feedId | int FK → feeds, cascade |
| title | text | guid | text, unique per feed |
| siteUrl | text? | title | text |
| lastUpdated | epoch ms? | author | text? |
| syncStatus | never / ok / error | url | text? |
| lastError | text? | pubDate | epoch ms? |
| favicon | blob? | summary | text? (HTML) |
| topic | tags, e.g. `ml,ic` | content | text? (HTML) |
| | | isRead | 0/1 |
| | | isDeleted | 0/1 |
| | | addedDate | epoch ms |
| | | imageUrl | text? (sample picture) |
| | | imageChecked | 0/1 (page looked at for a picture and full text) |
| | | figures | text? (JSON, arXiv) |
| | | figuresState | 0 unknown / 1 found / 2 no HTML |
| | | wordCount | int (best body's length) |
| | | fullContent | text? (HTML from the web page) |
| | | tags | text? (from its own words, e.g. `ic,claude`) |
| | | starred | 0/1 |

| novels | | chapters (saved for offline) | |
|---|---|---|---|
| id | int PK | url | text PK |
| url | text (its page) | novelId | int FK → novels, cascade |
| bookId | int, unique (site's number) | title | text |
| title, cover, author, status, description | text? | novelTitle | text? |
| chapterCount | int | body | text (paragraphs, blank-line separated) |
| addedDate, lastChecked, readAt | epoch ms | prevUrl, nextUrl | text? |
| chapterUrl, chapterTitle | text? (where you are) | fetchedAt | epoch ms |
| chapterNumber | int (from 1; 0 unknown) | | |
| chapterProgress | real 0–1 (how far down) | | |
| seenCount | int (chapters when last read) | | |
| notifiedCount | int (chapters when last announced) | | |

### Package notes

- **Parsing** uses [`rss_dart`](https://pub.dev/packages/rss_dart), a
  maintained successor of `webfeed`. `webfeed` 0.7 caps the SDK at `<3.0.0`
  and won't resolve on current Flutter.
- **Article bodies** are rendered by Scry's own small HTML renderer
  (`lib/widgets/html_view.dart`, built on `package:html`) rather than a web
  view, so they follow the app's fonts and colours. Scripts, forms and
  embedded players are left out; **Open in browser** shows the original.
- **Images** use [`cached_network_image`](https://pub.dev/packages/cached_network_image),
  which keeps them on disk for offline reading.

## App icon

The icon is generated, not hand-drawn. `tool/icon/scry_icon.py` paints the
sphere from many separate brush strokes (seed 11), and
`tool/icon/render_icons.py` renders it with headless Chrome into the Android
`mipmap-*` folders and the iOS `AppIcon.appiconset`. See
[tool/icon/README.md](tool/icon/README.md); a different seed gives a new
arrangement of strokes.

## iOS background refresh

Not set up. iOS needs the `fetch`/`processing` background modes,
`BGTaskSchedulerPermittedIdentifiers` in `Info.plist`, and a registration call
in `AppDelegate.swift` (see the
[workmanager iOS guide](https://pub.dev/packages/workmanager)). Even then iOS
decides when to run tasks. On iOS the app refreshes on launch and on
pull-to-refresh, and the sync setting is greyed out.

## Roadmap

- Search and keyword filters
- OPML import/export and backup
- Auto-tagging articles by category with a local LLM
- Pruning very old articles
