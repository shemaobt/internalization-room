import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

const _contados = BackTranslationProgress(
  trechos: [
    Trecho(index: 1, from: Duration.zero, to: Duration(seconds: 12)),
    Trecho(index: 2, from: Duration(seconds: 12), to: Duration(seconds: 30)),
  ],
  passes: [1, 2],
);

/// A tablet that was closed part-way and is opened again on the same passage.
///
/// The rehearsal is on disk, the ledger says where they were, and the room answers with
/// whatever [contado] says it is holding for that session.
Future<ProviderContainer> _reopen(
  SalaHarness harness, {
  required SalaStage parouEm,
  BackTranslationProgress contado = const BackTranslationProgress(),
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-retro-retomada').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: [KeptTake(scopeId: KeptScope.parte(1), path: gravada.path)],
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

void main() {
  test('a team that stopped telling back is telling back again', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _contados,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro,
        reason: 'a equipe voltava ao ensaio e gravava a passagem inteira de '
            'novo, e o servidor ficava com duas gravações e duas retros');
    expect(state.btTrechos, hasLength(2));
  });

  test('the stretches that come back are the ones the room is holding', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _contados,
    );

    final state = container.read(salaSessionProvider);
    expect(
      [for (final trecho in state.btTrechos) '${trecho.from}-${trecho.to}'],
      ['0:00:00.000000-0:00:12.000000', '0:00:12.000000-0:00:30.000000'],
    );
    expect(state.btChunkPasses, [1, 2]);
  });

  test('a telling-back the room already checked does not start over', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: const BackTranslationProgress(
        trechos: [
          Trecho(index: 1, from: Duration.zero, to: Duration(seconds: 30)),
        ],
        passes: [1],
        checked: true,
      ),
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btPhase, BtPhase.conferida,
        reason: 'a conferência já passou; pedir os trechos de novo é cobrar da '
            'equipe um trabalho que o servidor já tem');
    expect(state.voice, VoiceState.done);
  });

  test('with no stretch on the room, the rehearsal is still where they land',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(harness, parouEm: SalaStage.retro);

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'não há retro para retomar, e inventar uma seria pior que '
            'refazer o ensaio');
    expect(state.btTrechos, isEmpty);
  });

  test('a team that stopped at the rehearsal still lands on the rehearsal',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.ensaio,
      contado: _contados,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'o ponto de retomada é quem diz o estágio; trechos no servidor '
            'não arrastam para a retro quem parou antes dela');
    expect(state.ensaio, EnsaioStatus.idle);
  });

  test('telling one more stretch back carries on from the ones already told',
      () async {
    final harness = SalaHarness();
    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _contados,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 44);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['30000-44000'],
        reason: 'recomeçar do zero manda um segundo conjunto de trechos para a '
            'mesma passada, e o analista recebe a passagem contada duas vezes');
  });

  test('cutting over ground already told back tells the room nothing', () async {
    final harness = SalaHarness();
    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _contados,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, isEmpty,
        reason: 'o ensaio volta a tocar do começo enquanto o corte já está aos '
            '30s, e um trecho que termina antes de começar sai daí');

    harness.playback.at = const Duration(seconds: 44);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['30000-44000'],
        reason: 'o corte recusado não pode arrastar o cursor para trás e sujar '
            'todo trecho que vier depois dele');
  });
}
