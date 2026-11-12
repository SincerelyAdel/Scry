import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One synced thing (a novel, a passage, a feed) as plain JSON values.
/// Anything under `meta` travels with it but doesn't count as a change.
typedef SyncItem = Map<String, Object?>;

/// Picks between two versions of an item both devices changed.
typedef Resolve = SyncItem Function(SyncItem local, SyncItem remote);

/// What this device knew at its last sync: a fingerprint of each item,
/// and the items it couldn't keep (a book that isn't on this device).
class SyncBase {
  const SyncBase({this.prints = const {}, this.held = const {}});

  /// Fingerprints by collection, then by key.
  final Map<String, Map<String, String>> prints;

  /// Keys of items kept only in Drive, by collection.
  final Map<String, Set<String>> held;

  static const empty = SyncBase();

  factory SyncBase.fromJson(Map<String, Object?> json) => SyncBase(
    prints: {
      for (final e in ((json['prints'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as Map).cast<String, String>(),
    },
    held: {
      for (final e in ((json['held'] as Map?) ?? const {}).entries)
        e.key as String: {...(e.value as List).cast<String>()},
    },
  );

  Map<String, Object?> toJson() => {
    'prints': prints,
    'held': {for (final e in held.entries) e.key: e.value.toList()..sort()},
  };
}

/// One collection after merging.
class MergedCollection {
  MergedCollection(this.state, this.prints, this.changes);

  /// Everything, as it should now be in Drive.
  final Map<String, SyncItem> state;

  /// Fingerprints of [state].
  final Map<String, String> prints;

  /// What this device should change: the item's new version, or null to
  /// remove it.
  final Map<String, SyncItem?> changes;
}

abstract final class SyncMerge {
  /// A fingerprint of [item], leaving out its `meta`.
  static String print(SyncItem item) {
    final copy = {...item}..remove('meta');
    return sha1.convert(utf8.encode(canonical(copy))).toString();
  }

  /// [value] as JSON with its keys in order, so equal items read the same.
  static String canonical(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? value) => switch (value) {
    Map() => {
      for (final k in value.keys.map((k) => k as String).toList()..sort())
        k: _sorted(value[k]),
    },
    List() => [for (final v in value) _sorted(v)],
    _ => value,
  };

  /// Merges this device's [local] items with [remote] ones from Drive, by
  /// what changed on each side since [prints] (the last sync). A change on
  /// one side wins over no change on the other; when both changed,
  /// [resolve] picks; an edit wins over a removal.
  ///
  /// [held] items aren't on this device on purpose: their absence here
  /// isn't a removal. One that's here again (its book imported again) is
  /// taken as changed on both sides, so [resolve] decides.
  static MergedCollection merge({
    required Map<String, SyncItem> local,
    required Map<String, SyncItem> remote,
    required Map<String, String> prints,
    required Set<String> held,
    required Resolve resolve,
  }) {
    final state = <String, SyncItem>{};
    final merged = <String, String>{};
    final changes = <String, SyncItem?>{};
    final keys = {...local.keys, ...remote.keys, ...prints.keys};
    for (final k in keys) {
      final l = local[k], r = remote[k], b = prints[k];
      final lp = l == null ? null : print(l);
      final rp = r == null ? null : print(r);
      final bool localChanged;
      if (l != null) {
        localChanged = lp != b;
      } else {
        localChanged = !held.contains(k) && b != null;
      }
      final remoteChanged = r != null ? rp != b : b != null;

      SyncItem? v;
      if (held.contains(k) && l != null && r != null) {
        v = resolve(l, r);
      } else if (!localChanged && !remoteChanged) {
        v = l ?? r;
      } else if (localChanged && !remoteChanged) {
        v = l;
      } else if (!localChanged && remoteChanged) {
        v = r;
      } else {
        v = l != null && r != null ? resolve(l, r) : (l ?? r);
      }
      if (v == null) {
        if (l != null) changes[k] = null;
        continue;
      }
      final vp = print(v);
      state[k] = v;
      merged[k] = vp;
      if (vp != lp) changes[k] = v;
    }
    return MergedCollection(state, merged, changes);
  }
}
