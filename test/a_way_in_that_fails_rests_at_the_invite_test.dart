import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _theSign = 'Um momento para uma pessoa';

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
});

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

SalaSessionNotifier _notifier(_Sala sala) =>
    sala.container.read(salaSessionProvider.notifier);

Future<void> _until(_Sala sala, String what, bool Function() ready) => waitFor(
  what,
  ready,
  step: () => sala.tester.pump(const Duration(milliseconds: 100)),
);

Future<void> _pass(_Sala sala, [int beats = 30]) async {
  for (var beat = 0; beat < beats; beat++) {
    await sala.tester.pump(const Duration(milliseconds: 100));
  }
}

int _said(_Sala sala) =>
    sala.harness.voice.played.length +
    sala.harness.voice.assets.length +
    sala.harness.voice.fixedLines.length;

int _creates(_Sala sala) =>
    sala.harness.room.calls.where((call) => call == 'createSession').length;

Future<_Sala> _theRoom(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = _aBookWithItsPanorama;
  final container = await pumpSala(tester, harness);
  final sala = (tester: tester, harness: harness, container: container);
  await _until(sala, 'the Choice to be listed', () => _read(sala).entriesOpen);
  return sala;
}

void _restsSilentAtTheInvite(_Sala sala, int said) {
  expect(_said(sala), said, reason: 'nothing is said');
  expect(byLabel(_theSign), findsNothing);
  expect(_read(sala).needsPerson, isFalse);
  expect(_read(sala).voice, VoiceState.invite);
}

Future<void> _theNextTapOpens(_Sala sala, void Function() tap) async {
  final before = _creates(sala);
  sala.harness.room.reachable = true;
  tap();
  await _until(
    sala,
    'the opening to play',
    () => sala.harness.voice.played.isNotEmpty,
  );
  expect(_creates(sala), before + 1);
}

void main() {
  test('a way in whose Step fails on the network only lets its Step go', () {
    for (final machine in const [
      Machine(),
      Machine(station: Canvas()),
      Machine(station: Panorama('panorama')),
    ]) {
      final (next, effects) = reduce(machine, const NetworkFailedAt(Door.step));

      expect(effects, const [LetTheStepGo()]);
      expect(next.halt, machine.halt);
    }
  });

  testWidgets(
    'opening a passage while the room cannot be reached speaks nothing and '
    'rests at the invite; the next tap asks for the session again',
    (tester) async {
      final sala = await _theRoom(tester);
      final said = _said(sala);
      sala.harness.room.reachable = false;

      unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
      await _pass(sala);

      _restsSilentAtTheInvite(sala, said);
      expect(_read(sala).stage, SalaStage.conversa);
      expect(byLabel(circleLabelFor('default', testLanguage)), findsOneWidget);

      await _theNextTapOpens(sala, _notifier(sala).conversaTap);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'the Choice whose wheel could not be read rests silent, and a tap reads it '
    'again',
    (tester) async {
      final harness =
          SalaHarness(
              filaEmMemoria: true,
              linkedAs: const RememberedLink(
                deviceId: 'aparelho-1',
                team: TeamLink(projectId: 'equipe-1'),
                credential: 'credencial-1',
              ),
            )
            ..room.passages = _aBookWithItsPanorama
            ..room.reachable = false;
      final container = await pumpSala(tester, harness);
      final sala = (tester: tester, harness: harness, container: container);
      await _pass(sala);

      expect(_read(sala).naRoda, isNull);
      expect(_said(sala), 0, reason: 'nothing is said');
      expect(byLabel(_theSign), findsNothing);
      expect(_read(sala).needsPerson, isFalse);

      sala.harness.room.reachable = true;
      _notifier(sala).escolhaTap();
      await _until(
        sala,
        'the books to be listed',
        () => _read(sala).naRoda?.isNotEmpty ?? false,
      );
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a Panorama opened while the room cannot be reached rests silent, and a tap '
    'opens it',
    (tester) async {
      final sala = await _theRoom(tester);
      final chosen = _read(
        sala,
      ).naRoda!.firstWhere((entry) => entry.isPanorama);
      final said = _said(sala);
      sala.harness.room.reachable = false;

      _notifier(sala).openTheEntry(chosen);
      await _pass(sala);

      _restsSilentAtTheInvite(sala, said);
      expect(_read(sala).stage, SalaStage.panorama);

      await _theNextTapOpens(sala, _notifier(sala).panoramaTap);
      closeTheRoom(sala.container);
    },
  );
}
