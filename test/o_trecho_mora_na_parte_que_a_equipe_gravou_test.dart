import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _parteLen = Duration(seconds: 10);

/// The name the server holds for a recording this tablet has no part for: a session told
/// back before the room stopped assembling passages still answers with one.
const _deFora = 'gravacao-de-fora';

/// The room's reading of a telling-back of three parts, with the two stretches of part 2
/// addressed to a recording this tablet does not hold.
const _contadoDeFora = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-1',
      startsMs: 0,
      endsMs: 10000,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: _deFora,
      startsMs: 0,
      endsMs: 6000,
    ),
    SegmentView(
      segmentId: 'trecho-3',
      takeId: _deFora,
      startsMs: 6000,
      endsMs: 10000,
    ),
    SegmentView(
      segmentId: 'trecho-4',
      takeId: 'gravacao-3',
      startsMs: 0,
      endsMs: 10000,
    ),
  ],
);

/// The same telling-back, every stretch on a recording this tablet holds.
const _contadoDaqui = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-1',
      startsMs: 0,
      endsMs: 10000,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: 'gravacao-2',
      startsMs: 0,
      endsMs: 10000,
    ),
  ],
);

class _Retomada {
  final SalaHarness harness;
  final ProviderContainer container;

  /// The files the team's own recordings are in, in the order the parts were recorded.
  final List<String> gravadas;

  _Retomada(this.harness, this.container, this.gravadas);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);
}

/// A tablet closed part-way through a telling-back and opened again on the same passage,
/// with the team's own recordings still on disk.
Future<_Retomada> _reabrir(
  SalaHarness harness, {
  required BackTranslationProgress contado,
  int partes = 3,
  List<TakeView> naSala = const [],
  RoomFailure? semLista,
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-trecho-na-parte');
  addTearDown(() => casa.deleteSync(recursive: true));
  final gravadas = [
    for (var n = 1; n <= partes; n++)
      (File('${casa.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path,
  ];
  for (final gravada in gravadas) {
    harness.playback.lengths[gravada] = _parteLen;
  }
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (var n = 1; n <= partes; n++)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: gravadas[n - 1],
          takeId: 'gravacao-$n',
        ),
    ],
  );
  harness.room
    ..retroSoFar = contado
    ..takes.addAll(naSala)
    ..failTakesWith = semLista;

  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  await sala.goConversa(pericope: 'P01');
  await settle();
  return _Retomada(harness, container, gravadas);
}

/// Hear the rehearsal out to its end, crossing every boundary, so *terminei* lights.
Future<void> _ouvirAteOFim(_Retomada it) async {
  while (!it.estado.btClipEnded) {
    it.harness.playback
      ..length = _parteLen
      ..at = _parteLen
      ..finishPlayback();
    await waitFor(
      'a parte no ar acabar',
      () => it.estado.btClipEnded || it.estado.btParteFronteira,
    );
    if (it.estado.btClipEnded) break;
    it.sala.ouvirGravacao();
    await waitFor(
      'a parte seguinte entrar no ar',
      () => !it.estado.btParteFronteira,
    );
  }
}

Trecho _trecho(_Retomada it, String nome) =>
    it.estado.btTrechos.firstWhere((trecho) => trecho.segmentId == nome);

void main() {
  test(
    'um trecho numa gravação que o tablet não tem mora na sua parte',
    () async {
      final harness = SalaHarness();
      final it = await _reabrir(
        harness,
        contado: _contadoDeFora,
        naSala: const [
          TakeView(takeId: _deFora, scope: 'composed', ordinal: 2),
        ],
      );
      await waitFor(
        'os trechos da gravação de fora caírem na sua parte',
        () => _trecho(it, 'trecho-2').parte == 1,
      );

      expect(
        [
          for (final nome in ['trecho-2', 'trecho-3'])
            [
              _trecho(it, nome).parte,
              _trecho(it, nome).lugarFrom.inMilliseconds,
              _trecho(it, nome).lugarTo.inMilliseconds,
            ],
        ],
        [
          [1, 0, 6000],
          [1, 6000, 10000],
        ],
        reason:
            'a sala respondeu que a gravação que estes dois fatiam responde '
            'pela parte 2: eles moram na parte 2, nos segundos que a sala disse, '
            'e tocam o lugar em que moram (ADR 0021)',
      );
      expect(
        it.harness.room.calls.where((chamada) => chamada == 'takesOf').length,
        1,
        reason: 'a retomada pergunta a lista das gravações uma vez só',
      );

      expect(
        it.harness.room.clipsFetched,
        isEmpty,
        reason:
            'a equipe nunca gravou o arquivo que o servidor montava, e '
            'nada é baixado para colocar um trecho no lugar dele',
      );
      expect(
        [
          for (final take in it.estado.keptTakes)
            '${take.scopeId}|${take.path}|${take.takeId}',
        ],
        [
          for (var n = 1; n <= 3; n++)
            '${KeptScope.parte(n)}|${it.gravadas[n - 1]}|gravacao-$n',
        ],
        reason:
            'as partes continuam sendo as gravações da equipe, com os mesmos '
            'arquivos e os mesmos nomes',
      );
    },
  );

  test(
    'ouvir esse trecho toca a gravação da própria parte no seu lugar',
    () async {
      final harness = SalaHarness()
        ..room.verdictChecked = false
        ..room.verdictHasFinding = true
        ..room.verdictFindingSegmentId = 'trecho-2';
      final it = await _reabrir(
        harness,
        contado: _contadoDeFora,
        naSala: const [
          TakeView(takeId: _deFora, scope: 'composed', ordinal: 2),
        ],
      );
      await waitFor(
        'os trechos da gravação de fora caírem na sua parte',
        () => _trecho(it, 'trecho-2').parte == 1,
      );
      final daParteDois = it.gravadas[1];

      await _ouvirAteOFim(it);
      await it.sala.finishBackTranslation();
      await waitFor(
        'a sala abrir os achados',
        () => it.estado.btPhase == BtPhase.findings,
      );

      it.sala.ouvirOTrechoEATraducao();
      await waitFor('o trecho apontado tocar', () => it.estado.btTrechoTocando);

      expect(
        it.harness.playback.played.last,
        daParteDois,
        reason:
            'a voz materna do trecho é a gravação que a equipe fez da '
            'parte 2, e não um arquivo que o servidor montou',
      );
      expect(
        it.harness.playback.ranges.last,
        '0-6000',
        reason:
            'tocado nos segundos que a sala deu ao trecho dentro da '
            'gravação, que é o lugar em que ele mora',
      );
    },
  );

  test('sem a lista das gravações o trecho fica onde a leitura o põe e a sala '
      'não para', () async {
    final harness = SalaHarness();
    final it = await _reabrir(
      harness,
      contado: _contadoDeFora,
      semLista: const NetworkFailed('sem rede'),
    );
    await settle();

    expect(
      it.estado.stage,
      SalaStage.retro,
      reason: 'a retomada chega na tradução de volta mesmo assim',
    );
    expect(
      it.estado.needsPerson,
      isFalse,
      reason:
          'uma lista que não respondeu não é motivo para chamar '
          'alguém: a equipe continua contando',
    );
    expect(
      it.harness.room.calls,
      contains('takesOf'),
      reason: 'a lista foi pedida: sem isso o caso não mede recusa nenhuma',
    );
    expect(
      [for (final trecho in it.estado.btTrechos) trecho.segmentId],
      ['trecho-1', 'trecho-2', 'trecho-3', 'trecho-4'],
      reason: 'nenhum trecho some do colar por causa da lista',
    );
    expect(
      [
        for (final nome in ['trecho-2', 'trecho-3']) _trecho(it, nome).parte,
      ],
      [-1, -1],
      reason:
          'sem a lista nada os coloca, e a leitura não os inventa numa '
          'parte: uma banda sobre a parte errada mente à equipe sobre onde a '
          'fala dela está',
    );
  });

  test('uma gravação sem número não coloca nada', () async {
    final harness = SalaHarness();
    final it = await _reabrir(
      harness,
      contado: _contadoDeFora,
      naSala: const [TakeView(takeId: _deFora, scope: 'composed')],
    );
    await settle();

    expect(it.estado.stage, SalaStage.retro);
    expect(
      it.harness.room.calls,
      contains('takesOf'),
      reason:
          'a lista foi pedida e respondeu: sem isso o caso não mede a '
          'gravação sem número, mede a colocação que nunca rodou',
    );
    expect(
      it.estado.needsPerson,
      isFalse,
      reason: 'uma gravação que a sala não numerou não para ninguém',
    );
    expect(
      [for (final trecho in it.estado.btTrechos) trecho.segmentId],
      ['trecho-1', 'trecho-2', 'trecho-3', 'trecho-4'],
    );
    expect(
      [
        for (final nome in ['trecho-2', 'trecho-3']) _trecho(it, nome).parte,
      ],
      [-1, -1],
      reason:
          'uma gravação que a sala não numerou não diz por qual parte ela '
          'responde, e adivinhar uma põe a banda sobre a fala de outra parte',
    );
    expect(
      _trecho(it, 'trecho-1').parte,
      0,
      reason: 'os trechos das gravações que o tablet tem não se mexem',
    );
    expect(_trecho(it, 'trecho-4').parte, 2);
  });

  test(
    'uma retomada cujas gravações o tablet tem não pergunta nada à sala',
    () async {
      final harness = SalaHarness();
      final it = await _reabrir(harness, contado: _contadoDaqui, partes: 2);
      await settle();

      expect(
        it.harness.room.calls,
        isNot(contains('takesOf')),
        reason:
            'toda gravação que os trechos nomeiam está neste tablet: não '
            'há o que perguntar',
      );
      expect([for (final trecho in it.estado.btTrechos) trecho.parte], [0, 1]);
    },
  );

  test('a resposta da sala pode ainda trazer composed_take_id', () {
    final trocado = TellingAgain.fromJson({
      'segments': [
        {
          'segment_id': 'trecho-1',
          'take_id': 'gravacao-1',
          'starts_ms': 0,
          'ends_ms': 6000,
        },
      ],
      'captured': true,
      'composed_take_id': 'gravacao-de-fora',
    });

    expect(
      trocado.segments,
      hasLength(1),
      reason:
          'uma chave que este tablet não lê mais não estraga a resposta '
          'de um servidor que ainda a manda',
    );
    expect(trocado.segments.first.segmentId, 'trecho-1');
    expect(trocado.needsPerson, isFalse);
  });

  test('o endereço do áudio de uma gravação', () {
    expect(
      RoomRepository.takeAudioUrl('sessao-1', 'gravacao-1'),
      endsWith('/sessions/sessao-1/takes/gravacao-1/audio'),
    );
  });
}
