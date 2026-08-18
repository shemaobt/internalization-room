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
  final String path;
  final String sessionId;
  final String kind;
  final String scope;
  final int? passNumber;
  final int? chunkIndex;
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
  final DateTime? lastTry;

  const PendingTake({
    required this.id,
    required this.path,
    required this.sessionId,
    required this.kind,
    required this.scope,
    this.passNumber,
    this.chunkIndex,
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
        stored: stored ?? this.stored,
        lost: lost ?? this.lost,
        attempts: attempts ?? this.attempts,
        waits: waits ?? this.waits,
        lastTry: lastTry ?? this.lastTry,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'session_id': sessionId,
        'kind': kind,
        'scope': scope,
        'pass_number': passNumber,
        'chunk_index': chunkIndex,
        'stored': stored,
        'lost': lost,
        'attempts': attempts,
        'waits': waits,
        'last_try': lastTry?.toIso8601String(),
      };

  factory PendingTake.fromJson(Map<String, Object?> json) => PendingTake(
        id: json['id'] as String,
        path: json['path'] as String,
        sessionId: json['session_id'] as String,
        kind: json['kind'] as String,
        scope: json['scope'] as String,
        passNumber: json['pass_number'] as int?,
        chunkIndex: json['chunk_index'] as int?,
        stored: json['stored'] as bool? ?? false,
        lost: json['lost'] as bool? ?? false,
        attempts: json['attempts'] as int? ?? 0,
        waits: json['waits'] as int? ?? 0,
        lastTry: DateTime.tryParse(json['last_try'] as String? ?? ''),
      );
}

class TakeUploadQueue {
  final RoomRepository _room;
  final Future<Directory> Function() _home;
  final List<Duration> _backoff;
  final DateTime Function() _now;
  bool _flushing = false;
  Future<void> _writes = Future<void>.value();

  TakeUploadQueue({
    required RoomRepository room,
    Future<Directory> Function()? home,
    List<Duration> backoff = const [],
    DateTime Function()? now,
  })  : _room = room,
        _home = home ?? getApplicationSupportDirectory,
        _backoff = backoff,
        _now = now ?? DateTime.now;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestFile() async => File(p.join((await _dir()).path, _manifest));

  /// The queue as written on disk, or null when it could not be read.
  ///
  /// Null and an empty list must stay apart: empty means every take reached the room, and
  /// the beads paint full on the strength of it. A manifest that will not parse says
  /// nothing about where the audio is, and answering "nothing pending" to that told the
  /// team their recordings were safe on the word of a file we had just failed to read.
  Future<List<PendingTake>?> _written() async {
    final file = await _manifestFile();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return [
        for (final entry in raw) PendingTake.fromJson(entry as Map<String, Object?>),
      ];
    } on Object {
      return null;
    }
  }

  Future<List<PendingTake>> entries() async => await _written() ?? const [];

  Future<List<PendingTake>> pending() async =>
      [for (final entry in await entries()) if (!entry.stored) entry];

  Future<List<PendingTake>> waiting() async => [
        for (final entry in await pending())
          if (!entry.exhausted && !entry.lost) entry,
      ];

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

  Future<List<PendingTake>> giveUps() async => [
        for (final entry in await pending())
          if (entry.exhausted || entry.lost || entry.stalled) entry,
      ];

  bool _ready(PendingTake entry) {
    final last = entry.lastTry;
    if (last == null || entry.tries == 0 || _backoff.isEmpty) return true;
    final step = entry.tries - 1;
    final wait = _backoff[step < _backoff.length ? step : _backoff.length - 1];
    return !_now().isBefore(last.add(wait));
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
    final id = p.basenameWithoutExtension(audio.path);
    final kept = p.join(dir.path, '$kind-$id${p.extension(audio.path)}');
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

  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      var sent = 0;
      for (final entry in await waiting()) {
        if (!_ready(entry)) continue;
        final file = File(entry.path);
        if (!await file.exists()) {
          await _replace(entry, entry.copyWith(lost: true));
          continue;
        }
        try {
          await _room.sendTake(
            entry.sessionId,
            file,
            kind: entry.kind,
            scope: entry.scope,
            passNumber: entry.passNumber,
            chunkIndex: entry.chunkIndex,
          );
        } on RoomUnavailable {
          // Never reached the room: paced like any other retry, but it does not spend the
          // budget. A timeout is not a refusal, and treating it as one abandoned takes on
          // a slow link with the same finality as a server that said no.
          await _replace(
            entry,
            entry.copyWith(waits: entry.waits + 1, lastTry: _now()),
          );
          continue;
        } on Exception {
          await _replace(
            entry,
            entry.copyWith(attempts: entry.attempts + 1, lastTry: _now()),
          );
          continue;
        }
        await _replace(entry, entry.copyWith(stored: true));
        sent++;
      }
      return sent;
    } finally {
      _flushing = false;
    }
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
