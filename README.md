# Snippefy

A calm, offline-first RSS/Atom reader for Android and iOS, built with Flutter.
Subscribe to tech blogs and paper feeds, read everything in one inbox, and
keep reading without a connection.

> This repo used to hold a small PyQt tool for making VS Code snippets. It has
> been rewritten from scratch as an RSS reader; the name stuck.

## Features

- **Feeds**: add by feed URL *or* by a site's homepage (the app finds the
  advertised feed); RSS 2.0, RSS 1.0 (RDF) and Atom. The feed list shows the
  favicon, article and unread counts, the last update time, and any refresh
  error.
- **Unified inbox**: every feed's articles merged into one list, newest first,
  with unread dots. Sort by date, by feed, or unread first; show only unread
  articles; tap a feed to see only its articles.
- **Gestures**: swipe right to toggle read, swipe left to delete (with undo).
  Deleted articles don't come back on the next refresh.
- **Reader**: title, author, date, feed, and the body (full content when the
  feed includes it, otherwise the summary). Text is selectable. Buttons to
  open in the browser, share, and mark read or unread. Opening an article
  marks it read.
- **Offline**: feeds, articles and read state live in SQLite, so cached
  articles are readable without a connection.
- **Customization**: light, dark or system theme; 8 Material 3 accent colours;
  article text size; default sort. All saved with `shared_preferences`.
- **Background refresh** (Android): Workmanager refreshes feeds every 2 or 4
  hours (or never), only on a network and when the battery isn't low. Feeds
  also refresh when the app opens and when you pull down in the inbox.

## Getting started

```sh
flutter pub get
flutter run
```

Tap **Add feed** and pick a suggestion, or paste any feed or blog URL. The
suggestions are the Hugging Face blog, arXiv cs.AI, cs.LG and cs.CL, Simon
Willison, and Lil'Log. Papers with Code shut down in 2025 and Anthropic doesn't
publish an RSS feed, so neither is listed.

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
  models/                   Feed, Article, ArticleSort
  data/
    app_database.dart       sqflite schema and every SQL query
    feed_repository.dart    fetch → parse → store; used by the UI and the worker
  services/
    feed_fetcher.dart       Dio HTTP (interface, so tests use a fake)
    feed_parser.dart        RSS/Atom/RDF → ParsedFeed, plus feed discovery in HTML
    background_sync.dart    Workmanager dispatcher and scheduling
  state/                    ChangeNotifiers: settings, feeds, articles (inbox)
  screens/                  home shell, inbox, article detail, feeds, settings
  widgets/                  article tile, add-feed dialog
  utils/                    date parsing, HTML → text, date formatting
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
| | | content | text? (HTML) |
| | | isRead | 0/1 |
| | | isDeleted | 0/1 |
| | | addedDate | epoch ms |

### Package notes

- **Parsing** uses [`rss_dart`](https://pub.dev/packages/rss_dart), a
  maintained successor of `webfeed`. `webfeed` 0.7 caps the SDK at `<3.0.0`
  and won't resolve on current Flutter.
- **Article bodies** are converted from HTML to plain text with paragraph
  breaks and bullets kept (`package:html`), rather than rendered as HTML. That
  keeps the reader fast and themeable. Images and links are left out, and
  **Open in browser** shows the original page.

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
- Read-time estimates
- Auto-tagging articles by category with a local LLM
- Rich HTML rendering with inline images
- Pruning very old articles
