import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _lines = {'voice:line', 'voice:fixed', 'voice:asset'};

Uint8List _wavOf(
  int samples, {
  bool chunkBeforeData = false,
  int padding = 0,
}) => aWavTake(
  samples: List.filled(samples, 4000),
  chunkBeforeData: chunkBeforeData,
  paddingBeforeData: padding,
);

Future<void> _recordTheScene(SceneRoom room, Uint8List take) async {
  room.harness.recorder.rehearsalSpeaks = take;
  await theScreenOpens(room);
  await theSceneMicrophoneOpens(room);
  room.sala.sceneTap();
  await waitFor(
    'o microfone da cena fechar',
    () => room.state.channel is! Microphone,
  );
  await settle();
}

void _expectNothingLeftBehind(
  SceneRoom room, {
  required int soundsBefore,
  required int personsBefore,
}) {
  expect(
    room.asked('keepSceneRehearsal'),
    0,
    reason: 'um toque acidental não vira ensaio da cena',
  );
  expect(room.state.scene.step, SceneStep.record);
  expect(room.state.channel, isNot(isA<Microphone>()));
  expect(
    room.harness.sounds.skip(soundsBefore).where(_lines.contains),
    isEmpty,
    reason: 'nada é falado por um dedo que roçou o círculo',
  );
  expect(room.harness.room.personsAsked, personsBefore);
  expect(room.state.needsPerson, isFalse);
}

void main() {
  test('a finger brushing the circle for 0.2 s leaves nothing: no rehearsal is '
      'kept, no line is spoken, no person is called', () async {
    final room = await atRest();
    final soundsBefore = room.harness.sounds.length;
    final personsBefore = room.harness.room.personsAsked;

    await _recordTheScene(room, _wavOf(3200));

    _expectNothingLeftBehind(
      room,
      soundsBefore: soundsBefore,
      personsBefore: personsBefore,
    );
  });

  test(
    'a scene take the recorder handed back no take for leaves nothing',
    () async {
      final room = await atRest();
      final soundsBefore = room.harness.sounds.length;
      final personsBefore = room.harness.room.personsAsked;
      room.harness.recorder.returnsNothing = true;
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await waitFor(
        'o microfone da cena fechar',
        () => room.state.channel is! Microphone,
      );
      await settle();

      _expectNothingLeftBehind(
        room,
        soundsBefore: soundsBefore,
        personsBefore: personsBefore,
      );
    },
  );

  test('a scene take of 0.3 s is kept', () async {
    final room = await atRest();

    await _recordTheScene(room, _wavOf(4800));
    await waitFor(
      'o ensaio ser guardado',
      () => room.asked('keepSceneRehearsal') > 0,
    );

    expect(room.asked('keepSceneRehearsal'), 1);
  });

  test(
    'a WAV whose header is longer than 44 bytes is measured by its audio, not '
    'its size',
    () async {
      final room = await atRest();
      final take = _wavOf(3200, chunkBeforeData: true, padding: 4096);
      expect(take.length, greaterThan(44 + 16000 * 2 * 3 ~/ 10));
      final soundsBefore = room.harness.sounds.length;
      final personsBefore = room.harness.room.personsAsked;

      await _recordTheScene(room, take);

      _expectNothingLeftBehind(
        room,
        soundsBefore: soundsBefore,
        personsBefore: personsBefore,
      );
    },
  );

  test(
    'a WAV whose header was never finished is measured by its length',
    () async {
      final room = await atRest();
      final unfinished = Uint8List.fromList([
        ...List.filled(44, 0),
        ..._wavOf(16000).skip(44),
      ]);

      room.harness.recorder.rehearsalSpeaksAs = 'wav';
      await _recordTheScene(room, unfinished);
      await waitFor(
        'o ensaio ser guardado',
        () => room.asked('keepSceneRehearsal') > 0,
      );

      expect(
        room.harness.recorder.deleted,
        isEmpty,
        reason:
            'um gravador que falhou ao fechar o cabeçalho deixa o áudio inteiro '
            'atrás dele, e apagá-lo como toque perdia a fala da equipe',
      );
    },
  );

  group('a compressed scene take under 800 bytes is an accidental tap, and one '
      'of 800 bytes is kept', () {
    test('799 bytes are dropped', () async {
      final room = await atRest();
      final soundsBefore = room.harness.sounds.length;
      final personsBefore = room.harness.room.personsAsked;

      await _recordTheScene(room, Uint8List(799));

      _expectNothingLeftBehind(
        room,
        soundsBefore: soundsBefore,
        personsBefore: personsBefore,
      );
    });

    test('800 bytes are kept', () async {
      final room = await atRest();

      await _recordTheScene(room, Uint8List(800));
      await waitFor(
        'o ensaio ser guardado',
        () => room.asked('keepSceneRehearsal') > 0,
      );

      expect(room.asked('keepSceneRehearsal'), 1);
    });
  });

  test(
    'there is no maximum length: a scene microphone left open for an hour is '
    'still open',
    () {
      fakeAsync((async) {
        final harness = SalaHarness(filaEmMemoria: true);
        late SceneRoom room;
        unawaited(atRest(harness).then((opened) => room = opened));
        async.elapse(const Duration(seconds: 2));
        room.sala.openTheSceneRehearsal();
        async.elapse(const Duration(seconds: 1));
        room.sala.sceneTap();
        async.elapse(const Duration(seconds: 1));
        expect(room.state.channel, isA<Microphone>());

        async.elapse(const Duration(minutes: 60));

        expect(
          switch (room.state.channel) {
            Microphone(owner: MicOwner.scene) => true,
            _ => false,
          },
          isTrue,
          reason: 'a cena não tem tempo máximo; só o toque da equipe fecha',
        );
        expect(
          room.asked('keepSceneRehearsal'),
          0,
          reason: 'nada fechou o microfone sozinho',
        );

        room.sala.sceneTap();
        async.elapse(const Duration(seconds: 2));
        expect(room.asked('keepSceneRehearsal'), 1);
        room.container.dispose();
      });
    },
  );
}
