import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show intoTheBackTranslation, settle;
import 'support/temp.dart';

const _gravacao = 'gravacao-1';

const _traduzidos = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: _gravacao,
      startsMs: 12000,
      endsMs: 30000,
    ),
  ],
);

/// A tablet that was closed part-way and is opened again on the same passage.
///
/// The rehearsal is on disk, the ledger says where they were, and the room answers with
/// whatever [contado] says it is holding for that session. With [semAudio] the ledger
/// still names the rehearsal and the tablet no longer has it. With [throughTheHome] the
/// team walks from the conversation it lands on, through the recording home, into the
/// telling-back.
Future<ProviderContainer> _reopen(
  SalaHarness harness, {
  required SalaStage parouEm,
  BackTranslationProgress contado = const BackTranslationProgress(),
  bool semAudio = false,
  bool throughTheHome = false,
}) async {
  final gravada = File('${aTempDir('sala-retro-retomada').path}/p1.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  if (semAudio) gravada.deleteSync();
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: _gravacao,
      ),
    ],
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  if (throughTheHome) {
    await intoTheBackTranslation(
      notifier,
      () => container.read(salaSessionProvider),
    );
  }
  await settle();
  return container;
}

void main() {
  test(
    'the stretches that come back are the ones the room is holding',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        contado: _traduzidos,
      );

      final state = container.read(salaSessionProvider);
      expect(
        [for (final trecho in state.btTrechos) '${trecho.from}-${trecho.to}'],
        ['0:00:00.000000-0:00:12.000000', '0:00:12.000000-0:00:30.000000'],
      );
      expect(
        [for (final trecho in state.btTrechos) trecho.takeId],
        [_gravacao, _gravacao],
        reason: 'cada trecho volta amarrado à gravação que ele fatia',
      );
    },
  );

  test('a telling-back the room already checked does not start over', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      throughTheHome: true,

      harness,
      parouEm: SalaStage.retro,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 30000,
          ),
        ],
        checked: true,
      ),
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(
      state.btPhase,
      BtPhase.conferida,
      reason:
          'a conferência já passou; pedir os trechos de novo é cobrar da '
          'equipe um trabalho que o servidor já tem',
    );
    expect(state.voice, VoiceState.done);
  });

  test(
    'a halt on the way into a telling-back with nothing told still lets the part '
    'play, as hers',
    () async {
      final harness = SalaHarness();
      harness.playback.holdNextMeasurement();

      final container = await _reopen(
        throughTheHome: true,
        harness,
        parouEm: SalaStage.retro,
      );
      await waitFor(
        'a entrada medir as partes',
        () => harness.playback.measurements.isNotEmpty,
      );
      container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      harness.playback.finishHeldMeasurement();
      await waitFor(
        'a parte entrar no ar',
        () => harness.playback.played.isNotEmpty,
      );

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.retro);
      expect(state.needsPerson, isFalse);
      expect(
        harness.playback.played,
        isNotEmpty,
        reason: 'a parada na entrada retirava o som, e o Drafting dela toca',
      );
    },
  );

  test(
    'a checked answer with no stretches at all opens the passage instead of stalling',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        contado: const BackTranslationProgress(checked: true),
        semAudio: true,
      );

      await settle(const Duration(seconds: 2));

      expect(
        harness.room.calls,
        contains('openSession'),
        reason:
            'conferida sem trecho nenhum é uma resposta que se contradiz — '
            'a conferência é sobre o que foi contado. Sem trecho não há retro '
            'para retomar nem nada que a equipe possa aprovar, então a sala '
            'abre a passagem como qualquer outra: é a porta de onde se sai. '
            'Parada na conversa, ela ficava dois minutos calada até o vigia '
            'chamar uma pessoa',
      );
      expect(
        container.read(salaSessionProvider).stage,
        isNot(SalaStage.fim),
        reason:
            'e não fecha: dar por terminada uma passagem que ninguém '
            'aprovou é exatamente o que este gesto existe para não deixar '
            'acontecer',
      );
    },
  );

  test(
    'a telling-back the team can pick back up throws nothing away',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        throughTheHome: true,

        harness,
        parouEm: SalaStage.retro,
        contado: _traduzidos,
      );

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.retro,
        reason:
            'os trechos que o servidor guarda são os que a equipe está '
            'voltando para continuar, e descartá-los é mandar traduzir de novo '
            'o que já estava contado',
      );
      expect(container.read(salaSessionProvider).btTrechos, hasLength(2));
    },
  );

  test(
    'telling one more stretch back carries on from the ones already told',
    () async {
      final harness = SalaHarness();
      final container = await _reopen(
        throughTheHome: true,

        harness,
        parouEm: SalaStage.retro,
        contado: _traduzidos,
      );
      final notifier = container.read(salaSessionProvider.notifier);

      harness.playback.at = const Duration(seconds: 44);
      notifier.retroTap();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await settle();

      expect(
        harness.room.chunkSpans,
        ['30000-44000'],
        reason:
            'recomeçar do zero manda um segundo conjunto de trechos para a '
            'mesma passada, e o analista recebe a passagem contada duas vezes',
      );
      expect(
        harness.room.chunkTakes,
        [_gravacao],
        reason: 'e continua sendo a mesma gravação que ele fatia',
      );
    },
  );

  test('cutting over ground already told back tells the room nothing', () async {
    final harness = SalaHarness();
    final container = await _reopen(
      throughTheHome: true,

      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    notifier.retroTap();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(
      harness.room.chunkSpans,
      isEmpty,
      reason:
          'nenhum gesto da retro nasce atrás do cursor — só a mão que '
          'escreve a posição nesta linha chega a este estado —, mas a posição '
          'vem do player, e um player que responda de trás manda um trecho '
          'que termina antes de começar',
    );

    harness.playback.at = const Duration(seconds: 44);
    notifier.retroTap();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await settle();

    expect(
      harness.room.chunkSpans,
      ['30000-44000'],
      reason:
          'o corte recusado não pode arrastar o cursor para trás e sujar '
          'todo trecho que vier depois dele',
    );
  });
}
