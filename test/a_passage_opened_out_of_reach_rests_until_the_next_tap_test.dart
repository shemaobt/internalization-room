import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_client.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _tryAgain = 'Tocar para tentar de novo';

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

Future<void> _wait(_Sala sala) async {
  for (var beat = 0; beat < 10; beat++) {
    await sala.tester.pump(const Duration(milliseconds: 100));
  }
}

class _ARadioThatForgetsWhenNobodyListens implements Connectivity {
  late final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast(
        onCancel: () => _forgot = true,
      );
  bool _forgot = false;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (!_forgot) return [ConnectivityResult.wifi];
    _forgot = false;
    return [ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  void close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Duration> get _theProductionLadder {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(roomRetryBackoffProvider);
}

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

Future<void> _theChoiceOffers(_Sala sala, bool Function(Passagem) isIt) async {
  await _until(sala, 'the wheel to load', () => _read(sala).naRoda != null);
  final at = _read(sala).naRoda!.indexWhere(isIt);
  sala.notifier.apontarPassagem(at);
  await _until(
    sala,
    'the wheel to offer the entry',
    () => _read(sala).aOferecer == at && _read(sala).voice == VoiceState.invite,
  );
}

Future<void> _chooseP01(_Sala sala, RoomFailure creation) async {
  unawaited(sala.notifier.abrirEscolha());
  await _theChoiceOffers(sala, (entry) => entry.pericope == 'P01');
  sala.harness.room.failCreateOnceWith = creation;
  sala.notifier.entrarNaOferecida();
  await _wait(sala);
}

void _restsWithoutAHalt(_Sala sala) {
  expect(_read(sala).needsPerson, isFalse);
  expect(sala.harness.room.deviceAsksReceived, isEmpty);
  expect(byLabel(_tryAgain), findsOneWidget);
}

Future<void> _theNextTapOpens(_Sala sala, void Function() tap) async {
  final before = _creates(sala);
  await _wait(sala);
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
    'a session refused by a network failure at the Choice rests on «Tocar '
    'para tentar de novo» and raises no halt',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      await _chooseP01(sala, const NetworkFailed('sem rede'));

      expect(_read(sala).sessionId, isNull);
      _restsWithoutAHalt(sala);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'the next tap after the room is back asks for the session again',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      await _chooseP01(sala, const NetworkFailed('sem rede'));

      await _theNextTapOpens(sala, sala.notifier.conversaTap);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a 500 on the session\'s creation rests and recovers the same way',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      await _chooseP01(
        sala,
        RoomClient.classify(500, const [], asksForTheSession: false)!,
      );

      _restsWithoutAHalt(sala);
      await _theNextTapOpens(sala, sala.notifier.conversaTap);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'from that rest ≡ and the chevron rest the same way and a tap asks for '
    'the session',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      await _chooseP01(sala, const NetworkFailed('sem rede'));

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
      await _wait(sala);

      expect(_read(sala).stage, SalaStage.conversa);
      _restsWithoutAHalt(sala);
      await _theNextTapOpens(sala, sala.notifier.conversaTap);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'the Panorama opened with the room out of reach rests and a tap asks for '
    'the session',
    (tester) async {
      final sala = await _theSala(
        tester,
        _aRoomThatWaitsForTheTap()..room.passages = _aBookWithItsPanorama,
      );
      unawaited(sala.notifier.abrirEscolha());
      await _theChoiceOffers(sala, (entry) => entry.isPanorama);
      sala.harness.room.reachable = false;
      sala.harness.network.reachable = false;
      sala.notifier.entrarNaOferecida();
      await _wait(sala);

      expect(_read(sala).stage, SalaStage.panorama);
      _restsWithoutAHalt(sala);
      sala.harness.room.reachable = true;
      sala.harness.network.reachable = true;
      await _theNextTapOpens(sala, sala.notifier.panoramaTap);
      closeTheRoom(sala.container);
    },
  );

  SalaHarness aRoomThatGivesUp() => SalaHarness(
    retryBackoff: const [Duration(minutes: 1)],
    busyCeiling: const Duration(milliseconds: 300),
  )..room.passages = _aBookWithItsPanorama;

  Future<void> theCreationIsGivenUp(_Sala sala) async {
    unawaited(sala.notifier.abrirEscolha());
    await _theChoiceOffers(sala, (entry) => entry.pericope == 'P01');
    sala.harness.room.holdNextCreate();
    sala.notifier.entrarNaOferecida();
    await _wait(sala);
  }

  testWidgets(
    'a session\'s creation the tablet gives up waiting for rests on «Tocar '
    'para tentar de novo», raises no halt, and its late answer opens nothing',
    (tester) async {
      final sala = await _theSala(tester, aRoomThatGivesUp());
      await theCreationIsGivenUp(sala);

      expect(_read(sala).sessionId, isNull);
      _restsWithoutAHalt(sala);

      sala.harness.room.finishHeldCreate();
      await _wait(sala);

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
      await _theChoiceOffers(sala, (entry) => entry.isPanorama);
      sala.notifier.entrarNaOferecida();
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

  Future<_Sala> aPassageThatFellWhileTheRoomWasSilent(
    WidgetTester tester,
  ) async {
    var roomIsSilent = false;
    final radio = _ARadioThatForgetsWhenNobodyListens();
    addTearDown(radio.close);
    final harness = SalaHarness(
      retryBackoff: _theProductionLadder,
      connectivity: ConnectivityService(
        connectivity: radio,
        client: MockClient((_) async {
          if (roomIsSilent) throw http.ClientException('Connection refused');
          return http.Response('{"status":"ok"}', 200);
        }),
      ),
    );
    final sala = await _theSala(tester, harness);
    unawaited(sala.notifier.abrirEscolha());
    await _theChoiceOffers(sala, (entry) => entry.pericope == 'P01');
    void set(bool silent) {
      roomIsSilent = silent;
      harness.room.reachable = !silent;
    }

    set(true);
    sala.notifier.entrarNaOferecida();
    await _wait(sala);
    expect(byLabel(_tryAgain), findsOneWidget);
    await _pass(sala, _theProductionLadder[0] + _theProductionLadder[1]);
    set(false);
    return sala;
  }

  testWidgets(
    'a passage that fell while the room was silent asks for its session once '
    'when the tap finds the room back',
    (tester) async {
      final sala = await aPassageThatFellWhileTheRoomWasSilent(tester);
      final before = _creates(sala);

      sala.notifier.conversaTap();
      await _pass(sala, const Duration(seconds: 3));

      expect(_creates(sala), before + 1);
      expect(byLabel(_tryAgain), findsNothing);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a passage that fell while the room was silent asks for its session once '
    'when the ladder finds the room back',
    (tester) async {
      final sala = await aPassageThatFellWhileTheRoomWasSilent(tester);
      final before = _creates(sala);

      await _pass(sala, _theProductionLadder[2]);

      expect(_creates(sala), before + 1);
      expect(byLabel(_tryAgain), findsNothing);
      closeTheRoom(sala.container);
    },
  );

  Future<String> aHaltInThePanoramaCalledFor(_Sala sala) async {
    final harness = sala.harness;
    unawaited(sala.notifier.abrirEscolha());
    await _theChoiceOffers(sala, (entry) => entry.isPanorama);
    sala.notifier.entrarNaOferecida();
    await _until(
      sala,
      'the Panorama to be said',
      () => _read(sala).panoramaSaid && _read(sala).voice == VoiceState.invite,
    );
    harness.room.reachable = false;
    harness.network.reachable = false;
    sala.notifier.panoramaTap();
    await sala.tester.pump(const Duration(milliseconds: 100));
    sala.notifier.panoramaTap();
    await _until(sala, 'the person sign', () => _read(sala).needsPerson);
    harness.room.reachable = true;
    harness.network.reachable = true;
    await _until(
      sala,
      'the call for a person',
      () =>
          harness.room.personAsksFor.isNotEmpty ||
          harness.room.deviceAsksReceived.isNotEmpty,
    );
    return harness.room.sessionIds.single;
  }

  testWidgets(
    'a halt in the Panorama calls for a person by the Panorama\'s session, and '
    'the Desk\'s lift on that session clears it',
    (tester) async {
      final sala = await _theSala(
        tester,
        SalaHarness()..room.passages = _aBookWithItsPanorama,
      );
      final panorama = await aHaltInThePanoramaCalledFor(sala);

      expect(sala.harness.room.personAsksFor, [panorama]);
      expect(sala.harness.room.deviceAsksReceived, isEmpty);

      sala.harness.room.theDeskAttended();
      await _until(
        sala,
        'the Desk\'s lift to reach the tablet',
        () => !_read(sala).needsPerson,
      );
      expect(sala.harness.room.deviceAsksReceived, isEmpty);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a long press over a halt in the Panorama tells the Panorama\'s session a '
    'person arrived',
    (tester) async {
      final sala = await _theSala(
        tester,
        SalaHarness()..room.passages = _aBookWithItsPanorama,
      );
      final panorama = await aHaltInThePanoramaCalledFor(sala);
      await _wait(sala);

      sala.notifier.resolveWithPerson();
      await _wait(sala);

      expect(sala.harness.room.personArrivedSessions, [panorama]);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a turn without network on a live session still shows the person sign',
    (tester) async {
      final sala = await _theSala(tester, _aRoomThatWaitsForTheTap());
      unawaited(sala.notifier.abrirEscolha());
      await _theChoiceOffers(sala, (entry) => entry.pericope == 'P01');
      sala.notifier.entrarNaOferecida();
      await _until(
        sala,
        'the session to rest at the invite',
        () =>
            _read(sala).sessionId != null &&
            _read(sala).voice == VoiceState.invite,
      );

      sala.harness.room.reachable = false;
      sala.harness.network.reachable = false;
      sala.notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 100));
      sala.notifier.conversaTap();
      await _until(sala, 'the person sign', () => _read(sala).needsPerson);

      expect(byLabel('Um momento para uma pessoa'), findsOneWidget);
      closeTheRoom(sala.container);
    },
  );
}
