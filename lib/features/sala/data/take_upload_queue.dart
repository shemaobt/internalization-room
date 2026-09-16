import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'room_repository.dart';

const _folder = 'guardadas';
const _manifest = 'fila.json';

const takeUploadAttempts = 5;

/// How many answerless tries pass before the room says a recording is stuck.
///
/// Waits deliberately never exhaust the budget — a weak link would spend all five tries
/// on five slow minutes and abandon audio the room may well have accepted. But the other
/// half of that decision was never built: a take that only ever times out kept retrying
/// forever and nobody was ever told. It keeps retrying; it just stops doing it in silence.
const takeUploadWaitsBeforeSaying = 8;
const unknownScope = '?';

final takeRetryBackoffProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ],
);

class PendingTake {
  final String id;
  /// Where the audio is right now, resolved against `guardadas/` every time the manifest
  /// is read.
  ///
  /// Only the file name is written down. The absolute path carries the container prefix
  /// the device hands out, and that prefix changes on a restore, a reinstall, or a move
  /// to another tablet — after which every row pointed at a directory that no longer
  /// existed and the queue called recordings lost while the files sat untouched beside it.
  final String path;
  final String sessionId;
  final String kind;
  final String scope;
  final int? passNumber;
  final int? chunkIndex;
  /// The name the room gave this recording, once it answered. A told-back stretch is a
  /// slice of one file and names it, so this is what the retro sends.
  final String? takeId;
  final bool stored;
  /// The audio this row points at is no longer on disk.
  ///
  /// `stored` is the queue's only word for "the room has it", and a vanished file used to
  /// be written as `stored` — turning a lost recording into a delivered one, after which
  /// nothing could tell the two apart. Lost is its own answer: it still counts as
  /// outstanding, it is never retried, and it is what the room says out loud.
  final bool lost;
  /// Times the room answered and refused. Only these spend the budget.
  final int attempts;
  /// Times the request never got an answer. These pace the retries but never exhaust
  /// them: a tablet on a weak link would otherwise spend all five tries on five slow
  /// minutes and abandon a recording the room may well have accepted.
  final int waits;
  /// When this row was last tried, written down as UTC.
  ///
  /// A local ISO string carries no zone at all, so the same instant written in one
  /// timezone and read back in one behind it comes back as a time in the future — and a
  /// stamp in the future is what used to stop a row from ever being tried again. Rows the
  /// older app wrote are still zoneless and are still read; they come due just the same.
  final DateTime? lastTry;

  const PendingTake({
    required this.id,
    required this.path,
    required this.sessionId,
    required this.kind,
    required this.scope,
    this.passNumber,
    this.chunkIndex,
    this.takeId,
    this.stored = false,
    this.lost = false,
    this.attempts = 0,
    this.waits = 0,
    this.lastTry,
  });

  bool get exhausted => attempts >= takeUploadAttempts;

  bool get stalled => waits >= takeUploadWaitsBeforeSaying;

  int get tries => attempts + waits;

  PendingTake copyWith({
    String? takeId,
    bool? stored,
    bool? lost,
    int? attempts,
    int? waits,
    DateTime? lastTry,
  }) =>
      PendingTake(
        id: id,
        path: path,
        sessionId: sessionId,
        kind: kind,
        scope: scope,
        passNumber: passNumber,
        chunkIndex: chunkIndex,
        takeId: takeId ?? this.takeId,
        stored: stored ?? this.stored,
        lost: lost ?? this.lost,
        attempts: attempts ?? this.attempts,
        waits: waits ?? this.waits,
        lastTry: lastTry ?? this.lastTry,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': p.basename(path),
        'session_id': sessionId,
        'kind': kind,
        'scope': scope,
        'pass_number': passNumber,
        'chunk_index': chunkIndex,
        'take_id': takeId,
        'stored': stored,
        'lost': lost,
        'attempts': attempts,
        'waits': waits,
        'last_try': lastTry?.toUtc().toIso8601String(),
      };

  factory PendingTake.fromJson(
    Map<String, Object?> json, {
    required String folder,
  }) =>
      PendingTake(
        id: json['id'] as String,
        path: p.join(
          folder,
          p.basename((json['name'] ?? json['path']) as String),
        ),
        sessionId: json['session_id'] as String,
        kind: json['kind'] as String,
        scope: json['scope'] as String,
        passNumber: json['pass_number'] as int?,
        chunkIndex: json['chunk_index'] as int?,
        takeId: json['take_id'] as String?,
        stored: json['stored'] as bool? ?? false,
        lost: json['lost'] as bool? ?? false,
        attempts: json['attempts'] as int? ?? 0,
        waits: json['waits'] as int? ?? 0,
        // The row's audio and session are intact; only its pacing is unknown, and an
        // unknown pace means due now. Raising here instead would set every pending
        // recording aside, not this one.
        lastTry: switch (json['last_try']) {
          final String stamp => DateTime.tryParse(stamp),
          _ => null,
        },
      );
}

class TakeUploadQueue {
  final RoomRepository _room;
  final Future<Directory> Function() _home;
  final List<Duration> _backoff;
  final DateTime Function() _now;
  Future<int>? _flushInFlight;
  bool _flushAgainRequested = false;
  Future<void> _writes = Future<void>.value();
  int _minted = 0;

  TakeUploadQueue({
    required this._room,
    Future<Directory> Function()? home,
    this._backoff = const [],
    DateTime Function()? now,
  })  : _home = home ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestFile() async => File(p.join((await _dir()).path, _manifest));

  String _mintId() => '${DateTime.now().microsecondsSinceEpoch}-${_minted++}';

  /// The queue as written on disk, or null when it could not be read.
  ///
  /// Null and an empty list must stay apart: empty means every take reached the room, and
  /// the beads paint full on the strength of it. A manifest that will not parse says
  /// nothing about where the audio is, and answering "nothing pending" to that told the
  /// team their recordings were safe on the word of a file we had just failed to read.
  Future<List<PendingTake>?> _written() async {
    final folder = (await _dir()).path;
    final file = File(p.join(folder, _manifest));
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return [
        for (final entry in raw)
          PendingTake.fromJson(entry as Map<String, Object?>, folder: folder),
      ];
    } on Object {
      return null;
    }
  }

  Future<List<PendingTake>> entries() async => await _written() ?? const [];

  Future<List<PendingTake>> pending() async =>
      [for (final entry in await entries()) if (!entry.stored) entry];

  /// Whether a written-off row's audio really is off the tablet.
  ///
  /// Writing a row off is a guess about the disk — it is made because the file could not
  /// be found at flush time — and for a whole generation of rows the guess was simply
  /// wrong: the queue stored absolute paths, a restore changed the container prefix, and
  /// present audio read as absent. That resolution is fixed, but nothing ever revisited
  /// the rows it had already condemned, so there are tablets holding recordings the app
  /// decided were gone while the files sat untouched beside them. The flag alone is
  /// therefore not the answer to "is this recording gone"; the disk is.
  ///
  /// Both readings of that question come through here, so there is one definition of
  /// gone and not two: the rows a flush will try, and the rows the room speaks about. If
  /// they could disagree, the room would call a recording stranded while the queue was
  /// busy uploading it.
  ///
  /// It only ever reads — one stat per written-off row, none at all for a queue with
  /// nothing written off, and no manifest written. Letting the flush loop find out for
  /// itself instead would rewrite the manifest once per condemned row per flush.
  Future<bool> _reallyGone(PendingTake entry) async =>
      entry.lost && !await File(entry.path).exists();

  /// The rows a flush will try. A written-off row is back among them the moment its
  /// audio is on the disk again; one whose audio really is gone stays out, so the queue
  /// still empties.
  Future<List<PendingTake>> waiting() async {
    final trying = <PendingTake>[];
    for (final entry in await pending()) {
      if (entry.exhausted || await _reallyGone(entry)) continue;
      trying.add(entry);
    }
    return trying;
  }

  /// Whether a manifest this queue could not read was set aside.
  ///
  /// Its rows named audio that is still on the tablet and the session each one belonged
  /// to — and the session is the part no scan of the files can recover. The room is not
  /// allowed to imply everything reached the server after that.
  Future<bool> lostHistory() async => (await _quarantineFile()).exists();

  Future<File> _quarantineFile() async =>
      File(p.join((await _dir()).path, '$_manifest.ilegivel'));

  /// How many takes of this kind are still on the tablet — and never zero on a doubt.
  ///
  /// A manifest we cannot read is counted as one outstanding take rather than none: the
  /// bead stays hollow, the room keeps saying there is something to send, and the error
  /// falls on the safe side of a recording nobody is allowed to lose.
  Future<int> unsentOf(String kind, {required String sessionId}) async {
    final written = await _written();
    if (written == null) return 1;
    return [
      for (final entry in written)
        if (!entry.stored && entry.kind == kind && entry.sessionId == sessionId) entry,
    ].length;
  }

  /// What the room called the recording this row holds, or null while it has not answered
  /// for it yet.
  ///
  /// By row, never by scope: a part recorded again is a second row under the scope the
  /// part already had, and the first row's name, handed back for the second row's audio,
  /// would send every stretch of the new recording to the one nobody will hear again.
  Future<String?> takeIdOf(String row) async {
    for (final entry in (await _written() ?? const <PendingTake>[])) {
      if (entry.id == row) return entry.takeId;
    }
    return null;
  }

  Future<Set<String>> unsentScopesOf(String kind, {required String sessionId}) async {
    final written = await _written();
    if (written == null) return {unknownScope};
    return {
      for (final entry in written)
        if (!entry.stored && entry.kind == kind && entry.sessionId == sessionId)
          entry.scope,
    };
  }

  /// The rows the room says out loud, because nothing more will happen to them on their
  /// own. A row written off while its audio is still on the tablet is not one of them —
  /// the next flush picks it up, and saying it is stranded would be a false alarm on
  /// exactly the tablets that recovery exists for.
  Future<List<PendingTake>> giveUps() async {
    final givenUp = <PendingTake>[];
    for (final entry in await pending()) {
      if (entry.exhausted || entry.stalled || await _reallyGone(entry)) {
        givenUp.add(entry);
      }
    }
    return givenUp;
  }

  bool _ready(PendingTake entry) {
    final last = entry.lastTry;
    if (last == null || entry.tries == 0 || _backoff.isEmpty) return true;
    final now = _now();
    // A stamp we could not have written yet says nothing about when we last tried.
    //
    // The guard belongs here rather than in the pacing: a row that fails this check never
    // reaches the send path, so its stamp is never rewritten, so it fails again — forever.
    //
    // Any amount ahead, not only an implausible one. A corrupt stamp far in the future
    // would stay stuck for good under a threshold rule and cures itself under this one,
    // and flush() runs on events, never on a timer, so the extra try cannot spin.
    if (last.isAfter(now)) return true;
    final step = entry.tries - 1;
    final wait = _backoff[step < _backoff.length ? step : _backoff.length - 1];
    return !now.isBefore(last.add(wait));
  }

  Future<void> _write(List<PendingTake> entries) async {
    final file = await _manifestFile();
    final staging = File('${file.path}.novo');
    await staging.writeAsString(
      jsonEncode([for (final e in entries) e.toJson()]),
      flush: true,
    );
    await staging.rename(file.path);
  }

  /// Rewrite the manifest from what is actually on disk, one writer at a time.
  ///
  /// Both writers used to build the new list from `entries()`, which reads an unreadable
  /// file as an empty queue: the first recording after a truncated `fila.json` replaced
  /// the ledger of every pending take with a single row, and the audio those rows named
  /// became orphans nothing would ever scan again. Neither writer held a lock either, so
  /// a keep racing a flush wrote a list built before the other's — dropping the take that
  /// had just been enqueued.
  Future<void> _mutate(
    List<PendingTake> Function(List<PendingTake> written) change,
  ) {
    final next = _writes.then((_) async {
      final written = await _written();
      if (written == null) {
        await (await _manifestFile()).rename((await _quarantineFile()).path);
        await _write(change(const []));
        return;
      }
      await _write(change(written));
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    final dir = await _dir();
    final id = _mintId();
    final name = p.basenameWithoutExtension(audio.path);
    final kept = p.join(dir.path, '$kind-$name-$id${p.extension(audio.path)}');
    if (audio.path != kept) {
      await audio.copy(kept);
    }
    final entry = PendingTake(
      id: id,
      path: kept,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
    );
    await _mutate((written) => [...written, entry]);
    return entry;
  }

  /// Send every row a caller that only asked while this call was already running would
  /// otherwise miss.
  ///
  /// A second `flush()` called while the first is still talking to the room used to
  /// return at once, on the strength of the first one's own sweep — but a row enqueued
  /// after that sweep already started is not in it, and the caller who just enqueued it
  /// read the empty answer as "the room has this" and never asked again. It now waits on
  /// the flush already running and, if anything was asked for while it waited, that flush
  /// takes one more pass before either caller is told it is done.
  Future<int> flush() {
    final running = _flushInFlight;
    if (running != null) {
      _flushAgainRequested = true;
      return running;
    }
    return _flushInFlight = _flushUntilSettled();
  }

  Future<int> _flushUntilSettled() async {
    var sent = 0;
    try {
      do {
        _flushAgainRequested = false;
        sent += await _flushOnce();
      } while (_flushAgainRequested);
    } finally {
      _flushInFlight = null;
    }
    return sent;
  }

  Future<int> _flushOnce() async {
    var sent = 0;
    for (final entry in await waiting()) {
      if (!_ready(entry)) continue;
      final file = File(entry.path);
      if (!await file.exists()) {
        // Already written off and gone again between the check above and here: the row
        // is already saying so, and rewriting the manifest to say it twice is a write
        // for no change of state.
        if (!entry.lost) await _replace(entry, entry.copyWith(lost: true));
        continue;
      }
      // The audio is here, so the row stops carrying a word that is no longer true.
      // `lost` is what the room speaks from, and a recording being sent right now is
      // not one that was given up on. Every outcome below writes this back.
      final row = entry.lost ? entry.copyWith(lost: false) : entry;
      final String landed;
      try {
        landed = await _room.sendTake(
          entry.sessionId,
          file,
          kind: entry.kind,
          scope: entry.scope,
          passNumber: entry.passNumber,
          chunkIndex: entry.chunkIndex,
        );
      } on RoomUnavailable {
        await _replace(
          entry,
          row.copyWith(waits: row.waits + 1, lastTry: _now()),
        );
        continue;
      } on RoomSlow {
        await _replace(
          entry,
          row.copyWith(waits: row.waits + 1, lastTry: _now()),
        );
        continue;
      } on Exception {
        await _replace(
          entry,
          row.copyWith(attempts: row.attempts + 1, lastTry: _now()),
        );
        continue;
      }
      await _replace(entry, row.copyWith(takeId: landed, stored: true));
      sent++;
    }
    return sent;
  }

  Future<void> _replace(PendingTake target, PendingTake updated) =>
      _mutate((written) => [
            for (final entry in written)
              if (entry.id == target.id && entry.kind == target.kind)
                updated
              else
                entry,
          ]);
}

final takeUploadQueueProvider = Provider<TakeUploadQueue>(
  (ref) => TakeUploadQueue(
    room: ref.read(roomRepositoryProvider),
    backoff: ref.read(takeRetryBackoffProvider),
  ),
);
