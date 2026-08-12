import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'room_repository.dart';

const _folder = 'guardadas';
const _manifest = 'fila.json';

class PendingTake {
  final String id;
  final String path;
  final String sessionId;
  final String kind;
  final String scope;
  final int? passNumber;
  final int? chunkIndex;
  final bool stored;

  const PendingTake({
    required this.id,
    required this.path,
    required this.sessionId,
    required this.kind,
    required this.scope,
    this.passNumber,
    this.chunkIndex,
    this.stored = false,
  });

  PendingTake asStored() => PendingTake(
        id: id,
        path: path,
        sessionId: sessionId,
        kind: kind,
        scope: scope,
        passNumber: passNumber,
        chunkIndex: chunkIndex,
        stored: true,
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
      );
}

class TakeUploadQueue {
  final RoomRepository _room;
  final Future<Directory> Function() _home;
  bool _flushing = false;

  TakeUploadQueue({required RoomRepository room, Future<Directory> Function()? home})
      : _room = room,
        _home = home ?? getApplicationSupportDirectory;

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
      for (final entry in await pending()) {
        final file = File(entry.path);
        if (!await file.exists()) {
          await _markStored(entry);
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
          return sent;
        }
        await _markStored(entry);
        sent++;
      }
      return sent;
    } finally {
      _flushing = false;
    }
  }

  Future<void> _markStored(PendingTake stored) async {
    await _write([
      for (final entry in await entries())
        if (entry.id == stored.id && entry.kind == stored.kind) entry.asStored() else entry,
    ]);
  }
}

final takeUploadQueueProvider = Provider<TakeUploadQueue>(
  (ref) => TakeUploadQueue(room: ref.read(roomRepositoryProvider)),
);
