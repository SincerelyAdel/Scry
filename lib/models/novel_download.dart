/// Where a novel's download is.
enum DownloadState {
  /// Waiting for the background worker.
  queued,

  /// Being downloaded now.
  running,

  /// Stopped by ranobes.net's human check; resumes once it's passed.
  needsCheck,

  /// Paused by the reader.
  paused,

  /// Every chapter there was is saved.
  done,
}

/// A whole novel being downloaded for offline reading.
class NovelDownload {
  const NovelDownload({
    required this.novelId,
    required this.state,
    this.done = 0,
    this.total = 0,
    this.message,
    required this.updatedAt,
  });

  final int novelId;
  final DownloadState state;

  /// Chapters saved, out of [total] (0 while the list is being read).
  final int done;
  final int total;

  /// What it's doing or why it stopped, for people.
  final String? message;
  final DateTime updatedAt;

  /// Queued or running.
  bool get active =>
      state == DownloadState.queued || state == DownloadState.running;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  NovelDownload copyWith({
    DownloadState? state,
    int? done,
    int? total,
    String? message,
    bool clearMessage = false,
  }) {
    return NovelDownload(
      novelId: novelId,
      state: state ?? this.state,
      done: done ?? this.done,
      total: total ?? this.total,
      message: clearMessage ? null : message ?? this.message,
      updatedAt: DateTime.now(),
    );
  }

  factory NovelDownload.fromMap(Map<String, Object?> map) => NovelDownload(
    novelId: map['novelId'] as int,
    state:
        DownloadState.values.asNameMap()[map['state']] ?? DownloadState.paused,
    done: (map['done'] as int?) ?? 0,
    total: (map['total'] as int?) ?? 0,
    message: map['message'] as String?,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
  );

  Map<String, Object?> toMap() => {
    'novelId': novelId,
    'state': state.name,
    'done': done,
    'total': total,
    'message': message,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}
