import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

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
  expect(thePersonSign, findsNothing);
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
    'a passage whose session could not be created is not asked for again by '
    'itself, however long the team waits',
    (tester) async {
      final sala = await _theRoom(tester);
      final said = _said(sala);
      sala.harness.room.reachable = false;

      unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
      await _pass(sala);
      sala.harness.room.reachable = true;
      for (var minute = 0; minute < 10; minute++) {
        await tester.pump(const Duration(minutes: 1));
      }

      expect(_creates(sala), 1);
      _restsSilentAtTheInvite(sala, said);
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
      expect(thePersonSign, findsNothing);
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
    'a Panorama opened while the room cannot be reached rests silent on the '
    'Choice, and its pill opens it',
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
      expect(
        _read(sala).stage,
        SalaStage.escolha,
        reason: 'a equipe ficava no Panorama sem sessão',
      );

      await _theNextTapOpens(sala, () => _notifier(sala).openTheEntry(chosen));
      closeTheRoom(sala.container);
    },
  );

  group('a resume the network loses goes calmly back to the Choice, and the '
      'entry opened again resumes on its conversation', () {
    for (final stage in const [SalaStage.conversa, SalaStage.ensaio]) {
      test('on a ${stage.name} row', () async {
        final harness = SalaHarness();
        harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
          sessionId: 'sessao-antiga',
          stage: stage,
        );
        final container = harness.container();
        addTearDown(container.dispose);
        final notifier = container.read(salaSessionProvider.notifier);
        SalaSessionState read() => container.read(salaSessionProvider);
        await notifier.abrirEscolha();
        await settle();
        final entry = read().naRoda!.firstWhere((e) => e.pericope == 'P01');
        harness.room.reachable = false;

        unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
        await waitFor(
          'the room to rest on the Choice',
          () => read().stage == SalaStage.escolha && !read().awaitingTheGuide,
          limit: const Duration(seconds: 3),
        );
        expect(read().needsPerson, isFalse);

        harness.room.reachable = true;
        await notifier.abrirEscolha();
        await settle();
        notifier.openTheEntry(entry);
        await waitFor(
          'the resume to land on the conversation',
          () => read().stage == SalaStage.conversa && !read().awaitingTheGuide,
        );

        expect(read().sessionId, 'sessao-antiga');
        expect(harness.room.sessionIds, isEmpty);
      });
    }
  });
}
