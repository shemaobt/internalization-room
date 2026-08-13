import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'room_repository.dart';

const _folder = 'guardadas';
const _manifest = 'fila.json';

const takeUploadAttempts = 5;

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
  final int attempts;
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
    this.attempts = 0,
    this.lastTry,
  });

  bool get exhausted => attempts >= takeUploadAttempts;

  PendingTake copyWith({bool? stored, int? attempts, DateTime? lastTry}) => PendingTake(
        id: id,
        path: path,
        sessionId: sessionId,
        kind: kind,
        scope: scope,
        passNumber: passNumber,
        chunkIndex: chunkIndex,
        stored: stored ?? this.stored,
        attempts: attempts ?? this.attempts,
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
        'attempts': attempts,
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
        attempts: json['attempts'] as int? ?? 0,
        lastTry: DateTime.tryParse(json['last_try'] as String? ?? ''),
      );
}

class TakeUploadQueue {
  final RoomRepository _room;
  final Future<Directory> Function() _home;
  final List<Duration> _backoff;
  final DateTime Function() _now;
  bool _flushing = false;

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

  Future<List<PendingTake>> entries() async {
    final file = await _manifestFile();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return [
        for (final entry in raw) PendingTake.fromJson(entry as Map<String, Object?>),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<List<PendingTake>> pending() async =>
      [for (final entry in await entries()) if (!entry.stored) entry];

  Future<List<PendingTake>> waiting() async =>
      [for (final entry in await pending()) if (!entry.exhausted) entry];

  Future<int> unsentOf(String kind, {required String sessionId}) async => [
        for (final entry in await pending())
          if (entry.kind == kind && entry.sessionId == sessionId) entry,
      ].length;

  Future<List<PendingTake>> giveUps() async =>
      [for (final entry in await pending()) if (entry.exhausted) entry];

  bool _ready(PendingTake entry) {
    final last = entry.lastTry;
    if (last == null || entry.attempts == 0 || _backoff.isEmpty) return true;
    final step = entry.attempts - 1;
    final wait = _backoff[step < _backoff.length ? step : _backoff.length - 1];
    return !_now().isBefore(last.add(wait));
  }

  Future<void> _write(List<PendingTake> entries) async {
    final file = await _manifestFile();
    final staging = File('${file.path}.novo');
    await staging.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
    await staging.rename(file.path);
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
    await _write([...await entries(), entry]);
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
          await _replace(entry, entry.copyWith(stored: true));
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

  Future<void> _replace(PendingTake target, PendingTake updated) async {
    await _write([
      for (final entry in await entries())
        if (entry.id == target.id && entry.kind == target.kind) updated else entry,
    ]);
  }
}

final takeUploadQueueProvider = Provider<TakeUploadQueue>(
  (ref) => TakeUploadQueue(
    room: ref.read(roomRepositoryProvider),
    backoff: ref.read(takeRetryBackoffProvider),
  ),
);
