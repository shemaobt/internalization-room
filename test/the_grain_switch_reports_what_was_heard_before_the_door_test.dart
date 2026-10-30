import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

const _duasCenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
];

Map<String, Object?> _ouvida(String takeId, int de, int ate, int quanto) => {
  'take_id': takeId,
  'played_ranges': [
    [de, ate],
  ],
  'clip_duration_ms': quanto,
};

/// A passage reopened on its recording home, holding [takes] the room lists as [naSala].
Future<Sala> _reabertaNaCasa(
  List<KeptTake> Function(Directory pasta) takes,
  List<TakeView> naSala,
) async {
  final pasta = Directory.systemTemp.createTempSync('sala-2074');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passageScenes = _duasCenas
    ..room.takes.addAll(naSala);
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: takes(pasta),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await it.sala.abrirEscolha();
  await settle();
  unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
  await waitFor(
    'a casa do ensaio reabrir com as partes',
    () =>
        it.estado.stage == SalaStage.ensaio &&
        it.estado.partes.length == naSala.length,
  );
  await settle();
  return it;
}

String _arquivo(Directory pasta, String nome) =>
    (File('${pasta.path}/$nome.m4a')..writeAsBytesSync([1, 2, 3])).path;

/// A scene home over a joined recording: two parts the join brought in.
Future<Sala> _numaCasaJuntada() => _reabertaNaCasa(
  (pasta) => [
    for (final n in [1, 2])
      KeptTake(
        scopeId: KeptScope.parte(n),
        path: _arquivo(pasta, 'p$n'),
        takeId: 'gravacao-$n',
        origin: 'ensaio-da-cena-$n',
      ),
  ],
  [
    for (final n in [1, 2])
      TakeView(
        takeId: 'gravacao-$n',
        kind: 'ensaio',
        scope: KeptScope.parte(n),
        ordinal: n,
        pass: 1,
        origin: 'ensaio-da-cena-$n',
      ),
  ],
);

/// The whole-passage home: one whole take the room lists.
Future<Sala> _naCasaDaPassagemInteira() => _reabertaNaCasa(
  (pasta) => [
    KeptTake(
      scopeId: KeptScope.whole,
      path: _arquivo(pasta, 'inteiro'),
      takeId: 'gravacao-inteira',
    ),
  ],
  const [
    TakeView(
      takeId: 'gravacao-inteira',
      kind: 'ensaio',
      scope: KeptScope.whole,
    ),
  ],
);

/// Row [cena] played to [ate] and paused there.
Future<void> _ouvirAteOMeio(Sala it, int cena, Duration ate) async {
  it.sala.ouvirACena(cena);
  await theClipOpens(it.harness);
  it.harness.playback.at = ate;
  it.sala.ouvirACena(cena);
  await waitFor('a parte parar', () => it.estado.takePaused);
}

void main() {
  test('on a joined home, a part heard half-way reaches the room before '
      '«gravar a passagem inteira de uma vez» calls the door', () async {
    final it = await _numaCasaJuntada();
    it.harness.playback.length = const Duration(seconds: 8);
    await _ouvirAteOMeio(it, 1, const Duration(seconds: 3));
    final relatos = it.harness.room.listeningReports.length;
    it.harness.room.holdTheGrainSwitch();

    it.sala.recordTheWholePassage();
    await waitFor(
      'o toque armar',
      () => it.estado.armedTap?.phase == BtRecomeco.pronto,
    );
    it.sala.recordTheWholePassage();

    expect(it.harness.room.grainSwitches, hasLength(1));
    expect(
      it.harness.room.listeningReports.skip(relatos),
      [
        [_ouvida('gravacao-1', 0, 3000, 8000)],
      ],
      reason:
          'a troca tirava a parte antes do relato, e o que soou na casa '
          'nunca chegava à sala',
    );
    it.harness.room.finishTheGrainSwitch();
    await waitFor('a troca acabar', () => !it.estado.grainSwitching);
  });

  test(
    'on a home no join touched, a part heard half-way reaches the room before '
    '«Gravar a passagem inteira» calls the door',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      final segunda = it.partes[1].takeId!;
      it.harness.playback.length = partesDoEnsaio[1];
      await _ouvirAteOMeio(it, 2, const Duration(seconds: 3));
      final relatos = it.harness.room.listeningReports.length;
      it.harness.room.holdTheGrainSwitch();

      it.sala.recordTheWholePassageInstead();

      expect(it.harness.room.grainSwitches, hasLength(1));
      expect(it.harness.room.listeningReports.skip(relatos), [
        [_ouvida(segunda, 0, 3000, 8000)],
      ]);
      it.harness.room.finishTheGrainSwitch();
      await waitFor('a troca acabar', () => !it.estado.grainSwitching);
    },
  );

  test('on the whole-passage home, the whole heard half-way reaches the room '
      'before «Gravar cena por cena» calls the door', () async {
    final it = await _naCasaDaPassagemInteira();
    expect(it.estado.recordsTheWhole, isTrue);
    it.harness.playback.length = const Duration(seconds: 12);
    await _ouvirAteOMeio(it, 1, const Duration(seconds: 4));
    final relatos = it.harness.room.listeningReports.length;
    it.harness.room.holdTheGrainSwitch();

    it.sala.recordSceneByScene();

    expect(it.harness.room.grainSwitches, hasLength(1));
    expect(it.harness.room.listeningReports.skip(relatos), [
      [_ouvida('gravacao-inteira', 0, 4000, 12000)],
    ]);
    it.harness.room.finishTheGrainSwitch();
    await waitFor('a troca acabar', () => !it.estado.grainSwitching);
  });

  test('on the grain choice, a part heard on the home before reaches the room '
      'before «A passagem inteira» calls the door', () async {
    final it = await _numaCasaJuntada();
    it.harness.playback.length = const Duration(seconds: 8);
    await _ouvirAteOMeio(it, 2, const Duration(seconds: 5));
    it.sala.leaveTheRecording();
    await waitFor('a conversa voltar', () => it.estado.station is Canvas);
    it.harness.room.holdNextTakesList();
    it.sala.openTheEnsaioFinal();
    await waitFor(
      'a escolha do grão aparecer',
      () => it.estado.ensaioFinalPlan is GrainAsked,
      limit: const Duration(seconds: 12),
    );
    final relatos = it.harness.room.listeningReports.length;
    it.harness.room.holdTheGrainSwitch();

    it.sala.chooseTheGrain(Grain.whole);

    expect(it.harness.room.grainSwitches, hasLength(1));
    expect(it.harness.room.listeningReports.skip(relatos), [
      [_ouvida('gravacao-2', 0, 5000, 8000)],
    ]);
    it.harness.room.finishTheGrainSwitch();
    it.harness.room.finishHeldTakesList();
    await waitFor('a troca acabar', () => !it.estado.grainSwitching);
  });
}
