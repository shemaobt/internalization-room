import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';
const _notSent = 'não deu para enviar agora — tentem de novo';
const _alreadySent = 'a tradução deste ensaio da cena já foi para a voz';
const _listen =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para '
    'ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de '
    'vocês.';

final _redMicrophone = byLabel('ensaio da cena');
final _wentToTheVoice = byLabel(_listen);
final _terminei = byLabel('terminei');
final _theWayBack = byLabel('Voltar para a passagem atual');

Finder _says(String words) => find.byWidgetPredicate(
  (widget) =>
      (widget is Text && (widget.data?.contains(words) ?? false)) ||
      (widget is Semantics &&
          (widget.properties.label?.contains(words) ?? false)),
);

SceneRehearsalRecord _theRehearsal({String? sentAt}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: _session,
  n: 1,
  recordedAt: DateTime(2026, 10, 15, 14, 5),
  sentAt: sentAt,
  frases: const [
    SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
    SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 9000),
  ],
);

final _unsent = _theRehearsal();
final _listedSent = _theRehearsal(sentAt: '2026-10-15T15:00:00+00:00');

bool? _enabled(WidgetTester tester, Finder control) =>
    tester.widget<Semantics>(control).properties.enabled;

int _repliesPlayed(SalaHarness harness) =>
    harness.voice.played.where((url) => url == turnoUrl).length;

SalaSessionState _state(ProviderContainer container) =>
    container.read(salaSessionProvider);

/// The scene screen on the translate step of an unsent rehearsal with two frases, over
/// a session at rest in Articulação.
Future<(SalaHarness, ProviderContainer)> _theRehearsalOnScreen(
  WidgetTester tester, {
  Duration? busyCeiling,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, busyCeiling: busyCeiling)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room
    ..sceneRehearsals.add(_unsent)
    ..sceneAudio = Uint8List.fromList([1, 2, 3]);
  harness.playback.measured = const Duration(seconds: 20);
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await pumpUntil(tester, () => _state(container).voice == VoiceState.invite);
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.tap(_redMicrophone);
  await pumpUntil(
    tester,
    () =>
        _state(container).scene.step == SceneStep.translate &&
        !_state(container).scene.waiting,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

/// «terminei», and the wait until the room has looked once and rests.
Future<void> _termineiAndTheLook(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await tester.tap(_terminei);
  await pumpUntil(tester, () => harness.room.turnIdsLookedAt.isNotEmpty);
  await pumpUntil(
    tester,
    () =>
        !_state(container).awaitingTheGuide &&
        _state(container).machine.inFlight == null,
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _backToTheSession(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(_theWayBack);
  await pumpUntil(tester, () => _state(container).stage == SalaStage.conversa);
  await tester.pump(const Duration(seconds: 1));
}

/// A first «terminei» that drops and whose look finds nothing: «não deu…» and the sign
/// waiting.
Future<void> _aFailedSend(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
  await _termineiAndTheLook(tester, harness, container);
  expect(_says(_notSent), findsWidgets);
}

void main() {
  testWidgets(
    'a scene rehearsal whose send drops and did not arrive says «não deu para '
    'enviar agora — tentem de novo», and «terminei» sends it again',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
      final repliesBefore = _repliesPlayed(harness);

      await _termineiAndTheLook(tester, harness, container);

      expect(_state(container).stage, SalaStage.cena);
      expect(_says(_notSent), findsWidgets);
      expect(_enabled(tester, _terminei), isTrue);

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);

      expect(harness.room.scenesSent, hasLength(2));
      await tester.pump(const Duration(seconds: 2));
    },
  );

  for (final (what, code) in [
    ('a 422', RefusalCode.unnamed(422)),
    ('a 404', RefusalCode.notFound),
  ]) {
    testWidgets(
      'a «terminei» again refused with $what says «não deu para enviar agora — '
      'tentem de novo» and forgets the waiting sign',
      (tester) async {
        final (harness, container) = await _theRehearsalOnScreen(tester);
        await _aFailedSend(tester, harness, container);
        harness.room.sendRefusalsFirst.add(code);

        await tester.tap(_terminei);
        await pumpUntil(tester, () => harness.room.scenesSent.length == 2);
        await tester.pump(const Duration(seconds: 1));

        expect(_says(_notSent), findsWidgets);
        expect(_enabled(tester, _terminei), isTrue);

        await _backToTheSession(tester, container);

        expect(_state(container).needsPerson, isFalse);
      },
    );
  }

  testWidgets(
    'a «terminei» again that drops says «não deu para enviar agora — tentem de '
    'novo» and keeps the sign waiting',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      await _aFailedSend(tester, harness, container);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');

      await tester.tap(_terminei);
      await pumpUntil(tester, () => harness.room.turnIdsLookedAt.length == 2);
      await pumpUntil(tester, () => !_state(container).awaitingTheGuide);
      await tester.pump(const Duration(seconds: 1));

      expect(_says(_notSent), findsWidgets);

      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isTrue);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a first «terminei» refused with a 422 says «não deu para enviar agora — '
    'tentem de novo» and leaves no sign',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.sendRefusalsFirst.add(RefusalCode.unnamed(422));

      await tester.tap(_terminei);
      await pumpUntil(tester, () => harness.room.scenesSent.isNotEmpty);
      await pumpUntil(tester, () => !_state(container).awaitingTheGuide);
      await tester.pump(const Duration(seconds: 1));

      expect(_state(container).stage, SalaStage.cena);
      expect(_says(_notSent), findsWidgets);
      expect(_enabled(tester, _terminei), isTrue);

      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isFalse);
    },
  );

  testWidgets(
    'a «terminei» again refused because the passage closed closes the passage',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      await _aFailedSend(tester, harness, container);
      harness.room.sendRefusalsFirst.add(RefusalCode.passageClosed);

      await tester.tap(_terminei);
      await pumpUntil(
        tester,
        () => _state(container).stage == SalaStage.escolha,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(_state(container).stage, SalaStage.escolha);
    },
  );

  testWidgets(
    'a «terminei» again the room refuses as already sent forgets the waiting sign',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      await _aFailedSend(tester, harness, container);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneRehearsals[0] = _listedSent;

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _wentToTheVoice.evaluate().isNotEmpty);
      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isFalse);
    },
  );

  testWidgets(
    'a «terminei» that lands after «não deu para enviar agora» forgets the '
    'waiting sign',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
      final repliesBefore = _repliesPlayed(harness);
      await _termineiAndTheLook(tester, harness, container);

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);
      await pumpUntil(
        tester,
        () =>
            _state(container).stage == SalaStage.conversa &&
            _state(container).voice == VoiceState.invite,
      );
      await tester.pump(const Duration(seconds: 2));

      expect(_state(container).stage, SalaStage.conversa);
      expect(_state(container).needsPerson, isFalse);
    },
  );

  testWidgets(
    'a «terminei» again whose answer is lost but found by the look forgets the '
    'waiting sign',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
      final repliesBefore = _repliesPlayed(harness);
      await _termineiAndTheLook(tester, harness, container);
      harness.room
        ..turnsLandBeforeTheyFail = true
        ..failHeldTurnWith = const NetworkFailed('a rede caiu');

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);
      await pumpUntil(
        tester,
        () =>
            _state(container).stage == SalaStage.conversa &&
            _state(container).voice == VoiceState.invite,
      );
      await tester.pump(const Duration(seconds: 2));

      expect(_state(container).stage, SalaStage.conversa);
      expect(_state(container).needsPerson, isFalse);
    },
  );

  testWidgets(
    'a scene rehearsal listed as sent while the sign waits is never sent again',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..failHeldTurnWith = const NetworkFailed('a rede caiu')
        ..sceneRehearsals[0] = _listedSent;

      await _termineiAndTheLook(tester, harness, container);
      await tester.pump(const Duration(seconds: 3));

      expect(_state(container).stage, SalaStage.cena);
      expect(harness.room.scenesSent, hasLength(1));

      await _backToTheSession(tester, container);
      container.read(salaSessionProvider.notifier).teamTapped();
      await pumpUntil(tester, () => !_state(container).needsPerson);
      await tester.pump(const Duration(seconds: 2));

      expect(harness.room.scenesSent, hasLength(1));
    },
  );

  testWidgets(
    'a scene rehearsal whose send drops but arrived shows once that it went to '
    'the voice, plays nothing and is not sent again',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..failHeldTurnWith = const NetworkFailed('a rede caiu')
        ..sceneRehearsals[0] = _listedSent;
      final repliesBefore = _repliesPlayed(harness);

      await _termineiAndTheLook(tester, harness, container);

      expect(_state(container).stage, SalaStage.cena);
      expect(_wentToTheVoice, findsOneWidget);
      expect(_says(_alreadySent), findsNothing);
      expect(_terminei, findsNothing);
      expect(harness.room.scenesSent, hasLength(1));
      expect(_repliesPlayed(harness), repliesBefore);
    },
  );

  testWidgets(
    'after a failed scene send, the team returning to the session screen sees '
    'the person sign',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');

      await _termineiAndTheLook(tester, harness, container);
      expect(_says(_notSent), findsWidgets);
      expect(_state(container).needsPerson, isFalse);

      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isTrue);
      closeTheRoom(container);
    },
  );

  group('a scene rehearsal answered without a reply to play', () {
    testWidgets('says the same sentence and leaves the same sign waiting', (
      tester,
    ) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..answersTurnsWithoutAReply = true
        ..sceneListsAnswerFirst.add(Answered([_unsent]));

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _says(_notSent).evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));

      expect(_state(container).stage, SalaStage.cena);
      expect(_says(_notSent), findsWidgets);
      expect(_enabled(tester, _terminei), isTrue);
      expect(_state(container).needsPerson, isFalse);

      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isTrue);
      closeTheRoom(container);
    });

    testWidgets(
      'that the room lists sent says «a tradução deste ensaio da cena já foi '
      'para a voz», with the same sign waiting',
      (tester) async {
        final (harness, container) = await _theRehearsalOnScreen(tester);
        harness.room.answersTurnsWithoutAReply = true;

        await tester.tap(_terminei);
        await pumpUntil(tester, () => _wentToTheVoice.evaluate().isNotEmpty);

        expect(_state(container).stage, SalaStage.cena);
        expect(_wentToTheVoice, findsOneWidget);
        expect(_says(_alreadySent), findsNothing);
        expect(_state(container).needsPerson, isFalse);

        await _backToTheSession(tester, container);

        expect(_state(container).needsPerson, isTrue);
        closeTheRoom(container);
      },
    );
  });

  testWidgets('nothing is spoken about a failed scene send', (tester) async {
    final (harness, container) = await _theRehearsalOnScreen(tester);
    harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
    final fixedLinesBefore = harness.voice.fixedLines.length;
    final playedBefore = harness.voice.played.length;
    final assetsBefore = harness.voice.assets.length;
    final personsBefore = harness.room.personsAsked;

    await _termineiAndTheLook(tester, harness, container);
    await tester.pump(const Duration(seconds: 2));

    expect(
      harness.voice.fixedLines.skip(fixedLinesBefore).map((line) => line.$1),
      everyElement(isIn(instantAckLines)),
    );
    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(harness.voice.assets.skip(assetsBefore), isEmpty);
    expect(harness.room.personsAsked, personsBefore);
  });

  testWidgets(
    '«terminei» again after a failed scene send reuses its turn id, and a room '
    'that already holds the reply plays it once',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..turnsLandBeforeTheyFail = true
        ..failHeldTurnWith = const NetworkFailed('a rede caiu')
        ..failLooksWith = const NetworkFailed('a rede caiu')
        ..sceneListsAnswerFirst.add(Answered([_unsent]));
      final repliesBefore = _repliesPlayed(harness);

      await _termineiAndTheLook(tester, harness, container);
      expect(_says(_notSent), findsWidgets);
      harness.room.failLooksWith = null;

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);
      await tester.pump(const Duration(seconds: 2));

      expect(
        harness.room.scenesSent.map((send) => send.turnId).toSet(),
        hasLength(1),
      );
      expect(harness.room.scenesSent, hasLength(2));
      expect(_repliesPlayed(harness), repliesBefore + 1);
    },
  );

  group('a «terminei» the room refuses as already sent says «a tradução deste '
      'ensaio da cena já foi para a voz»', () {
    testWidgets('on the first tap', (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneRehearsals[0] = _listedSent;

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _wentToTheVoice.evaluate().isNotEmpty);

      expect(_wentToTheVoice, findsOneWidget);
      expect(_says(_alreadySent), findsNothing);
      expect(harness.room.scenesSent, hasLength(1));
    });

    testWidgets('on the tap after a failed send', (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
      await _termineiAndTheLook(tester, harness, container);
      expect(_says(_notSent), findsWidgets);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneRehearsals[0] = _listedSent;

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _wentToTheVoice.evaluate().isNotEmpty);

      expect(_wentToTheVoice, findsOneWidget);
      expect(_says(_alreadySent), findsNothing);
      expect(harness.room.scenesSent, hasLength(2));
    });

    testWidgets('even when the list cannot be read', (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneListsAnswerFirst.add(const NetworkFailed('a rede caiu'));

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _says(_alreadySent).evaluate().isNotEmpty);

      expect(_says(_alreadySent), findsWidgets);
      expect(harness.room.scenesSent, hasLength(1));
    });
  });

  testWidgets('a scene send that times out says the same as one that dropped', (
    tester,
  ) async {
    final (harness, container) = await _theRehearsalOnScreen(
      tester,
      busyCeiling: const Duration(milliseconds: 300),
    );
    harness.room.holdNextTurn();

    await _termineiAndTheLook(tester, harness, container);

    expect(_state(container).stage, SalaStage.cena);
    expect(_says(_notSent), findsWidgets);
    expect(_enabled(tester, _terminei), isTrue);
    harness.room.finishHeldTurn();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the late answer of a scene send that timed out plays nothing', (
    tester,
  ) async {
    final (harness, container) = await _theRehearsalOnScreen(
      tester,
      busyCeiling: const Duration(milliseconds: 300),
    );
    harness.room.holdNextTurn();
    final repliesBefore = _repliesPlayed(harness);
    await _termineiAndTheLook(tester, harness, container);

    harness.room.finishHeldTurn();
    await tester.pump(const Duration(seconds: 2));

    expect(_repliesPlayed(harness), repliesBefore);
    expect(_says(_notSent), findsWidgets);
  });

  group('a refusal of an earlier «terminei» that comes after the team tapped '
      'again', () {
    Future<(SalaHarness, ProviderContainer, int)> theEarlierRefusalLate(
      WidgetTester tester,
    ) async {
      final (harness, container) = await _theRehearsalOnScreen(
        tester,
        busyCeiling: const Duration(seconds: 3),
      );
      final repliesBefore = _repliesPlayed(harness);
      harness.room.holdSceneSends = true;
      await _termineiAndTheLook(tester, harness, container);
      expect(_says(_notSent), findsWidgets);
      await tester.tap(_terminei);
      await pumpUntil(tester, () => harness.room.heldSceneSends.length == 2);
      harness.room.heldSceneSends[0].complete(
        Refused(RefusalCode.unnamed(422)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return (harness, container, repliesBefore);
    }

    testWidgets('keeps the sign waiting and says nothing while the «terminei» '
        'again is in the air', (tester) async {
      final (harness, container, _) = await theEarlierRefusalLate(tester);

      expect(_state(container).machine.aHaltWaitsForTheCanvas, isNotNull);
      expect(_says(_notSent), findsNothing);

      harness.room.heldSceneSends[1].complete(null);
      await pumpUntil(
        tester,
        () =>
            !_state(container).awaitingTheGuide &&
            !_state(container).scene.wentToTheVoice,
      );
      closeTheRoom(container);
    });

    testWidgets('lets the «terminei» again play its reply', (tester) async {
      final (harness, _, repliesBefore) = await theEarlierRefusalLate(tester);

      harness.room.heldSceneSends[1].complete(null);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);
      await tester.pump(const Duration(seconds: 4));

      expect(_repliesPlayed(harness), repliesBefore + 1);
    });

    testWidgets('leaves the sign waiting when the «terminei» again drops', (
      tester,
    ) async {
      final (harness, container, _) = await theEarlierRefusalLate(tester);

      harness.room.heldSceneSends[1].complete(
        const NetworkFailed('a rede caiu'),
      );
      await pumpUntil(tester, () => harness.room.turnIdsLookedAt.length == 2);
      await pumpUntil(tester, () => !_state(container).awaitingTheGuide);
      await _backToTheSession(tester, container);

      expect(_state(container).needsPerson, isTrue);
      closeTheRoom(container);
    });
  });

  group('a «terminei» whose answer cannot be read', () {
    testWidgets('plays the reply the look finds, once', (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..turnsLandBeforeTheyFail = true
        ..failHeldTurnWith = const Refused(RefusalCode.unreadable);
      final repliesBefore = _repliesPlayed(harness);

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _repliesPlayed(harness) > repliesBefore);
      await tester.pump(const Duration(seconds: 2));

      expect(_repliesPlayed(harness), repliesBefore + 1);
      expect(harness.room.scenesSent, hasLength(1));
    });

    testWidgets(
      'says «não deu para enviar agora — tentem de novo» and leaves the sign '
      'waiting when the look finds nothing',
      (tester) async {
        final (harness, container) = await _theRehearsalOnScreen(tester);
        harness.room.failHeldTurnWith = const Refused(RefusalCode.unreadable);

        await _termineiAndTheLook(tester, harness, container);

        expect(_says(_notSent), findsWidgets);

        await _backToTheSession(tester, container);

        expect(_state(container).needsPerson, isTrue);
        closeTheRoom(container);
      },
    );
  });

  testWidgets(
    'a refused «terminei» whose list reads the rehearsal as sent shows that it '
    'went to the voice instead of «não deu para enviar agora»',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.unnamed(422))
        ..sceneRehearsals[0] = _listedSent;

      await tester.tap(_terminei);
      await pumpUntil(tester, () => _wentToTheVoice.evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));

      expect(_wentToTheVoice, findsOneWidget);
      expect(_says(_notSent), findsNothing);
    },
  );

  testWidgets(
    'a refused «terminei» whose list lands on places unknown stops the take '
    'the team started in between, as hers',
    (tester) async {
      final (harness, container) = await _theRehearsalOnScreen(tester);
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.unnamed(422))
        ..sceneRehearsals[0] = SceneRehearsalRecord(
          rehearsalId: 'ensaio-da-cena-1',
          sessionId: _session,
          n: 1,
          recordedAt: DateTime(2026, 10, 15, 14, 5),
          frases: const [
            SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
            SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 25000),
          ],
        )
        ..holdNextSceneList();
      await tester.tap(_terminei);
      await pumpUntil(tester, () => harness.room.scenesSent.isNotEmpty);
      await pumpUntil(tester, () => !_state(container).theSceneIsSending);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byLabel('Tocar ou pausar a gravação'));
      await pumpUntil(tester, () => _state(container).channel is PartPlaying);
      expect(_state(container).channel, isA<PartPlaying>());

      harness.room.finishHeldSceneList();
      await pumpUntil(
        tester,
        () => _state(container).scene.step == SceneStep.placesUnknown,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(_state(container).scene.step, SceneStep.placesUnknown);
      expect(
        _state(container).channel,
        isNot(isA<PartPlaying>()),
        reason:
            'o take seguia tocando na tela de lugares desconhecidos, onde nada o para',
      );
    },
  );
}
