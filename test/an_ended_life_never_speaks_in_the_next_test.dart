import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

class _AnOutboxHeldAsTheRoomCloses extends TakeUploadQueue {
  _AnOutboxHeldAsTheRoomCloses({
    required super.room,
    super.home,
    required super.recordings,
  });

  Completer<bool>? _armed;
  final _room = Completer<bool>();
  bool holding = false;
  bool stranded = false;

  void holdTheNextTake() => _armed = _room;

  void theDiskIsFull() => _room.complete(false);

  void theDiskTakesIt() => _room.complete(true);

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    if (_armed case final held?) {
      _armed = null;
      holding = true;
      if (!await held.future) throw const FileSystemException('disco cheio');
    }
    return super.enqueue(
      audio,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }

  @override
  Future<OutboxTally> tally({required String? sessionId}) async {
    final counted = await super.tally(sessionId: sessionId);
    return (
      stranded: stranded,
      unsentTakes: counted.unsentTakes,
      unsentChunks: counted.unsentChunks,
      unsentTakeScopes: counted.unsentTakeScopes,
      parts: counted.parts,
      due: counted.due,
    );
  }
}

class _ADiskThatFillsAsTheRoomCloses extends FakeWorkInProgress {
  final _full = Completer<void>();
  bool holding = false;

  void theDiskIsFull() => _full.complete();

  @override
  Future<void> remember(
    String book,
    String pericope,
    String language,
    ResumePoint point,
  ) async {
    holding = true;
    await _full.future;
    throw const FileSystemException('disco cheio');
  }
}

SalaHarness _aRoomWith(
  void Function(_AnOutboxHeldAsTheRoomCloses queue) handed, {
  WorkInProgress? disk,
}) => SalaHarness(
  emAbertoNoDisco: disk,
  takesOverride: (room, home, recordings) {
    final queue = _AnOutboxHeldAsTheRoomCloses(
      room: room,
      home: () async => home,
      recordings: recordings,
    );
    handed(queue);
    return queue;
  },
);

int _strandedSaid(SalaHarness harness) => harness.voice.assets
    .where((asset) => asset == strandedTakeAsset(testLanguage))
    .length;

Future<void> _theNewLifeCountsAStrandedTake(
  ProviderContainer container,
  _AnOutboxHeldAsTheRoomCloses queue,
) async {
  queue.stranded = true;
  await container.read(salaSessionProvider.notifier).refreshUnsent();
  await settle();
}

void main() {
  test('a scene take of an ended life that cannot be kept says nothing in the '
      'next, and the next says its own stranded line', () async {
    late _AnOutboxHeldAsTheRoomCloses queue;
    final room = await atRest(_aRoomWith((handed) => queue = handed));
    await theScreenOpens(room);
    queue.stranded = true;
    await room.sala.refreshUnsent();
    await settle();
    queue.stranded = false;
    expect(_strandedSaid(room.harness), 1);
    room.harness.recorder.rehearsalSpeaks = Uint8List.fromList([
      for (var i = 0; i < 1200; i++) (i * 7) % 251,
    ]);
    queue.holdTheNextTake();
    await theSceneMicrophoneOpens(room);
    room.sala.sceneTap();
    await waitFor('a Fila segurar o take', () => queue.holding);

    room.container.invalidate(salaSessionProvider);
    room.container.read(salaSessionProvider);
    queue.theDiskIsFull();
    await settle();

    expect(
      _strandedSaid(room.harness),
      1,
      reason:
          'a gravação que ficou presa era da sala de antes do desvínculo, '
          'que já tinha dito; a sala nova não fala por ela',
    );
    await _theNewLifeCountsAStrandedTake(room.container, queue);
    expect(
      _strandedSaid(room.harness),
      2,
      reason: 'a sala nova diz uma vez o que é dela',
    );
  });

  test(
    'a rehearsal take of an ended life that cannot be queued says nothing in '
    'the next, and the next says its own stranded line',
    () async {
      late _AnOutboxHeldAsTheRoomCloses queue;
      final harness = _aRoomWith((handed) => queue = handed);
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      await sala.goConversa(book: 'Ruth');
      await settle();
      sala.goEnsaio();
      sala.ensaioTap();
      sala.ensaioTap();
      await waitFor(
        'a tomada ser oferecida',
        () =>
            container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
      );
      queue.holdTheNextTake();
      sala.takeKeep();
      await waitFor('a Fila segurar a tomada', () => queue.holding);

      container.invalidate(salaSessionProvider);
      container.read(salaSessionProvider);
      queue.theDiskIsFull();
      await settle();

      expect(
        _strandedSaid(harness),
        0,
        reason: 'a tomada era da sala de antes do desvínculo',
      );
      await _theNewLifeCountsAStrandedTake(container, queue);
      expect(_strandedSaid(harness), 1);
    },
  );

  test(
    'a place of an ended life the disk refuses says nothing in the next, and '
    'the next says its own stranded line',
    () async {
      late _AnOutboxHeldAsTheRoomCloses queue;
      final disk = _ADiskThatFillsAsTheRoomCloses();
      final harness = _aRoomWith((handed) => queue = handed, disk: disk);
      final container = harness.container();
      addTearDown(container.dispose);
      unawaited(
        container
            .read(salaSessionProvider.notifier)
            .goConversa(book: 'Ruth', pericope: 'P01'),
      );
      await waitFor('o disco segurar o lugar', () => disk.holding);

      container.invalidate(salaSessionProvider);
      container.read(salaSessionProvider);
      disk.theDiskIsFull();
      await settle();

      expect(
        _strandedSaid(harness),
        0,
        reason: 'o lugar era da equipe de antes do desvínculo',
      );
      await _theNewLifeCountsAStrandedTake(container, queue);
      expect(_strandedSaid(harness), 1);
    },
  );

  test('a scene take of an ended life the Outbox queues still goes up to '
      'the room', () async {
    late _AnOutboxHeldAsTheRoomCloses queue;
    final room = await atRest(_aRoomWith((handed) => queue = handed));
    await theScreenOpens(room);
    room.harness.recorder.rehearsalSpeaks = Uint8List.fromList([
      for (var i = 0; i < 1200; i++) (i * 7) % 251,
    ]);
    queue.holdTheNextTake();
    await theSceneMicrophoneOpens(room);
    room.sala.sceneTap();
    await waitFor('a Fila segurar o take', () => queue.holding);

    room.container.invalidate(salaSessionProvider);
    room.container.read(salaSessionProvider);
    queue.theDiskTakesIt();
    await settle();

    expect(
      room.harness.room.scenesKept,
      hasLength(1),
      reason:
          'o ensaio gravado é da equipe, não da sala que acabou; guardado na '
          'Fila, ele sobe como sobe uma tomada do ensaio',
    );
    expect(room.state.scene.keep, isNull);
  });
}
