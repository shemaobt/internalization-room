import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_client.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

final _atRest = byLabel(circleLabelFor('default', testLanguage));

const _aBookWithItsPanorama = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
];

typedef _Sala = ({
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier notifier,
});

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

int _creates(_Sala sala) =>
    sala.harness.room.calls.where((call) => call == 'createSession').length;

Future<void> _until(_Sala sala, String what, bool Function() ready) => waitFor(
  what,
  ready,
  step: () => sala.tester.pump(const Duration(milliseconds: 100)),
);

Future<void> _pass(_Sala sala, Duration time) async {
  for (var beat = Duration.zero; beat < time; beat += _aBeat) {
    await sala.tester.pump(_aBeat);
  }
}

const _aBeat = Duration(milliseconds: 100);

SalaHarness _aRoomThatWaitsForTheTap() =>
    SalaHarness(retryBackoff: const [Duration(minutes: 1)]);

Future<_Sala> _theSala(WidgetTester tester, SalaHarness harness) async {
  final container = await pumpSala(tester, harness);
  return (
    tester: tester,
    harness: harness,
    container: container,
    notifier: container.read(salaSessionProvider.notifier),
  );
}

Future<Passagem> _theChoiceOffers(
  _Sala sala,
  bool Function(Passagem) isIt,
) async {
  await _until(sala, 'the entries to open', () => _read(sala).entriesOpen);
  return _read(sala).naRoda!.firstWhere(isIt);
}

Future<Passagem> _chooseP01(_Sala sala, RoomFailure creation) async {
  unawaited(sala.notifier.abrirEscolha());
  final chosen = await _theChoiceOffers(
    sala,
    (entry) => entry.pericope == 'P01',
  );
  sala.harness.room.failCreateOnceWith = creation;
  sala.notifier.openTheEntry(chosen);
  return chosen;
}

Future<void> _enterP01Without(_Sala sala, RoomFailure creation) async {
  unawaited(sala.notifier.abrirEscolha());
  await _theChoiceOffers(sala, (entry) => entry.pericope == 'P01');
  sala.harness.room.failCreateOnceWith = creation;
  unawaited(sala.notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _restsAtTheInvite(sala);
}

Future<void> _restsAtTheInvite(_Sala sala) => _until(
  sala,
  'the room to rest at the invite',
  () => !_read(sala).awaitingTheGuide && _atRest.evaluate().isNotEmpty,
);

void _restsWithoutAHalt(_Sala sala) {
  expect(_read(sala).needsPerson, isFalse);
  expect(_read(sala).voice, VoiceState.invite);
  expect(_atRest, findsOneWidget);
}

Future<void> _theNextTapOpens(_Sala sala, void Function() tap) async {
  final before = _creates(sala);
  await _pass(sala, const Duration(seconds: 1));
  expect(_creates(sala), before);
  tap();
  await _until(
    sala,
    'the Opening to be asked',
    () => sala.harness.room.turnIdsAsked.isNotEmpty,
  );
  expect(_creates(sala), before + 1);
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local'));

  testWidgets(
    'a 500 on the session\'s creation from the Choice leaves the team on the '
    'Choice, and the same pill asks again',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      final chosen = await _chooseP01(
        sala,
        RoomClient.classify(500, const [], asksForTheSession: false)!,
      );
      await _until(
        sala,
        'the Choice to come back',
        () => _creates(sala) == 1 && _read(sala).entriesOpen,
      );

      expect(
        _read(sala).stage,
        SalaStage.escolha,
        reason: 'a equipe ficava no círculo de uma passagem sem sessão',
      );
      expect(_read(sala).needsPerson, isFalse);
      await _theNextTapOpens(sala, () => sala.notifier.openTheEntry(chosen));
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'from a passage entered with no session ≡ and the chevron rest the same '
    'way and a tap asks for the session',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      await _enterP01Without(sala, const NetworkFailed('sem rede'));

      sala.notifier.leaveThePassage();
      await tester.pump(const Duration(seconds: 2));
      sala.notifier.escolhaTap();
      await _until(
        sala,
        'the way back to be live',
        () => _read(sala).theWayBackIsLive,
      );
      sala.harness.room.failCreateOnceWith = const NetworkFailed('sem rede');
      unawaited(sala.notifier.returnToTheLeftEntry());
      await _restsAtTheInvite(sala);

      expect(_read(sala).stage, SalaStage.conversa);
      _restsWithoutAHalt(sala);
      await _theNextTapOpens(sala, sala.notifier.conversaTap);
      closeTheRoom(sala.container);
    },
  );

  SalaHarness aRoomThatGivesUp() => SalaHarness(
    retryBackoff: const [Duration(minutes: 1)],
    busyCeiling: const Duration(milliseconds: 1500),
  )..room.passages = _aBookWithItsPanorama;

  Future<void> theCreationIsGivenUp(_Sala sala) async {
    unawaited(sala.notifier.abrirEscolha());
    final chosen = await _theChoiceOffers(
      sala,
      (entry) => entry.pericope == 'P01',
    );
    sala.harness.room.holdNextCreate();
    sala.notifier.openTheEntry(chosen);
    await _restsAtTheInvite(sala);
  }

  testWidgets(
    'a session\'s creation the tablet gives up waiting for rests at the '
    'invite, raises no halt, and its late answer opens nothing',
    (tester) async {
      final sala = await _theSala(tester, aRoomThatGivesUp());
      await theCreationIsGivenUp(sala);

      expect(_read(sala).sessionId, isNull);
      _restsWithoutAHalt(sala);

      sala.harness.room.finishHeldCreate();
      await _pass(sala, const Duration(seconds: 1));

      expect(_read(sala).sessionId, isNull);
      expect(sala.harness.room.turnIdsAsked, isEmpty);
      _restsWithoutAHalt(sala);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a creation given up after a visit to the Panorama rests the same way',
    (tester) async {
      final sala = await _theSala(tester, aRoomThatGivesUp());
      unawaited(sala.notifier.abrirEscolha());
      final chosen = await _theChoiceOffers(sala, (entry) => entry.isPanorama);
      sala.notifier.openTheEntry(chosen);
      await _until(
        sala,
        'the Panorama to be said',
        () => _read(sala).panoramaSaid,
      );
      sala.notifier.leaveThePassage();
      await tester.pump(const Duration(seconds: 2));

      await theCreationIsGivenUp(sala);
      await tester.pump(const Duration(seconds: 2));

      expect(_read(sala).stage, SalaStage.conversa);
      _restsWithoutAHalt(sala);
      sala.harness.room.finishHeldCreate();
      closeTheRoom(sala.container);
    },
  );

  Future<String> aHaltInThePanoramaCalledFor(_Sala sala) async {
    final harness = sala.harness;
    unawaited(sala.notifier.abrirEscolha());
    final chosen = await _theChoiceOffers(sala, (entry) => entry.isPanorama);
    sala.notifier.openTheEntry(chosen);
    await _until(
      sala,
      'the Panorama to be said',
      () => _read(sala).panoramaSaid && _read(sala).voice == VoiceState.invite,
    );
    harness.room.reachable = false;
    sala.notifier.panoramaTap();
    await sala.tester.pump(const Duration(milliseconds: 100));
    sala.notifier.panoramaTap();
    await _until(sala, 'the person sign', () => _read(sala).needsPerson);
    harness.room.reachable = true;
    await _until(
      sala,
      'the call for a person',
      () => harness.room.personAsksFor.isNotEmpty,
    );
    return harness.room.sessionIds.single;
  }

  testWidgets(
    'a halt in the Panorama calls for a person by the Panorama\'s session, and '
    'the team\'s tap clears it',
    (tester) async {
      final sala = await _theSala(
        tester,
        SalaHarness()..room.passages = _aBookWithItsPanorama,
      );
      final panorama = await aHaltInThePanoramaCalledFor(sala);

      expect(sala.harness.room.personAsksFor, [panorama]);

      sala.notifier.teamTapped();
      await _until(sala, 'the sign to clear', () => !_read(sala).needsPerson);
      closeTheRoom(sala.container);
    },
  );
}
