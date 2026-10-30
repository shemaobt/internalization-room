import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/kept_take.dart';
import '../domain/machine.dart';
import '../domain/scene_rehearsal.dart';
import '../domain/wav.dart';
import 'recording_repository.dart';
import 'room_answer.dart';
import 'room_repository.dart';
import 'staged_write.dart';

const _folder = 'guardadas';
const _manifest = 'fila.json';

const takeUploadAttempts = 3;

const sentenceKind = 'frase';

/// The kind an older build gave the Back-translation's stretches in the Outbox.
const _theBackTranslationsOldKind = 'retro';

const largestTakeTheRoomKeeps = 25 * 1024 * 1024;

const largestSentenceTheRoomTakes = 4 * 1024 * 1024;

typedef OutboxTally = ({
  int unsentTakes,
  int unsentChunks,
  Map<String, List<PendingTake>> unsentParts,
  Map<String, int> goneParts,
  Map<String, PartFact> parts,
});

final takeAttemptSpacingProvider = Provider<List<Duration>>(
  (ref) => const [Duration(seconds: 1), Duration(seconds: 3)],
);

typedef TakeLeaving = ({PendingTake take, DateTime since});

class TheLifeEnded implements Exception {
  const TheLifeEnded();
}

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

  /// The session the row goes up into; none while its passage has no session the room
  /// still knows.
  final String? sessionId;

  /// The passage the row belongs to, as `book/pericope/language`, so a row whose session
  /// is gone is found again by the passage's next session. A row an older app wrote has
  /// none.
  final String? passage;
  final String kind;
  final String scope;
  final int? passNumber;
  final int? chunkIndex;
  final String? scene;
  final String? original;

  /// The name the room gave this recording, once it answered. A told-back stretch is a
  /// slice of one file and names it, so this is what the retro sends.
  final String? takeId;
  final bool stored;

  /// The audio this row points at is no longer on disk.
  ///
  /// `stored` is the queue's only word for "the room has it", and a vanished file used to
  /// be written as `stored` — turning a lost recording into a delivered one, after which
  /// nothing could tell the two apart. Lost is its own answer: it still counts as
  /// outstanding and it is never retried.
  final bool lost;

  /// Attempts spent at this take: a refusal, a network failure, a timeout, an answer the
  /// room's list did not hold, a stop.
  final int attempts;

  /// Times the room turned the tablet away rather than the take, and times a join row
  /// (one with an origin) fell on the network; neither spends an attempt.
  final int waits;

  /// When this row was last tried, written down as UTC. A tap that makes the row due
  /// again clears it.
  final DateTime? lastTry;

  final String? refusal;

  /// When the recording stopped, on the tablet's clock; its length when it is a WAV; and
  /// the sha256 of the bytes that go up. Fixed when the row is written and sent unchanged
  /// on every try. A row an older app wrote has none and sends none.
  final DateTime? recordedAt;
  final int? durationMs;
  final String? sha256;

  /// The Scene rehearsal a join row's bytes are, and whether the team armed the reopening
  /// of an approved draft for it. A row an older app wrote has neither.
  final String? origin;
  final bool reopensTheApprovedDraft;

  /// The part's take a join row replaces, as the room listed it when the row was
  /// written; none over an empty scene. The room turns the row away for good when the
  /// part's take is another by then.
  final String? overTake;

  const PendingTake({
    required this.id,
    required this.path,
    required this.sessionId,
    this.passage,
    required this.kind,
    required this.scope,
    this.passNumber,
    this.chunkIndex,
    this.scene,
    this.original,
    this.takeId,
    this.stored = false,
    this.lost = false,
    this.attempts = 0,
    this.waits = 0,
    this.lastTry,
    this.refusal,
    this.recordedAt,
    this.durationMs,
    this.sha256,
    this.origin,
    this.reopensTheApprovedDraft = false,
    this.overTake,
  });

  bool get exhausted => attempts >= takeUploadAttempts;

  SendFailure get failure => switch (refusal) {
    null => SendFailure.failed,
    RefusalCode.tooLarge => SendFailure.tooLarge,
    _ => SendFailure.refused,
  };

  /// The row as it goes into [sessionId], kept under [passage] so the passage's next
  /// session can find it once that session is gone.
  PendingTake inTheSession(String? sessionId, {String? passage}) => PendingTake(
    id: id,
    path: path,
    sessionId: sessionId,
    passage: passage ?? this.passage,
    kind: kind,
    scope: scope,
    passNumber: passNumber,
    chunkIndex: chunkIndex,
    scene: scene,
    original: original,
    takeId: takeId,
    stored: stored,
    lost: lost,
    attempts: attempts,
    waits: waits,
    lastTry: lastTry,
    refusal: refusal,
    recordedAt: recordedAt,
    durationMs: durationMs,
    sha256: sha256,
    origin: origin,
    reopensTheApprovedDraft: reopensTheApprovedDraft,
    overTake: overTake,
  );

  PendingTake dueNow() => PendingTake(
    id: id,
    path: path,
    sessionId: sessionId,
    passage: passage,
    kind: kind,
    scope: scope,
    passNumber: passNumber,
    chunkIndex: chunkIndex,
    scene: scene,
    original: original,
    takeId: takeId,
    lost: lost,
    recordedAt: recordedAt,
    durationMs: durationMs,
    sha256: sha256,
    origin: origin,
    reopensTheApprovedDraft: reopensTheApprovedDraft,
    overTake: overTake,
  );

  bool get refusedWithNoCode =>
      exhausted && RefusalCode.namesNothing(refusal ?? '');

  int get tries => attempts + waits;

  PendingTake copyWith({
    String? takeId,
    bool? stored,
    bool? lost,
    int? attempts,
    int? waits,
    DateTime? lastTry,
    String? refusal,
  }) => PendingTake(
    id: id,
    path: path,
    sessionId: sessionId,
    passage: passage,
    kind: kind,
    scope: scope,
    passNumber: passNumber,
    chunkIndex: chunkIndex,
    scene: scene,
    original: original,
    takeId: takeId ?? this.takeId,
    stored: stored ?? this.stored,
    lost: lost ?? this.lost,
    attempts: attempts ?? this.attempts,
    waits: waits ?? this.waits,
    lastTry: lastTry ?? this.lastTry,
    refusal: refusal ?? this.refusal,
    recordedAt: recordedAt,
    durationMs: durationMs,
    sha256: sha256,
    origin: origin,
    reopensTheApprovedDraft: reopensTheApprovedDraft,
    overTake: overTake,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': p.basename(path),
    'session_id': sessionId,
    'passage': passage,
    'kind': kind,
    'scope': scope,
    'pass_number': passNumber,
    'chunk_index': chunkIndex,
    'scene': scene,
    'original': original,
    'take_id': takeId,
    'stored': stored,
    'lost': lost,
    'attempts': attempts,
    'waits': waits,
    'last_try': lastTry?.toUtc().toIso8601String(),
    'refusal': refusal,
    'recorded_at': recordedAt?.toUtc().toIso8601String(),
    'duration_ms': durationMs,
    'sha256': sha256,
    'origin': origin,
    'reopens_the_approved_draft': reopensTheApprovedDraft,
    'over_take': overTake,
  };

  factory PendingTake.fromJson(
    Map<String, Object?> json, {
    required String folder,
  }) => PendingTake(
    id: json['id'] as String,
    path: p.join(folder, p.basename((json['name'] ?? json['path']) as String)),
    sessionId: json['session_id'] as String?,
    passage: json['passage'] as String?,
    kind: json['kind'] as String,
    scope: json['scope'] as String,
    passNumber: json['pass_number'] as int?,
    chunkIndex: json['chunk_index'] as int?,
    scene: json['scene'] as String?,
    original: json['original'] as String?,
    takeId: json['take_id'] as String?,
    stored: json['stored'] as bool? ?? false,
    lost: json['lost'] as bool? ?? false,
    attempts: json['attempts'] as int? ?? 0,
    waits: json['waits'] as int? ?? 0,
    // The row's audio and session are intact; only its stamp is unreadable. Raising here
    // instead would set every pending recording aside, not this one.
    lastTry: switch (json['last_try']) {
      final String stamp => DateTime.tryParse(stamp),
      _ => null,
    },
    refusal: switch (json['refusal']) {
      final String code => code,
      _ => null,
    },
    recordedAt: switch (json['recorded_at']) {
      final String stamp => DateTime.tryParse(stamp),
      _ => null,
    },
    durationMs: json['duration_ms'] as int?,
    sha256: json['sha256'] as String?,
    origin: json['origin'] as String?,
    reopensTheApprovedDraft:
        json['reopens_the_approved_draft'] as bool? ?? false,
    overTake: json['over_take'] as String?,
  );
}

Future<({int? durationMs, String sha256})> _whatTheCopyHolds(String path) =>
    Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      return (
        durationMs: wavLengthOf(bytes)?.inMilliseconds,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
    });

class _CachedRead {
  final String folder;
  final DateTime modified;
  final int size;
  final List<PendingTake>? rows;

  _CachedRead(this.folder, this.modified, this.size, this.rows);
}

class TakeUploadQueue {
  final RoomRepository _room;
  final Future<Directory> Function() _home;
  final List<Duration> _spacing;
  final DateTime Function() _now;
  Future<int>? _flushInFlight;
  bool _flushAgainRequested = false;
  Future<void> _writes = Future<void>.value();
  int _minted = 0;
  _CachedRead? _cachedRead;
  final Map<String, String?> _confirmed = {};
  final List<PendingTake> _landedRows = [];
  final Map<String, SceneRehearsalRecord> _keptScenes = {};

  /// The rows a tap of this life asked to send, each by the tap that asked last. Kept in
  /// memory only: a relaunch makes nothing due, and a row goes up again only on its own
  /// tap.
  final Map<String, int> _dueOnATap = {};
  int _taps = 0;

  final RecordingRepository Function() _recordings;

  TakeUploadQueue({
    required this._room,
    Future<Directory> Function()? home,
    this._spacing = const [],
    DateTime Function()? now,
    required this._recordings,
  }) : _home = home ?? getApplicationSupportDirectory,
       _now = now ?? clock.now;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestFile() async =>
      File(p.join((await _dir()).path, _manifest));

  String _mintId() => '${clock.now().microsecondsSinceEpoch}-${_minted++}';

  /// The queue as written on disk, or null when it could not be read.
  ///
  /// Null and an empty list must stay apart: empty means every take reached the room, and
  /// the beads paint full on the strength of it. A manifest that will not parse says
  /// nothing about where the audio is, and answering "nothing pending" to that told the
  /// team their recordings were safe on the word of a file we had just failed to read.
  Future<List<PendingTake>?> _written() async {
    final folder = (await _dir()).path;
    final file = File(p.join(folder, _manifest));
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      _cachedRead = null;
      return const [];
    }
    final cached = _cachedRead;
    if (cached != null &&
        cached.folder == folder &&
        cached.modified == stat.modified &&
        cached.size == stat.size) {
      final rows = cached.rows;
      return rows == null ? null : [for (final e in rows) e];
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      final rows = [
        for (final entry in raw)
          PendingTake.fromJson(entry as Map<String, Object?>, folder: folder),
      ];
      _cachedRead = _CachedRead(folder, stat.modified, stat.size, rows);
      return [for (final e in rows) e];
    } on Object {
      _cachedRead = _CachedRead(folder, stat.modified, stat.size, null);
      return null;
    }
  }

  Future<List<PendingTake>> entries() async => await _written() ?? const [];

  Future<List<PendingTake>> pending() async => [
    for (final entry in await entries())
      if (!entry.stored) entry,
  ];

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
  /// It only ever reads — one stat per written-off row, none at all for a queue with
  /// nothing written off, and no manifest written. Letting the flush loop find out for
  /// itself instead would rewrite the manifest once per condemned row per flush.
  Future<bool> _reallyGone(PendingTake entry) async =>
      entry.lost && !await File(entry.path).exists();

  bool Function(PendingTake row) _aRowOffersItsTap = (_) => true;

  /// [aRowOffersItsTap] says whether a row on screen can offer a take's tap. A take no row
  /// can show goes up after every take a row can show, and once spent, whatever spent it,
  /// it is never held for a tap, except a refused one, which the room would refuse
  /// again.
  void offerTheTapThrough(bool Function(PendingTake row) aRowOffersItsTap) =>
      _aRowOffersItsTap = aRowOffersItsTap;

  bool _spentForATap(PendingTake entry) =>
      entry.exhausted && (entry.refusal != null || _aRowOffersItsTap(entry));

  /// The rows a flush will try. A written-off row is back among them the moment its
  /// audio is on the disk again; one whose audio really is gone stays out, so the queue
  /// still empties.
  Future<List<PendingTake>> waiting() async {
    final scenes = <PendingTake>[];
    final trying = <PendingTake>[];
    final heldForATap = <String>{};
    for (final entry in await pending()) {
      if (entry.kind == sentenceKind || entry.sessionId == null) continue;
      final part = _partOf(entry);
      if (part != null && heldForATap.contains(part)) continue;
      if (_spentForATap(entry)) {
        if (part != null &&
            entry.refusal == null &&
            await File(entry.path).exists()) {
          heldForATap.add(part);
        }
        continue;
      }
      if (await _reallyGone(entry)) continue;
      (entry.kind == sceneTakeKind ? scenes : trying).add(entry);
    }
    return [
      ...scenes,
      for (final entry in trying)
        if (_aRowOffersItsTap(entry)) entry,
      for (final entry in trying)
        if (!_aRowOffersItsTap(entry)) entry,
    ];
  }

  Future<File> _quarantineFile() async =>
      File(p.join((await _dir()).path, '$_manifest.ilegivel'));

  /// How many takes of this kind are still on the tablet — and never zero on a doubt.
  ///
  /// A manifest we cannot read is counted as one outstanding take rather than none: the
  /// bead stays hollow, the room keeps saying there is something to send, and the error
  /// falls on the safe side of a recording nobody is allowed to lose.
  Future<int> unsentOf(String kind, {required String sessionId}) async =>
      _unsentIn(await _written(), kind, sessionId);

  static int _unsentIn(
    List<PendingTake>? written,
    String kind,
    String? sessionId, {
    String? passage,
  }) {
    if (written == null) return 1;
    return [
      for (final entry in written)
        if (!entry.stored &&
            entry.kind == kind &&
            _ofTheVisit(entry, sessionId, passage))
          entry,
    ].length;
  }

  /// What the room called the recording this row holds, or null while it has not answered
  /// for it yet.
  ///
  /// By row, never by scope: a part recorded again is a second row under the scope the
  /// part already had, and the first row's name, handed back for the second row's audio,
  /// would send every stretch of the new recording to the one nobody will hear again.
  Future<String?> takeIdOf(String row) async {
    if (_confirmed.containsKey(row)) return _confirmed[row];
    for (final entry in (await _written() ?? const <PendingTake>[])) {
      if (entry.id == row) return entry.takeId;
    }
    return null;
  }

  /// A row of [sessionId], or one of [passage] whose session is gone.
  static bool _ofTheVisit(
    PendingTake entry,
    String? sessionId,
    String? passage,
  ) => entry.sessionId == null
      ? passage != null && entry.passage == passage
      : entry.sessionId == sessionId;

  Future<String?> fingerprintOf(String path) async {
    try {
      return (await _whatTheCopyHolds(path)).sha256;
    } on FileSystemException {
      return null;
    }
  }

  String? takeIdOfThePart(String sessionId, KeptTake part) {
    final name = p.basenameWithoutExtension(part.path);
    for (final entry in _landedRows) {
      if (entry.sessionId == sessionId &&
          entry.scope == part.scopeId &&
          (entry.passNumber ?? 1) == part.pass &&
          p.basenameWithoutExtension(entry.path) ==
              '${entry.kind}-$name-${entry.id}') {
        return entry.takeId;
      }
    }
    return null;
  }

  Future<Map<String, List<PendingTake>>> _unsentPartsIn(
    List<PendingTake>? written,
    String? sessionId,
    String? passage,
  ) async {
    final parts = <String, List<PendingTake>>{};
    for (final entry in written ?? const <PendingTake>[]) {
      if (!entry.stored &&
          entry.kind == partTakeKind &&
          _ofTheVisit(entry, sessionId, passage) &&
          await File(entry.path).exists()) {
        parts.putIfAbsent(entry.scope, () => []).add(entry);
      }
    }
    return parts;
  }

  Future<Map<String, int>> _gonePartsIn(
    List<PendingTake>? written,
    String? sessionId,
    String? passage,
  ) async {
    final newest = <String, PendingTake>{};
    for (final entry in written ?? const <PendingTake>[]) {
      if (entry.kind != partTakeKind ||
          !_ofTheVisit(entry, sessionId, passage)) {
        continue;
      }
      final held = newest[entry.scope];
      if (held == null || (entry.passNumber ?? 1) >= (held.passNumber ?? 1)) {
        newest[entry.scope] = entry;
      }
    }
    return {
      for (final MapEntry(key: scope, value: entry) in newest.entries)
        if (!await File(entry.path).exists()) scope: entry.passNumber ?? 1,
    };
  }

  Future<Set<String>> _goneRowsOf(
    String? sessionId,
    String scope, {
    int? upToPass,
  }) async => {
    for (final entry in await entries())
      if (entry.kind == partTakeKind &&
          entry.sessionId == sessionId &&
          entry.scope == scope &&
          (upToPass == null || (entry.passNumber ?? 1) <= upToPass) &&
          !await File(entry.path).exists())
        entry.id,
  };

  Future<OutboxTally> tally({
    required String? sessionId,
    String? passage,
  }) async {
    final written = await _written();
    final waiting = await this.waiting();
    final trying = {
      for (final entry in waiting)
        if (await File(entry.path).exists()) entry.id,
    };
    final unsentParts = await _unsentPartsIn(written, sessionId, passage);
    return (
      parts: {
        for (final row in _confirmed.keys) row: PartFact.sent,
        for (final entry in written ?? const <PendingTake>[])
          entry.id: entry.stored
              ? PartFact.sent
              : trying.contains(entry.id)
              ? PartFact.pending
              : PartFact.stranded,
      },
      unsentTakes: written == null
          ? 1
          : unsentParts.values.fold(0, (count, rows) => count + rows.length),
      unsentChunks: written == null
          ? 1
          : _unsentIn(written, sentenceKind, sessionId, passage: passage),
      unsentParts: unsentParts,
      goneParts: await _gonePartsIn(written, sessionId, passage),
    );
  }

  String? _partOf(PendingTake entry) => switch (entry.kind) {
    partTakeKind => '${entry.sessionId}/${entry.scope}',
    sceneTakeKind => '${entry.sessionId}/$sceneTakeKind',
    _ => null,
  };

  Future<void> _write(List<PendingTake> entries) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, _manifest));
    await writeWhole(file, jsonEncode([for (final e in entries) e.toJson()]));
    final stat = await file.stat();
    _cachedRead = _CachedRead(dir.path, stat.modified, stat.size, [
      for (final e in entries) e,
    ]);
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
        _cachedRead = null;
        await (await _manifestFile()).rename((await _quarantineFile()).path);
        await _write(change(const []));
        return;
      }
      final changed = change(written);
      await _write([
        for (final entry in changed)
          if (!entry.stored) entry,
      ]);
      for (final entry in changed) {
        if (!entry.stored) continue;
        _confirmed[entry.id] ??= entry.takeId;
        await _deleteTheCopy(entry);
      }
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  bool _lifeEnded = false;

  Future<bool> endTheLife() async {
    _lifeEnded = true;
    try {
      await _mutate((_) => const []);
      final kept = await _inTurn(
        () => _deleteTheCopies(
          (copy) async => !_copiesBeingMade.containsKey(copy.path),
        ),
      );
      if (kept.isNotEmpty) return false;
      await _recordings().deleteEveryRecording();
      return true;
    } on FileSystemException {
      return false;
    } on MissingPlatformDirectoryException {
      return false;
    }
  }

  void beginALife() => _lifeEnded = false;

  /// The copies `enqueue` has made and not yet written a row for, each until its keep
  /// settles.
  final Map<String, Future<void>> _copiesBeingMade = {};

  bool _sweptTheCopies = false;

  /// Once per Outbox: every copy no row names leaves the folder, except the copy of the
  /// take in the air, one being made, and one a quarantined manifest may still name.
  Future<void> sweepTheCopiesLeftBehind() async {
    if (_sweptTheCopies) return;
    _sweptTheCopies = true;
    try {
      await _inTurn(() async {
        final written = await _written();
        if (written == null) return;
        final named = {for (final row in written) p.basename(row.path)};
        final quarantined = await _quarantineFile();
        final quarantinedAt = await quarantined.exists()
            ? await quarantined.lastModified()
            : null;
        await _deleteTheCopies(
          (copy) async =>
              !named.contains(p.basename(copy.path)) &&
              !_copiesBeingMade.containsKey(copy.path) &&
              _inTheAir?.path != copy.path &&
              (quarantinedAt == null ||
                  (await copy.lastModified()).isAfter(quarantinedAt)),
        );
      });
    } on FileSystemException catch (error) {
      debugPrint(
        'As cópias sem linha não puderam ser varridas da fila: $error',
      );
    } on MissingPlatformDirectoryException catch (error) {
      debugPrint(
        'As cópias sem linha não puderam ser varridas da fila: $error',
      );
    }
  }

  static final _aCopy = RegExp(
    '^(${[partTakeKind, sceneTakeKind, sentenceKind, _theBackTranslationsOldKind].join('|')})'
    r'-.+-\d+-\d+(\.[^.]+)?$',
  );

  Future<List<File>> _deleteTheCopies(
    Future<bool> Function(File copy) leaves,
  ) async {
    final kept = <File>[];
    await for (final entity in (await _dir()).list()) {
      if (!_aCopy.hasMatch(p.basename(entity.path))) continue;
      final copy = File(entity.path);
      if (!await leaves(copy)) continue;
      try {
        await copy.delete();
      } on FileSystemException {
        kept.add(copy);
      }
    }
    return kept;
  }

  /// [step] in a turn of its own on the manifest's write chain.
  Future<T> _inTurn<T>(Future<T> Function() step) {
    final done = _writes.then((_) => step());
    _writes = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> writingEnds() async {
    while (true) {
      if (_copiesBeingMade.isNotEmpty) {
        await Future.wait(_copiesBeingMade.values);
        continue;
      }
      final writes = _writes;
      await writes;
      if (identical(writes, _writes) && _copiesBeingMade.isEmpty) return;
    }
  }

  /// The [recordings] whose copy a row of the Outbox holds, once every keep in flight has
  /// written its row or failed to.
  Future<Set<String>> recordingsItHolds(Iterable<String> recordings) async {
    await Future.wait(_copiesBeingMade.values);
    final rows = await entries();
    return {
      for (final recording in recordings)
        if (rows.any(
          (row) =>
              p.basenameWithoutExtension(row.path) ==
              '${row.kind}-${p.basenameWithoutExtension(recording)}-${row.id}',
        ))
          recording,
    };
  }

  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async => (await _enqueue(
    audio,
    sessionId: sessionId,
    passage: passage,
    kind: kind,
    scope: scope,
    passNumber: passNumber,
    chunkIndex: chunkIndex,
    scene: scene,
    recordedAt: await audio.lastModified(),
  ))!;

  /// A row of a join: the rehearsal's own bytes as the part, written only when the copy
  /// is [fingerprint]'s, naming [overTake], the part's take it replaces. Each try sends
  /// the moment it is made as its Recording time.
  Future<PendingTake?> enqueueTheJoin(
    File audio, {
    required String sessionId,
    String? passage,
    required int number,
    required int passNumber,
    required String origin,
    String? fingerprint,
    String? overTake,
    bool reopensTheApprovedDraft = false,
  }) => _enqueue(
    audio,
    sessionId: sessionId,
    passage: passage,
    kind: 'ensaio',
    scope: KeptScope.parte(number),
    passNumber: passNumber,
    chunkIndex: number,
    recordedAt: _now(),
    fingerprint: fingerprint,
    origin: origin,
    reopensTheApprovedDraft: reopensTheApprovedDraft,
    overTake: overTake,
  );

  Future<PendingTake?> _enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    required DateTime recordedAt,
    int? passNumber,
    int? chunkIndex,
    String? scene,
    String? fingerprint,
    String? origin,
    bool reopensTheApprovedDraft = false,
    String? overTake,
  }) async {
    final dir = await _dir();
    final id = _mintId();
    final name = p.basenameWithoutExtension(audio.path);
    final kept = p.join(dir.path, '$kind-$name-$id${p.extension(audio.path)}');
    final settled = Completer<void>();
    _copiesBeingMade[kept] = settled.future;
    try {
      if (audio.path != kept) {
        await audio.copy(kept);
      }
      final held = await _whatTheCopyHolds(kept);
      if (fingerprint != null && held.sha256 != fingerprint) {
        await File(kept).delete();
        return null;
      }
      final entry = PendingTake(
        id: id,
        path: kept,
        sessionId: sessionId,
        passage: passage,
        kind: kind,
        scope: scope,
        passNumber: passNumber,
        chunkIndex: chunkIndex,
        scene: scene,
        original: kind == sceneTakeKind ? name : null,
        recordedAt: recordedAt,
        durationMs: held.durationMs,
        sha256: held.sha256,
        origin: origin,
        reopensTheApprovedDraft: reopensTheApprovedDraft,
        overTake: overTake,
      );
      final gone = kind == partTakeKind
          ? await _goneRowsOf(sessionId, scope)
          : const <String>{};
      await _mutate(
        (written) => _lifeEnded
            ? written
            : [
                for (final row in written)
                  if (!gone.contains(row.id)) row,
                entry,
              ],
      );
      if (_lifeEnded) {
        await _deleteTheCopy(entry);
        if (await audio.exists()) await audio.delete();
        throw const TheLifeEnded();
      }
      tapped(entry.id);
      return entry;
    } finally {
      _copiesBeingMade.remove(kept);
      settled.complete();
    }
  }

  final StreamController<void> _falls = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get fallsOnTheNetwork => _falls.stream;

  void _fellOnTheNetwork() => _falls.add(null);

  final StreamController<String> _sessionsGone =
      StreamController<String>.broadcast(sync: true);

  Stream<String> get sessionsGone => _sessionsGone.stream;

  PendingTake? _inTheAir;

  final StreamController<TakeLeaving?> _leaving =
      StreamController<TakeLeaving?>.broadcast(sync: true);

  Stream<TakeLeaving?> get leaving => _leaving.stream;

  Completer<void>? _stop;

  final StreamController<String> _rowsLeaving =
      StreamController<String>.broadcast(sync: true);

  /// Each row's id as its own request goes out to the room.
  Stream<String> get rowsLeaving => _rowsLeaving.stream;

  final StreamController<String> _rowsBack = StreamController<String>.broadcast(
    sync: true,
  );

  /// Each row's id once the room's answer to its request is written down.
  Stream<String> get rowsBack => _rowsBack.stream;

  bool inTheAir(String row) => _inTheAir?.id == row;

  final Set<String> _moved = {};

  /// Whether the room turned this join row away because the part's take was another by
  /// then; the row left the Outbox with its copy.
  bool movedAway(String row) => _moved.contains(row);

  /// The room turned the tablet away, not the take: nothing more leaves until it is
  /// linked again, and nothing is given up for it.
  bool _turnedAway = false;

  bool _stopped = false;

  void stop(String row) {
    final stop = _stop;
    if (stop == null || stop.isCompleted || _inTheAir?.id != row) return;
    _stopped = true;
    stop.complete();
  }

  /// Send the rows a tap of this life made due, each with the rest of its part and after
  /// them every take no row can show, since no tap of its own can reach it; and every row
  /// a caller that only asked while this call was already running would otherwise miss.
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

  /// The recordings of one part leave in the order the team made them.
  ///
  /// A part recorded again is a second row under the scope the part already has, and the
  /// room decides which of two recordings under one number is the part by the tablet's
  /// own count and then by arrival, so a tap on one row of a part sends the whole part in
  /// its order. A row skipped here — audio gone, refused, unanswered — used to let the
  /// one behind it go, so a retry landing after the
  /// re-recording left the room holding the recording the team abandoned. A row that does
  /// not land holds the rest of its part for the rest of this pass; a row refused for good
  /// holds nothing, and a telling-back is not a part.
  Future<int> _flushOnce() async {
    _turnedAway = false;
    _stopped = false;
    final List<PendingTake> rows;
    try {
      await _sweepTheOldBackTranslations();
      final waiting = await this.waiting();
      final tappedParts = {
        for (final entry in waiting)
          if (_dueOnATap.containsKey(entry.id)) _partOf(entry) ?? entry.id,
      };
      rows = tappedParts.isEmpty
          ? const []
          : [
              for (final entry in waiting)
                if (tappedParts.contains(_partOf(entry) ?? entry.id) ||
                    !_aRowOffersItsTap(entry))
                  entry,
            ];
    } on PathNotFoundException {
      return 0;
    }
    final taps = {for (final entry in rows) entry.id: _dueOnATap[entry.id]};
    try {
      return await _sendEach(rows);
    } finally {
      for (final MapEntry(key: row, value: tap) in taps.entries) {
        if (_dueOnATap[row] == tap) _dueOnATap.remove(row);
      }
    }
  }

  Future<int> _sendEach(List<PendingTake> rows) async {
    var sent = 0;
    final held = <String>{};
    final leftInThisPass = <String, DateTime>{};
    for (final entry in rows) {
      if (_turnedAway || _stopped) break;
      final part = _partOf(entry);
      if (part != null && held.contains(part)) continue;
      switch (await _landed(entry, leftInThisPass)) {
        case _Landing.landed:
          sent++;
        case _Landing.held when part != null:
          held.add(part);
        case _Landing.held || _Landing.givenUp:
          break;
      }
    }
    return sent;
  }

  /// Whether the room took this row. Held is every reason it did not that holds the rest
  /// of this row's part on it; a row refused for good, sent or not, holds nothing.
  Future<_Landing> _landed(
    PendingTake entry,
    Map<String, DateTime> leftInThisPass,
  ) async {
    var left = false;
    void leaving() {
      left = true;
      _rowsLeaving.add(entry.id);
    }

    try {
      return await _landedOnce(entry, leftInThisPass, leaving);
    } finally {
      if (left) _rowsBack.add(entry.id);
    }
  }

  Future<_Landing> _landedOnce(
    PendingTake entry,
    Map<String, DateTime> leftInThisPass,
    void Function() leaving,
  ) async {
    final sessionId = entry.sessionId;
    if (sessionId == null) return _Landing.givenUp;
    final file = File(entry.path);
    if (!await file.exists()) {
      if (!await _betweenWrites((written) => _holds(written, entry))) {
        return _Landing.givenUp;
      }
      // Already written off and gone again between the check above and here: the row
      // is already saying so, and rewriting the manifest to say it twice is a write
      // for no change of state.
      if (!entry.lost) await _replace(entry, entry.copyWith(lost: true));
      return _Landing.held;
    }
    var sent = entry;
    try {
      if (await file.length() > largestTakeTheRoomKeeps) {
        await _settleWith(
          entry,
          (now) => now.copyWith(
            lost: false,
            attempts: takeUploadAttempts,
            lastTry: _now(),
            refusal: RefusalCode.tooLarge,
          ),
        );
        return _Landing.givenUp;
      }
      if (!await _claim(entry)) return _Landing.givenUp;
      final stop = _stop = Completer<void>();
      _leaving.add((
        take: entry,
        since: switch (_partOf(entry)) {
          final part? => leftInThisPass.putIfAbsent(part, _now),
          null => _now(),
        },
      ));
      leaving();
      var fell = false;
      for (var attempt = 0; ; attempt++) {
        final answer = await _attempt(entry, sessionId, file, stop.future);
        switch (answer) {
          case Answered(value: final landed):
            await _confirm(entry, landed);
            return _Landing.landed;
          case Refused(code: RefusalCode.takeMoved):
            _moved.add(entry.id);
            await withdraw(entry);
            await _deleteTheCopy(entry);
            return _Landing.givenUp;
          case Refused(
            code: RefusalCode.deviceRevoked || RefusalCode.unauthorized,
          ):
            _turnedAway = true;
            await _settleWith(
              sent,
              (now) => now.copyWith(
                lost: false,
                waits: now.waits + 1,
                lastTry: _now(),
              ),
            );
            return _Landing.held;
          case Refused(:final code):
            await _settleWith(
              sent,
              (now) => now.copyWith(
                lost: false,
                attempts: takeUploadAttempts,
                lastTry: _now(),
                refusal: code,
              ),
            );
            return _Landing.givenUp;
          case SessionGone():
            await letGoOfTheSession(sessionId);
            _sessionsGone.add(sessionId);
            return _Landing.held;
          case NetworkFailed() when entry.origin != null:
            if (_stopped) return await _theTeamStopped(sent);
            _fellOnTheNetwork();
            await _settleWith(
              sent,
              (now) => now.copyWith(
                lost: false,
                waits: now.waits + 1,
                lastTry: _now(),
              ),
            );
            return _Landing.held;
          case NetworkFailed(:final reason):
            if (_stopped) return await _theTeamStopped(sent);
            fell = fell || reason != _notListed;
            final now = await _settleWith(
              sent,
              (now) => now.copyWith(
                lost: false,
                attempts: now.attempts + 1,
                lastTry: _now(),
              ),
            );
            if (now == null || now.exhausted) {
              if (fell) _fellOnTheNetwork();
              return _Landing.held;
            }
            sent = now;
            await Future.any([_pauseAfter(attempt), stop.future]);
            if (_stopped) return await _theTeamStopped(sent);
        }
      }
    } on FileSystemException {
      await _settleWith(
        sent,
        (now) => now.copyWith(
          lost: false,
          attempts: now.attempts + 1,
          lastTry: _now(),
        ),
      );
      return _Landing.held;
    } finally {
      _inTheAir = null;
      _stop = null;
      _leaving.add(null);
    }
  }

  static const _notListed = 'not listed';

  Future<void> _pauseAfter(int attempt) => _spacing.isEmpty
      ? Future<void>.value()
      : Future<void>.delayed(
          _spacing[attempt < _spacing.length ? attempt : _spacing.length - 1],
        );

  Future<_Landing> _theTeamStopped(PendingTake entry) async {
    await _settleWith(
      entry,
      (now) => now.copyWith(
        lost: false,
        attempts: takeUploadAttempts,
        lastTry: _now(),
      ),
    );
    return _Landing.held;
  }

  Future<RoomAnswer<String>> _attempt(
    PendingTake entry,
    String sessionId,
    File file,
    Future<void> stop,
  ) async {
    if (entry.kind == sceneTakeKind) {
      final kept = await _unlessStopped(
        _room.keepSceneRehearsal(
          sessionId,
          file,
          scene: entry.scene,
          recordedAt: entry.recordedAt,
          durationMs: entry.durationMs,
          sha256: entry.sha256,
          abortTrigger: stop,
        ),
        stop,
      );
      final SceneRehearsalRecord record;
      switch (kept) {
        case Answered(:final value):
          record = value;
        case final RoomFailure failure:
          return failure;
      }
      final listed = await _unlessStopped(
        _room.sceneRehearsalsOf(sessionId),
        stop,
      );
      switch (listed) {
        case Answered(:final value)
            when value.any((held) => held.rehearsalId == record.rehearsalId):
          _keptScenes[entry.id] = record;
          await _nameTheTake(entry.original, 'cena-${record.rehearsalId}');
          return Answered(record.rehearsalId);
        case Answered():
          return const NetworkFailed(_notListed);
        case final RoomFailure failure:
          return failure;
      }
    }
    final sent = await _unlessStopped(
      _room.sendTake(
        sessionId,
        file,
        kind: entry.kind,
        scope: entry.scope,
        passNumber: entry.passNumber,
        chunkIndex: entry.chunkIndex,
        recordedAt: entry.origin == null ? entry.recordedAt : _now(),
        durationMs: entry.durationMs,
        sha256: entry.sha256,
        origin: entry.origin,
        reopensTheApprovedDraft: entry.reopensTheApprovedDraft,
        overTake: entry.overTake,
        abortTrigger: stop,
      ),
      stop,
    );
    final String takeId;
    switch (sent) {
      case Answered(:final value):
        takeId = value;
      case final RoomFailure failure:
        return failure;
    }
    final listed = await _unlessStopped(_room.takesOf(sessionId), stop);
    switch (listed) {
      case Answered(:final value)
          when value.any((held) => held.takeId == takeId):
        return Answered(takeId);
      case Answered():
        return const NetworkFailed(_notListed);
      case final RoomFailure failure:
        return failure;
    }
  }

  static Future<RoomAnswer<T>> _unlessStopped<T>(
    Future<RoomAnswer<T>> call,
    Future<void> stop,
  ) => Future.any([
    call,
    stop.then<RoomAnswer<T>>((_) => const NetworkFailed('stopped')),
  ]);

  Future<PendingTake?> _settleWith(
    PendingTake sent,
    PendingTake Function(PendingTake now) outcome,
  ) async {
    PendingTake? settled;
    await _mutate((written) {
      final next = <PendingTake>[];
      for (final now in written) {
        if (!_sameRow(now, sent)) {
          next.add(now);
          continue;
        }
        settled = _madeDueInTheAir(sent, now)
            ? now.copyWith(lost: false)
            : outcome(now);
        next.add(settled!);
      }
      return next;
    });
    if (settled == null) await _deleteTheCopy(sent);
    return settled;
  }

  static bool _madeDueInTheAir(PendingTake sent, PendingTake now) =>
      now.tries < sent.tries || (sent.lastTry != null && now.lastTry == null);

  Future<void> _nameTheTake(String? original, String name) async {
    if (original == null) return;
    final recordings = _recordings();
    try {
      final held = await recordings.heldAs(original);
      if (held != null) await recordings.keepAs(held, name);
    } on Object {
      return;
    }
  }

  Future<void> _confirm(PendingTake entry, String takeId) async {
    _confirmed[entry.id] = takeId;
    _landedRows.add(entry.copyWith(takeId: takeId));
    final gone = entry.kind == partTakeKind
        ? await _goneRowsOf(
            entry.sessionId,
            entry.scope,
            upToPass: entry.passNumber ?? 1,
          )
        : const <String>{};
    await _mutate(
      (written) => [
        for (final row in written)
          if (!_sameRow(row, entry) && !gone.contains(row.id)) row,
      ],
    );
    await _deleteTheCopy(entry);
  }

  /// [read] over the manifest as written, in a step of its own between writes.
  Future<T> _betweenWrites<T>(T Function(List<PendingTake> written) read) =>
      _inTurn(() async => read(await _written() ?? const []));

  static bool _holds(List<PendingTake> written, PendingTake entry) =>
      written.any((row) => _sameRow(row, entry));

  /// The row goes up only while the manifest still holds it, and it is in the air from
  /// the same step: a withdraw runs wholly before the send or wholly after it.
  Future<bool> _claim(PendingTake entry) => _betweenWrites((written) {
    final held = _holds(written, entry);
    if (held) _inTheAir = entry;
    return held;
  });

  static bool _sameRow(PendingTake a, PendingTake b) =>
      a.id == b.id && a.kind == b.kind;

  bool _isInTheAir(PendingTake entry) {
    final inTheAir = _inTheAir;
    return inTheAir != null && _sameRow(entry, inTheAir);
  }

  Future<bool> _replace(PendingTake target, PendingTake updated) async {
    var found = false;
    await _mutate((written) {
      found = written.any((entry) => _sameRow(entry, target));
      return [
        for (final entry in written) _sameRow(entry, target) ? updated : entry,
      ];
    });
    return found;
  }

  /// A Back-translation stretch is never queued: one an older build left is a stale
  /// translation, and it leaves with its copy before anything is sent.
  Future<void> _sweepTheOldBackTranslations() async {
    final old = [
      for (final entry in await _written() ?? const <PendingTake>[])
        if (entry.kind == _theBackTranslationsOldKind) entry,
    ];
    if (old.isEmpty) return;
    for (final entry in old) {
      await _deleteTheCopy(entry);
    }
    await _mutate(
      (written) => [
        for (final entry in written)
          if (entry.kind != _theBackTranslationsOldKind) entry,
      ],
    );
  }

  Future<void> _deleteTheCopy(PendingTake entry) async {
    try {
      await File(entry.path).delete();
    } on FileSystemException {
      return;
    }
  }

  Future<SceneRehearsalRecord?> keepTheScene(
    String row, {
    String? intoTheSession,
  }) async {
    await _mutate((written) {
      final at = written.indexWhere((entry) => entry.id == row);
      final kept = [
        for (var i = 0; i < written.length; i++)
          i == at ||
                  i < at &&
                      written[i].kind == sceneTakeKind &&
                      written[i].sessionId == written[at].sessionId &&
                      (written[i].sessionId != null ||
                          written[i].passage == written[at].passage) &&
                      written[i].refusal == null
              ? switch (written[i].dueNow()) {
                  final due when due.sessionId == null => due.inTheSession(
                    intoTheSession,
                  ),
                  final due => due,
                }
              : written[i],
      ];
      for (var i = 0; i < kept.length; i++) {
        if (!identical(kept[i], written[i])) tapped(kept[i].id);
      }
      return kept;
    });
    await flush();
    return keptSceneOf(row);
  }

  SceneRehearsalRecord? keptSceneOf(String row) => _keptScenes[row];

  /// [row] goes up on the next flush, with its attempts given back; a row whose session
  /// is gone goes into [intoTheSession], the session of its passage now.
  Future<void> dueAgain(String row, {String? intoTheSession}) {
    tapped(row);
    return _mutate(
      (written) => [
        for (final entry in written)
          if (entry.id != row)
            entry
          else if (entry.sessionId == null)
            entry.dueNow().inTheSession(intoTheSession)
          else
            entry.dueNow(),
      ],
    );
  }

  /// [row] goes up on the next flush, as its own tap asked.
  void tapped(String row) => _dueOnATap[row] = ++_taps;

  Future<PendingTake?> sceneWaitingIn(
    String sessionId, {
    String? passage,
  }) async {
    PendingTake? newest;
    for (final entry in await pending()) {
      if (entry.kind == sceneTakeKind &&
          _ofTheVisit(entry, sessionId, passage) &&
          entry.refusal == null &&
          !await _reallyGone(entry)) {
        newest = entry;
      }
    }
    return newest;
  }

  Future<PendingTake?> sentenceHeldIn(
    String sessionId, {
    String? passage,
  }) async {
    PendingTake? newest;
    for (final entry in await _inTurn(pending)) {
      if (entry.kind == sentenceKind &&
          _ofTheVisit(entry, sessionId, passage)) {
        newest = entry;
      }
    }
    return newest;
  }

  /// The room no longer knows [sessionId]: its rows stay on the tablet with their copies,
  /// under [passage] when they carry none, for the passage's next session to send. A row
  /// whose passage is known nowhere keeps its session, so a later call that knows the
  /// passage still finds it.
  Future<void> letGoOfTheSession(String sessionId, {String? passage}) =>
      _mutate(
        (written) => [
          for (final entry in written)
            switch (entry.passage ?? passage) {
              final known? when entry.sessionId == sessionId =>
                entry.inTheSession(null, passage: known),
              _ => entry,
            },
        ],
      );

  /// Take every join row of [scope] off the manifest, even one whose request is in the
  /// air: the team recorded the part again by hand. A row at rest goes with its copy; a
  /// request in the air keeps its copy until its answer deletes it. With [passage], a
  /// join row the gone session already left under its passage goes too.
  Future<void> withdrawTheJoinsOf(
    String sessionId,
    String scope, {
    String? passage,
  }) async {
    final removed = <PendingTake>[];
    await _mutate((written) {
      final kept = <PendingTake>[];
      for (final entry in written) {
        if (!entry.stored &&
            entry.origin != null &&
            _ofTheVisit(entry, sessionId, passage) &&
            entry.scope == scope) {
          if (!_isInTheAir(entry)) removed.add(entry);
          continue;
        }
        kept.add(entry);
      }
      return kept;
    });
    for (final entry in removed) {
      await _deleteTheCopy(entry);
    }
  }

  /// Take a pending row off the manifest before it can ever be delivered, and delete
  /// the copy `enqueue` made of it.
  ///
  /// A no-op for a row already stored or one the queue no longer holds — the caller
  /// discards a recording whether or not a guard ever queued it, and asking should
  /// never be an error either way. Matched by id and kind, the same pair `_replace`
  /// reads a row by.
  Future<void> withdraw(PendingTake row) async {
    await _takeOff(row, keepsItsCopy: () => false);
  }

  /// Take [row] off the manifest even while its request is in the air, decided in the
  /// same step a pass claims a row: no later pass, here or after a relaunch, sends it
  /// again. A request in the air keeps the copy, and its answer deletes it; true when
  /// it was in the air.
  Future<bool> withdrawEvenInTheAir(PendingTake row) =>
      _takeOff(row, keepsItsCopy: () => _isInTheAir(row));

  /// [row] off the manifest in one manifest step, with its copy unless [keepsItsCopy]
  /// says otherwise inside that step; whether it kept the copy.
  Future<bool> _takeOff(
    PendingTake row, {
    required bool Function() keepsItsCopy,
  }) async {
    PendingTake? removed;
    var kept = false;
    await _mutate((written) {
      kept = keepsItsCopy();
      removed = written.where((entry) => _isTheRow(entry, row)).firstOrNull;
      return [
        for (final entry in written)
          if (!_isTheRow(entry, row)) entry,
      ];
    });
    if (removed case final entry? when !kept) await _deleteTheCopy(entry);
    return kept;
  }

  static bool _isTheRow(PendingTake entry, PendingTake row) =>
      !entry.stored && _sameRow(entry, row);
}

final takeUploadQueueProvider = Provider<TakeUploadQueue>(
  (ref) => TakeUploadQueue(
    room: ref.read(roomRepositoryProvider),
    spacing: ref.read(takeAttemptSpacingProvider),
    recordings: () => ref.read(recordingRepositoryProvider),
  ),
);

enum _Landing { landed, held, givenUp }
