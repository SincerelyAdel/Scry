# Scry

A calm, offline-first RSS/Atom reader for Android and iOS, built with Flutter.
It shares its look with its sibling app, RepoViewer: near-black and gold (or
warm cream in light mode), serif headings, rounded cards and a soft gold glow
around the screen edge.
Subscribe to tech blogs and paper feeds, read everything in one inbox, and
keep reading without a connection.

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
- **Topics**: each feed is about machine learning (**ML**, purple) or chips
  and IC design (**IC**, teal). The topic is guessed when a feed is added
  (from arXiv categories and names) and can be changed from the feed's menu.
  Chips at the top of the inbox show one topic at a time.
- **Badges**: inbox cards and the reader show the feed's topic, **Paper** for
  arXiv papers, and the read time once the article's length is known.
- **Unified inbox**: every feed's articles merged into one list, newest first,
  with unread dots. Sort by date, by feed, unread first, or by read time
  (quick or long reads first; papers and unfetched teasers go last); show
  only unread articles. On tablets the feed list sits beside the articles:
  tap a feed to see only its articles, and combine it with the topic chips.
- **Gestures**: swipe right to toggle read, swipe left to delete (with undo).
  Deleted articles don't come back on the next refresh.
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
  models/                   Feed, Article, ArticleSort, Topic
  data/
    app_database.dart       sqflite schema and every SQL query
    feed_repository.dart    fetch → parse → store; used by the UI and the worker
  services/
    feed_fetcher.dart       Dio HTTP (interface, so tests use a fake)
    feed_parser.dart        RSS/Atom/RDF → ParsedFeed, plus feed discovery in HTML
    background_sync.dart    Workmanager dispatcher and scheduling
  state/                    ChangeNotifiers: settings, feeds, articles (inbox),
                            article images (background picture lookups)
  screens/                  home shell, inbox, article detail, feeds, settings
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
| topic | ml / ic / null | content | text? (HTML) |
| | | isRead | 0/1 |
| | | isDeleted | 0/1 |
| | | addedDate | epoch ms |
| | | imageUrl | text? (sample picture) |
| | | imageChecked | 0/1 (page looked at for a picture and full text) |
| | | figures | text? (JSON, arXiv) |
| | | figuresState | 0 unknown / 1 found / 2 no HTML |
| | | wordCount | int (best body's length) |
| | | fullContent | text? (HTML from the web page) |

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
