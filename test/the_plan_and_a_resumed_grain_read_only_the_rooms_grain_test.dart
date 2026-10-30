import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show holdTheSession, settle;

const _held = 'sessao-guardada';
const _oneScene = [Scene(sceneId: 'S1', title: 'A fome em Belém')];

Future<ProviderContainer> _theDotTappedOnAReopenedPassage({
  required List<Scene> scenes,
  List<KeptTake> takes = const [],
  Grain? remembered,
}) async {
  final harness = SalaHarness()
    ..room.passageScenes = scenes
    ..room.openedSessions.add(_held);
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: _held,
      stage: SalaStage.ensaio,
      takes: takes,
      grain: remembered,
    ),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  SalaSessionState state() => container.read(salaSessionProvider);
  await container.read(salaSessionProvider.notifier).openTheRoom();
  await waitFor(
    'the team to land on the session',
    () =>
        state().sessionId == _held &&
        !state().awaitingTheGuide &&
        state().voice == VoiceState.invite,
  );
  await settle();
  container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
  await waitFor(
    'the dot to lead somewhere',
    () =>
        state().ensaioFinalPlan is! PlanAwaited ||
        switch (state().station) {
          Ensaio(step: EnsaioStep.home) => true,
          _ => false,
        },
  );
  return container;
}

KeptTake _aWholeHere() {
  final home = Directory.systemTemp.createTempSync('sala-inteiro-aqui');
  addTearDown(() => home.deleteSync(recursive: true));
  return KeptTake(
    scopeId: KeptScope.whole,
    path: (File('${home.path}/inteiro.m4a')..writeAsBytesSync([1])).path,
  );
}

void main() {
  test(
    'a whole kept only on the tablet over a passage with scenes opens the plan while the room names no grain',
    () async {
      final container = await _theDotTappedOnAReopenedPassage(
        scenes: _oneScene,
        takes: [_aWholeHere()],
      );
      final state = container.read(salaSessionProvider);
      expect(
        state.station,
        isA<Ensaio>().having((it) => it.step, 'step', EnsaioStep.plan),
        reason:
            'o inteiro guardado só no tablet lia-se como o grão em vigor e abria a casa da '
            'passagem inteira por cima do plano; o grão dela é só o da sala',
      );
      expect(state.ensaioFinalPlan, isA<PlanRead>());
    },
  );

  test(
    'a grain remembered on the tablet is let go when the room names none, and the choice shows',
    () async {
      final container = await _theDotTappedOnAReopenedPassage(
        scenes: const [],
        remembered: Grain.whole,
      );
      final state = container.read(salaSessionProvider);
      expect(
        state.station,
        isA<Ensaio>().having((it) => it.step, 'step', EnsaioStep.plan),
        reason:
            'o grão lembrado no ponto de retomada abria a casa da passagem inteira com a '
            'listagem da sala lida e sem grão nenhum; a dela mostra a escolha',
      );
      expect(state.ensaioFinalPlan, isA<GrainAsked>());
      expect(state.grainInForce, isNull);
    },
  );

  test(
    'a whole remembered on the tablet over a passage with scenes opens the plan while the room names no grain',
    () async {
      final container = await _theDotTappedOnAReopenedPassage(
        scenes: _oneScene,
        remembered: Grain.whole,
      );
      final state = container.read(salaSessionProvider);
      expect(
        state.station,
        isA<Ensaio>().having((it) => it.step, 'step', EnsaioStep.plan),
        reason:
            'o inteiro lembrado no ponto de retomada chegava ao braço do plano como o grão '
            'em vigor e abria a casa da passagem inteira; sem grão na sala a dela abre o plano',
      );
      expect(state.ensaioFinalPlan, isA<PlanRead>());
    },
  );

  test(
    'a clear of the grain lays the frases under no grain, never under the one just cleared',
    () {
      final antes = SalaSessionState(
        grainInForce: Grain.whole,
        keptTakes: const [_inteiro],
        btTrechos: [_trecho('trecho-do-inteiro', 0)],
      );
      final depois = antes.copyWith(
        keptTakes: [_inteiro, _parte(1)],
        clearGrainInForce: true,
      );
      expect(
        depois.btTrechos,
        isEmpty,
        reason:
            'as frases eram recolocadas sob o grão que a mesma chamada limpava, e a frase '
            'do inteiro passava a ler «parte 1» com o grão já nulo',
      );
    },
  );
}

const _inteiro = KeptTake(
  scopeId: KeptScope.whole,
  path: 'inteiro.m4a',
  takeId: 'gravacao-inteira',
);

KeptTake _parte(int n) => KeptTake(
  scopeId: KeptScope.parte(n),
  path: 'parte-$n.m4a',
  takeId: 'gravacao-$n',
);

Trecho _trecho(String nome, int parte) => Trecho(
  segmentId: nome,
  takeId: 'gravacao-de-$nome',
  parte: parte,
  from: Duration.zero,
  to: const Duration(seconds: 4),
  contado: true,
  lugarFrom: Duration.zero,
  lugarTo: const Duration(seconds: 4),
);
