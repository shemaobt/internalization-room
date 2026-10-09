import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _a502 = NetworkFailed('HTTP 502');
const _aWhile = Duration(seconds: 1);

class _Check {
  final SalaHarness harness;
  final ProviderContainer container;
  int finishes = 0;

  _Check(this.harness, this.container) {
    harness.room.duranteOVeredito = () => finishes++;
  }

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  Future<void> resting(String why) =>
      waitFor('a retro descansar no círculo $why', () => estado.offline);

  Future<void> finishesReach(int count) =>
      waitFor('o veredito ser pedido $count vezes', () => finishes >= count);
}

Future<_Check> _readyForTheVerdict(SalaHarness harness) async {
  final casa = Directory.systemTemp.createTempSync('sala-veredito');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness.playback
    ..length = const Duration(seconds: 30)
    ..measured = const Duration(seconds: 30);
  final parte1 = KeptScope.parte(1);
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: parte1,
        path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final check = _Check(harness, container);
  await check.sala.abrirEscolha();
  await check.sala.goConversa(pericope: 'P01');
  await waitFor(
    'a tradução retomada pôr a parte no ar',
    () => check.estado.stage == SalaStage.retro,
  );
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução poder pedir o veredito',
    () => check.estado.canFinishBackTranslation,
  );
  return check;
}

void main() {
  test(
    '1: a finish answered 502 is sent once and the room asks no more',
    () async {
      final check = await _readyForTheVerdict(
        SalaHarness(busyCeiling: const Duration(milliseconds: 300)),
      );
      check.harness.room.failFinishWith = _a502;

      await check.sala.finishBackTranslation();
      await check.resting('depois do 502');
      final probes = check.harness.network.checks;
      await settle(_aWhile);

      expect(check.finishes, 1);
      expect(check.harness.network.checks, probes);
      expect(check.estado.offline, isTrue);
    },
  );

  test(
    '2: after a 502 the team\'s tap sends exactly one more finish',
    () async {
      final check = await _readyForTheVerdict(SalaHarness());
      check.harness.room.failFinishWith = _a502;
      await check.sala.finishBackTranslation();
      await check.resting('depois do 502');
      await settle(_aWhile);

      check.sala.retroTap();
      await check.finishesReach(2);
      await check.resting('depois do segundo 502');
      await settle(_aWhile);

      expect(check.finishes, 2);
      expect(check.estado.offline, isTrue);
    },
  );

  test('3: a finish lost on the network is sent once, and the radio\'s return '
      'does not send it', () async {
    final check = await _readyForTheVerdict(SalaHarness());
    check.harness.room.failFinishWith = const NetworkFailed('sem rede');
    check.harness.network.reachable = false;
    await check.sala.finishBackTranslation();
    await check.resting('sem rede');
    await settle(_aWhile);

    check.harness.network.reachable = true;
    check.harness.network.networkComesBack();
    await settle(_aWhile);

    expect(check.finishes, 1);

    check.harness.room.failFinishWith = null;
    check.sala.retroTap();
    await waitFor(
      'o veredito pousar',
      () => check.harness.room.playedByTakeSent.isNotEmpty,
    );
    await settle(_aWhile);

    expect(check.finishes, 2);
    expect(check.harness.room.playedByTakeSent, hasLength(1));
  });

  testWidgets('4: the resting Retro reads «Tocar para tentar de novo»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await pumpSala(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    await sala.goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));
    sala.goEnsaio();
    sala.ensaioTap();
    sala.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    sala.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
    sala.startRetro();
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.at = const Duration(seconds: 10);
    sala.cortarTrecho();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    harness.room.failFinishWith = _a502;

    await sala.finishBackTranslation();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(byLabel('Tocar para tentar de novo'), findsOneWidget);

    closeTheRoom(container);
  });

  test('5: a finish that lands after the tap leaves the room reachable and '
      'speaks the verdict', () async {
    final check = await _readyForTheVerdict(SalaHarness());
    check.harness.room.failFinishWith = _a502;
    await check.sala.finishBackTranslation();
    await check.resting('depois do 502');
    check.harness.room.failFinishWith = null;

    check.sala.retroTap();
    await waitFor(
      'o veredito pousar',
      () => check.harness.room.playedByTakeSent.isNotEmpty,
    );
    await waitFor(
      'a sala sair do pensamento',
      () => check.estado.btPhase != BtPhase.thinking,
    );

    expect(check.harness.room.playedByTakeSent, hasLength(1));
    expect(check.estado.unreachable, isFalse);
  });

  test('6: a team that leaves the passage while the check rests gets the '
      'room\'s own ladder back', () async {
    final check = await _readyForTheVerdict(SalaHarness());
    check.harness.room.failFinishWith = _a502;
    await check.sala.finishBackTranslation();
    await check.resting('depois do 502');
    final probes = check.harness.network.checks;

    check.sala.leaveThePassage();

    await waitFor(
      'a sala voltar a sondar sozinha',
      () => check.harness.network.checks > probes,
    );
  });
}
