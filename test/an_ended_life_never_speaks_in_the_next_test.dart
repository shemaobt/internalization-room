import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
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
  Duration takesToCopy = Duration.zero;

  void holdTheNextTake() => _armed = _room;

  void theDiskIsFull() => _room.complete(false);

  void theDiskTakesIt() => _room.complete(true);

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
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
      await Future<void>.delayed(takesToCopy);
    }
    return super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }
}

SalaHarness _aRoomWith(
  void Function(_AnOutboxHeldAsTheRoomCloses queue) handed,
) => SalaHarness(
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

void main() {
  test(
    'a rehearsal take of an ended life that cannot be queued is not shown as '
    'failed in the next',
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

      await container.read(salaSessionProvider.notifier).refreshUnsent();
      await settle();

      expect(
        container.read(salaSessionProvider).unsentParts,
        isEmpty,
        reason: 'a tomada era da sala de antes do desvínculo',
      );
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
    queue.takesToCopy = const Duration(milliseconds: 400);
    queue.holdTheNextTake();
    await theSceneMicrophoneOpens(room);
    room.sala.sceneTap();
    await waitFor('a Fila segurar o take', () => queue.holding);

    room.container.invalidate(salaSessionProvider);
    room.container.read(salaSessionProvider);
    queue.theDiskTakesIt();
    await waitFor(
      'a sala guardar o take da Fila',
      () => room.harness.room.scenesKept.isNotEmpty,
    );

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
