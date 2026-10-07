import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _at = Duration(milliseconds: 2400);
const _of = Duration(milliseconds: 9000);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  ({String session, String turnId, Duration at, Duration? of})? get lastCut =>
      harness.room.cutsSent.last;

  Future<void> tap() async {
    notifier.conversaTap();
    await settle();
  }

  /// A take, and her reply to it held while she says it.
  Future<void> aReplySpeaking() async {
    harness.room.holdNextTurn();
    await tap();
    await tap();
    await waitFor('a vez ficar no ar', () => harness.room.turnsSent > 0);
    harness.voice.holdNextLine();
    harness.room.finishHeldTurn();
    await waitFor('a resposta falar', () => state.voice == VoiceState.speaking);
  }

  /// A take with nothing in it.
  Future<void> aGhostTake() async {
    harness.recorder.returnsEmpty = true;
    await tap();
    harness.recorder.returnsEmpty = false;
  }

  /// A take with words in it, sent and answered.
  Future<void> aRealTake() async {
    await tap();
    await tap();
  }
}

Future<_Room> _inConversa({SalaHarness? harness}) async {
  final room = harness ?? SalaHarness();
  final container = await inConversa(room);
  addTearDown(container.dispose);
  return _Room(room, container);
}

/// In the Conversation after an Opening said in two movements, so the line «Ouvir de
/// novo» holds before any turn is the Scene, never the reply's own url.
Future<_Room> _afterATwoMovementOpening() async {
  final harness = SalaHarness()..room.opensInTwoMovements = true;
  final room = await _inConversa(harness: harness);
  harness.room.opensInTwoMovements = false;
  expect(room.state.lastSpoken?.url, sceneUrl);
  return room;
}

Future<_Room> _cutWhileSheSpeaks({
  Duration at = _at,
  Duration? of = _of,
  _Room? on,
}) async {
  final room = on ?? await _inConversa();
  await room.aReplySpeaking();
  room.harness.voice
    ..linePosition = at
    ..lineLength = of;
  await room.tap();
  return room;
}

void main() {
  test('a tap while the voice speaks stops her, opens the microphone and holds '
      'where she was cut', () async {
    final room = await _inConversa();
    await room.aReplySpeaking();
    room.harness.voice
      ..linePosition = _at
      ..lineLength = _of;
    final stops = room.harness.voice.stops;
    final captures = room.harness.recorder.captures;
    final cuts = room.harness.room.cutsSent.length;

    await room.tap();

    expect(room.harness.voice.stops, greaterThan(stops));
    expect(room.state.voice, VoiceState.listening);
    expect(room.harness.recorder.captures, captures + 1);
    expect(room.harness.room.cutsSent, hasLength(cuts));
  });

  test('the team\'s next take tells the room it followed an interruption, and '
      'where', () async {
    final room = await _cutWhileSheSpeaks();

    await room.tap();
    await waitFor(
      'a vez cortada chegar à sala',
      () => room.harness.room.cutsSent.length == 2,
    );

    expect(room.lastCut, (
      session: room.state.sessionId!,
      turnId: room.harness.room.turnIdsSent.last,
      at: _at,
      of: _of,
    ));

    await waitFor('a sala voltar ao convite', () {
      return room.state.voice == VoiceState.invite;
    });
    await room.aRealTake();

    expect(room.harness.room.cutsSent, hasLength(3));
    expect(room.lastCut, isNull);
  });

  test('a cut followed by nothing kept sends nothing and the room comes back '
      'to rest', () async {
    final room = await _cutWhileSheSpeaks();
    final turns = room.harness.room.turnsSent;
    final played = [...room.harness.voice.played];
    final assets = [...room.harness.voice.assets];

    await room.aGhostTake();

    expect(room.harness.room.turnsSent, turns);
    expect(room.state.voice, VoiceState.invite);
    expect(room.harness.voice.played, played);
    expect(room.harness.voice.assets, assets);

    await room.aRealTake();

    expect(room.harness.room.turnsSent, turns + 1);
    expect(room.lastCut, isNull);
  });

  test('after a cut, «Ouvir de novo» plays the whole reply', () async {
    final room = await _cutWhileSheSpeaks(
      on: await _afterATwoMovementOpening(),
    );
    await room.aGhostTake();

    expect(room.state.canHearAgain, isTrue);
    final before = room.harness.voice.played.length;
    await room.notifier.hearAgain();

    expect(room.harness.voice.played.sublist(before), [turnoUrl]);
    expect(room.state.needsPerson, isFalse);
  });

  test('a tap while the voice thinks does nothing', () async {
    final room = await _inConversa();
    room.harness.room.holdNextTurn();
    await room.tap();
    await room.tap();
    await waitFor(
      'a sala pensar',
      () => room.state.voice == VoiceState.thinking,
    );
    final stops = room.harness.voice.stops;
    final captures = room.harness.recorder.captures;
    final played = room.harness.voice.played.length;

    await room.tap();

    expect(room.harness.voice.stops, stops);
    expect(room.harness.recorder.captures, captures);
    expect(room.state.voice, VoiceState.thinking);

    room.harness.room.finishHeldTurn();
    await waitFor(
      'a resposta tocar',
      () => room.harness.voice.played.length > played,
    );
    expect(room.harness.voice.played.last, turnoUrl);
  });

  group('a cut in the Opening\'s first movement', () {
    Future<_Room> cutOnThePanorama() async {
      final harness = SalaHarness()..room.opensInTwoMovements = true;
      harness.voice
        ..holdNextLine()
        ..linePosition = const Duration(milliseconds: 1000)
        ..lineLength = const Duration(milliseconds: 5000);
      final container = harness.container();
      addTearDown(container.dispose);
      final room = _Room(harness, container);
      unawaited(room.notifier.goConversa());
      await waitFor(
        'o panorama falar',
        () =>
            room.state.voice == VoiceState.speaking &&
            harness.voice.played.last == panoramaUrl,
      );
      harness.room.opensInTwoMovements = false;
      await room.tap();
      return room;
    }

    test('reports that movement, and the Scene is never said', () async {
      final room = await cutOnThePanorama();

      await room.tap();
      await waitFor(
        'a vez cortada chegar à sala',
        () => room.harness.room.cutsSent.isNotEmpty,
      );
      await waitFor(
        'a sala voltar ao convite',
        () => room.state.voice == VoiceState.invite,
      );

      expect(room.harness.voice.played, isNot(contains(sceneUrl)));
      expect(room.lastCut?.at, const Duration(milliseconds: 1000));
      expect(room.lastCut?.of, const Duration(milliseconds: 5000));
    });

    test('keeps the Scene, with its Panorama, for «Ouvir de novo»', () async {
      final room = await cutOnThePanorama();
      await room.aGhostTake();

      final beforeAgain = room.harness.voice.played.length;
      await room.notifier.hearAgain();
      expect(room.harness.voice.played.sublist(beforeAgain), [sceneUrl]);

      final beforeWhole = room.harness.voice.played.length;
      await room.notifier.hearTheWholeOpening();
      expect(room.harness.voice.played.sublist(beforeWhole), [
        panoramaUrl,
        sceneUrl,
      ]);
    });
  });

  test('a cut in the Panorama of the whole Opening heard again does not say '
      'the Scene after the take', () async {
    final room = await _afterATwoMovementOpening();
    room.harness.voice.holdNextLine();
    final heard = room.notifier.hearTheWholeOpening();
    await waitFor(
      'o panorama falar de novo',
      () =>
          room.state.voice == VoiceState.speaking &&
          room.harness.voice.played.last == panoramaUrl,
    );
    final before = room.harness.voice.played.length;

    await room.tap();
    await room.tap();
    await heard;
    await waitFor(
      'a sala voltar ao convite',
      () => room.state.voice == VoiceState.invite,
    );

    expect(
      room.harness.voice.played.sublist(before),
      isNot(contains(sceneUrl)),
    );
  });

  group('a cut reply counts as heard', () {
    test('the passage\'s end settles as if it had played', () async {
      final room = await _inConversa();
      room.harness.room
        ..done = true
        ..readsDone = false;
      await _cutWhileSheSpeaks(on: room);

      await room.aGhostTake();

      expect(room.state.voice, VoiceState.done);
    });

    test(
      'a cut turn counts toward the calm streak that forgives a failure',
      () async {
        final harness = SalaHarness();
        harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
          sessionId: 'sessao-velha',
          stage: SalaStage.retro,
        );
        final container = harness.container();
        addTearDown(container.dispose);
        final room = _Room(harness, container);
        await room.notifier.abrirEscolha();
        await settle();
        Future<void> aCheckTheRoomRefuses() async {
          harness.room.failWith = const Refused('BAD_REQUEST');
          await room.notifier.goConversa(pericope: 'P01');
          await settle();
          harness.room.failWith = null;
        }

        await aCheckTheRoomRefuses();
        await room.aRealTake();
        await _cutWhileSheSpeaks(on: room);
        await room.aGhostTake();

        await aCheckTheRoomRefuses();
        await aCheckTheRoomRefuses();

        expect(room.state.needsPerson, isFalse);
      },
    );
  });

  group('a tap while the acknowledgement plays with the reply waiting', () {
    Future<(_Room, int)> cutOverTheAcknowledgement() async {
      final room = await _inConversa();
      room.harness.voice
        ..linePosition = const Duration(milliseconds: 700)
        ..lineLength = _of;
      await room.tap();
      room.harness.voice.holdNextLine();
      final played = room.harness.voice.played.length;
      await room.tap();
      await waitFor(
        'a resposta esperar atrás do reconhecimento',
        () =>
            room.harness.room.turnsSent > 0 &&
            room.state.voice == VoiceState.speaking,
      );
      await room.tap();
      return (room, played);
    }

    test('cuts both, and the reply is never said', () async {
      final (room, played) = await cutOverTheAcknowledgement();
      room.harness.voice.finishHeldLine();
      await room.aGhostTake();

      expect(
        room.harness.voice.played.sublist(played),
        isNot(contains(turnoUrl)),
      );
    });

    test(
      'tells the room she was cut at the start, of a length unknown',
      () async {
        final (room, _) = await cutOverTheAcknowledgement();

        await room.tap();
        await waitFor(
          'a vez cortada chegar à sala',
          () => room.harness.room.cutsSent.length == 2,
        );

        expect(room.lastCut?.at, Duration.zero);
        expect(room.lastCut?.of, isNull);
      },
    );

    test('keeps the reply for «Ouvir de novo»', () async {
      final room = await _afterATwoMovementOpening();
      await room.tap();
      room.harness.voice.holdNextLine();
      await room.tap();
      await waitFor(
        'a resposta esperar atrás do reconhecimento',
        () =>
            room.harness.room.turnsSent > 0 &&
            room.state.voice == VoiceState.speaking,
      );
      await room.tap();
      await room.aGhostTake();

      final before = room.harness.voice.played.length;
      await room.notifier.hearAgain();

      expect(room.harness.voice.played.sublist(before), [turnoUrl]);
    });
  });

  test(
    'the cut says how long the line was only when the player knows',
    () async {
      final room = await _cutWhileSheSpeaks(
        at: const Duration(milliseconds: 3000),
        of: null,
      );

      await room.tap();
      await waitFor(
        'a vez cortada chegar à sala',
        () => room.harness.room.cutsSent.length == 2,
      );

      expect(room.lastCut?.at, const Duration(milliseconds: 3000));
      expect(room.lastCut?.of, isNull);
    },
  );

  group('a tap while the voice speaks is ignored', () {
    test('by the Panorama\'s circle', () async {
      final harness = SalaHarness();
      harness.room.passages = [_panorama, ...harness.room.passages];
      final container = harness.container();
      addTearDown(container.dispose);
      final room = _Room(harness, container);
      harness.voice.holdNextFetch();
      await enterThePanorama(room.notifier, () => room.state);
      harness.voice.holdNextLine();
      harness.voice.finishHeldFetch();
      await waitFor(
        'o panorama falar',
        () => room.state.voice == VoiceState.speaking,
      );
      final stops = harness.voice.stops;
      final captures = harness.recorder.captures;

      room.notifier.panoramaTap();
      await settle();

      expect(harness.voice.stops, stops);
      expect(harness.recorder.captures, captures);
    });

    test('by the note', () async {
      final room = await _inConversa();
      await room.aReplySpeaking();
      final stops = room.harness.voice.stops;
      final captures = room.harness.recorder.captures;

      room.notifier.handTap();
      expect(room.state.noteMode, isTrue);
      await room.tap();

      expect(room.harness.voice.stops, stops);
      expect(room.harness.recorder.captures, captures);
    });
  });

  group('a cut whose microphone ends without a take tells the next take '
      'nothing', () {
    test('when the team leaves the passage', () async {
      final room = await _cutWhileSheSpeaks();

      room.notifier.leaveThePassage();
      await settle();
      await room.notifier.goConversa();
      await settle();
      final cuts = room.harness.room.cutsSent.length;
      await room.aRealTake();

      expect(room.harness.room.cutsSent, hasLength(cuts + 1));
      expect(room.lastCut, isNull);
    });

    test('when the recorder refuses to open', () async {
      final room = await _inConversa();
      await room.aReplySpeaking();
      room.harness.recorder.permitted = false;
      await room.tap();
      room.harness.recorder.permitted = true;
      final cuts = room.harness.room.cutsSent.length;

      await room.aRealTake();

      expect(room.harness.room.cutsSent, hasLength(cuts + 1));
      expect(room.lastCut, isNull);
    });
  });
}
