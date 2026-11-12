import 'library_sync.dart';
import 'sync_merge.dart';

/// Where the shared copy of the library lives (Google Drive in the app).
abstract class RemoteStore {
  /// The file's id, version and contents; null when there's none yet.
  Future<({String id, String version, Map<String, Object?>? content})?> read();

  /// The file's version now.
  Future<String?> version(String id);

  /// Writes [content] to file [id], or a new file when null.
  Future<void> write(String? id, Map<String, Object?> content);
}

/// Another device kept writing while this one tried to sync.
class SyncBusyException implements Exception {
  const SyncBusyException();

  @override
  String toString() => 'Another device is syncing; try again in a moment';
}

/// One sync: reads the shared copy, merges it with this device's library,
/// writes the result back if it changed, then changes this device to
/// match.
class SyncEngine {
  SyncEngine(this._library, {required this.loadBase, required this.saveBase});

  final LibrarySync _library;
  final Future<SyncBase> Function() loadBase;
  final Future<void> Function(SyncBase base) saveBase;

  static const _collections = ['novels', 'passages', 'feeds'];

  Future<SyncOutcome> run(RemoteStore store) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final file = await store.read();
      final remote = file?.content == null
          ? const LibrarySnapshot()
          : LibrarySnapshot.fromJson(file!.content!);
      final local = await _library.snapshot();
      final base = await loadBase();

      final merged = {
        for (final name in _collections)
          name: SyncMerge.merge(
            local: local.collections[name]!,
            remote: remote.collections[name]!,
            prints: base.prints[name] ?? const {},
            held: base.held[name] ?? const {},
            resolve: name == 'novels' ? LibrarySync.resolveNovel : (l, r) => l,
          ),
      };
      final next = LibrarySnapshot(
        novels: merged['novels']!.state,
        passages: merged['passages']!.state,
        feeds: merged['feeds']!.state,
      );

      final changed =
          file?.content == null ||
          SyncMerge.canonical(next.collections) !=
              SyncMerge.canonical(remote.collections);
      if (changed) {
        // Someone else wrote it since it was read: merge again with theirs.
        if (file != null && await store.version(file.id) != file.version) {
          continue;
        }
        await store.write(file?.id, next.toJson());
      }

      final (outcome, held) = await _library.apply({
        for (final name in _collections) name: merged[name]!.changes,
      });
      await saveBase(
        SyncBase(
          prints: {for (final name in _collections) name: merged[name]!.prints},
          held: held,
        ),
      );
      return outcome;
    }
    throw const SyncBusyException();
  }
}
