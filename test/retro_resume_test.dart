import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([
  Duration delay = const Duration(milliseconds: 120),
]) async {
  await Future<void>.delayed(delay);
}

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

/// The room's own recording of a rehearsal of one part, as its listing answers.
const _naSala = [
  TakeView(takeId: _gravacao, kind: 'ensaio', scope: 'parte-1', ordinal: 1),
];

/// A tablet that was closed part-way and is opened again on the same passage.
///
/// The rehearsal is on disk, the ledger says where they were, and the room answers with
/// whatever [contado] says it is holding for that session. With [semAudio] the ledger
/// still names the rehearsal and the tablet no longer has it, and [naSala] is what the
/// room answers when it is asked for the recordings it holds.
Future<ProviderContainer> _reopen(
  SalaHarness harness, {
  required SalaStage parouEm,
  BackTranslationProgress contado = const BackTranslationProgress(),
  bool semAudio = false,
  List<TakeView> naSala = const [],
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-retro-retomada').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  if (semAudio) gravada.deleteSync();
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
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
  harness.room
    ..retroSoFar = contado
    ..takes.addAll(naSala);
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
      contado: _traduzidos,
    );

    final state = container.read(salaSessionProvider);
    expect(
      state.stage,
      SalaStage.retro,
      reason:
          'a equipe voltava ao ensaio e gravava a passagem inteira de '
          'novo, e o servidor ficava com duas gravações e duas retros',
    );
    expect(state.btTrechos, hasLength(2));
  });

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
    'with no stretch on the room, the telling-back is still where they land',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(harness, parouEm: SalaStage.retro);
      await waitFor(
        'a primeira parte ir ao ar',
        () => harness.playback.played.isNotEmpty,
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.retro,
        reason:
            'a equipe parou na retro: devolvê-la ao ensaio porque nada '
            'foi contado ainda é mandá-la gravar de novo o que já gravou',
      );
      expect(state.btPhase, BtPhase.playing);
      expect(
        state.voice,
        VoiceState.invite,
        reason: 'e o convite de pé: a equipe tem a palavra',
      );
      expect(
        state.btTrechos,
        isEmpty,
        reason: 'e sem nada contado, não há faixa nenhuma no cordão',
      );
      expect(
        harness.playback.played.last,
        state.partes.first.path,
        reason: 'o chão não contado começa na primeira parte',
      );
      expect(
        harness.playback.playedFrom.last,
        Duration.zero,
        reason: 'e do começo dela, que é onde o chão não contado abre',
      );
    },
  );

  test(
    'a telling-back resumed without its rehearsal fetches the rehearsal back',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        contado: _traduzidos,
        semAudio: true,
        naSala: _naSala,
      );
      await waitFor(
        'a retro voltar com o ensaio da sala',
        () => container.read(salaSessionProvider).partes.isNotEmpty,
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.retro,
        reason:
            'a equipe para no gesto que falta: mandada à conversa, ela '
            'contava a passagem inteira de novo sobre trechos que a sessão '
            'ainda guardava, e o analista recebia os velhos concatenados com '
            'os novos',
      );
      expect(
        [for (final take in state.partes) take.takeId],
        [_gravacao],
        reason: 'o ensaio que a sala guarda volta para o tablet que o perdeu',
      );
      expect(state.btTrechos, hasLength(2));
    },
  );

  test(
    'a telling-back nobody had told into yet comes back with the rehearsal the room holds',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        semAudio: true,
        naSala: _naSala,
      );
      await waitFor(
        'o ensaio voltar da sala e a primeira parte ir ao ar',
        () => harness.playback.played.isNotEmpty,
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.retro,
        reason:
            'a equipe parou na retro, e o ensaio que a sala guarda é dela: '
            'mandá-la ao ensaio é mandá-la gravar tudo de novo',
      );
      expect(
        [for (final take in state.partes) take.takeId],
        [_gravacao],
        reason: 'e o que volta é a gravação da equipe, não uma fila vazia',
      );
      expect(
        harness.room.pericopesAsked,
        isEmpty,
        reason: 'nada aqui pede sessão nova: a sessão da equipe está de pé',
      );
      expect(harness.playback.played.last, state.partes.first.path);
      expect(
        harness.playback.playedFrom.last,
        Duration.zero,
        reason: 'o chão não contado abre no começo da primeira parte',
      );
    },
  );

  test(
    'a halt on the way into a telling-back with nothing told withholds the sound',
    () async {
      final harness = SalaHarness()..room.serverStatus = 'needs_person';

      final container = await _reopen(harness, parouEm: SalaStage.retro);
      await waitFor(
        'a sala parar e a entrada terminar de medir as partes',
        () =>
            container.read(salaSessionProvider).needsPerson &&
            container.read(salaSessionProvider).btFimDasPartesMs.isNotEmpty,
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.retro,
        reason:
            'a parada não muda a estação: quem vier atender encontra a '
            'equipe onde ela parou',
      );
      expect(state.voice, VoiceState.needsPerson);
      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'uma sala parada retira o som e nada mais (ADR 0029)',
      );
      expect(harness.playback.played, isEmpty);
    },
  );

  test(
    'a checked answer with no stretch lands on the approval over the rehearsal it has',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        contado: const BackTranslationProgress(checked: true),
      );
      await settle(const Duration(seconds: 2));

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.retro,
        reason:
            'a conferência é o gesto que falta, e mandar a equipe gravar '
            'ou contar de novo é tirar dela a aprovação que ninguém deu',
      );
      expect(state.btPhase, BtPhase.conferida);
      expect(state.voice, VoiceState.done);
      expect(
        state.btTrechos,
        isEmpty,
        reason:
            'a sala não guarda trecho nenhum, e inventar um seria dizer à '
            'equipe que ela contou o que não contou',
      );
      expect(
        harness.room.pericopesAsked,
        isEmpty,
        reason: 'a sessão conferida é a que a aprovação vai fechar',
      );
      expect(
        harness.playback.played,
        isEmpty,
        reason:
            'e a conferida não toca nada sozinha: a última audição é um '
            'gesto da equipe',
      );
    },
  );

  test(
    'a passage the room already checked comes back to the approval, not to a close',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
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
        semAudio: true,
        naSala: _naSala,
      );
      final notifier = container.read(salaSessionProvider.notifier);

      await settle(const Duration(seconds: 2));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.retro,
        reason:
            'a equipe volta ao gesto que falta — deixá-la na conversa é '
            'mandá-la gravar e contar tudo de novo, e fechar sozinho é tirar '
            'dela a aprovação que ninguém deu ainda',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
      expect(
        harness.finished.done,
        isNot(contains('Ruth/P01')),
        reason: 'e a passagem não está feita: quem a fecha é a aprovação',
      );
      expect(
        harness.emAberto.rows,
        contains('Ruth/P01'),
        reason: 'então o ponto de retomada continua de pé, para a próxima vez',
      );
      expect(
        container.read(salaSessionProvider).partes,
        hasLength(1),
        reason:
            'esta é a porta em que o ensaio não está mais no tablet, e a '
            'sala ainda o guarda: a equipe recebe de volta a própria gravação',
      );

      notifier.ouvirGravacao();
      await settle();

      expect(
        harness.playback.played.last,
        container.read(salaSessionProvider).partes.first.path,
        reason:
            'e a última audição que a aprovação convida tem o que tocar: '
            'antes o botão estava na tela sobre o silêncio',
      );

      await notifier.aprovarRascunhoFinal();
      await settle(const Duration(seconds: 2));

      expect(
        harness.room.releasesAsked,
        ['sessao-antiga'],
        reason: 'a aprovação vale para a sessão que a equipe retomou',
      );
      expect(container.read(salaSessionProvider).stage, SalaStage.fim);
      expect(harness.finished.done, contains('Ruth/P01'));
      expect(harness.emAberto.rows, isNot(contains('Ruth/P01')));
    },
  );

  test(
    'a passage checked and picked back up over its own recording lands on the approval too',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
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

      await settle(const Duration(seconds: 2));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.retro,
        reason:
            'a outra porta da retomada — a que encontra o ensaio no tablet '
            '— tem de pousar no mesmo lugar: duas portas para a mesma passagem '
            'não podem discordar sobre se ela acabou',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
      expect(
        container.read(salaSessionProvider).partes,
        isNotEmpty,
        reason: 'e com o ensaio de pé, que é o que a última audição pede',
      );
      expect(harness.finished.done, isNot(contains('Ruth/P01')));

      container.read(salaSessionProvider.notifier).ouvirGravacao();
      await settle();

      expect(
        harness.playback.played,
        isNotEmpty,
        reason:
            'a última audição que a fala do veredito convida tem de valer '
            'também aqui: a sala retomada nunca pôs parte nenhuma no ar, então '
            'mandar o tocador continuar é acender o halo sobre o silêncio',
      );
      expect(
        harness.playback.played.last,
        container.read(salaSessionProvider).partes.first.path,
      );
      expect(
        harness.playback.playedFrom.last,
        Duration.zero,
        reason: 'e do começo, como do outro lado da porta',
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
      expect(harness.finished.done, isNot(contains('Ruth/P01')));
    },
  );

  test(
    'a telling-back the team can pick back up throws nothing away',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
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
    'a team that stopped at the rehearsal still lands on the rehearsal',
    () async {
      final harness = SalaHarness();

      final container = await _reopen(
        harness,
        parouEm: SalaStage.ensaio,
        contado: _traduzidos,
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.ensaio,
        reason:
            'o ponto de retomada é quem diz o estágio; trechos no servidor '
            'não arrastam para a retro quem parou antes dela',
      );
      expect(state.ensaio, EnsaioStatus.idle);
    },
  );

  test(
    'telling one more stretch back carries on from the ones already told',
    () async {
      final harness = SalaHarness();
      final container = await _reopen(
        harness,
        parouEm: SalaStage.retro,
        contado: _traduzidos,
      );
      final notifier = container.read(salaSessionProvider.notifier);

      harness.playback.at = const Duration(seconds: 44);
      notifier.cortarTrecho();
      await settle();
      notifier.retroTap();
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
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    notifier.cortarTrecho();
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
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
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
