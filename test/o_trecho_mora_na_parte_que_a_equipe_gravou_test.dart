import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'support/temp.dart';

const _parteLen = Duration(seconds: 10);

/// A telling-back of two parts, every stretch on a recording this tablet holds.
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
}) async {
  final casa = aTempDir('sala-trecho-na-parte');
  final gravadas = [
    for (var n = 1; n <= partes; n++)
      (File('${casa.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path,
  ];
  for (final gravada in gravadas) {
    harness.playback.lengths[gravada] = _parteLen;
  }
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  harness.room.retroSoFar = contado;

  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  await sala.goConversa(book: 'Ruth', pericope: 'P01');
  await settle();
  return _Retomada(harness, container, gravadas);
}

void main() {
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

  for (final listaPorUltimo in [true, false]) {
    test('a stretch on a recording this tablet lacks keeps its part whatever '
        'order the two reads land in (listing last: $listaPorUltimo)', () async {
      final harness = SalaHarness();
      harness.room
        ..openedSessions.add('sessao-antiga')
        ..takes.add(
          const TakeView(
            takeId: 'de-fora',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        )
        ..listeningUnheardTakeIds = const [];
      if (listaPorUltimo) harness.room.holdNextTakesList();
      final it = await _reabrir(
        harness,
        partes: 2,
        contado: BackTranslationProgress(
          segments: [
            _contadoDaqui.segments.first,
            const SegmentView(
              segmentId: 'trecho-2',
              takeId: 'de-fora',
              startsMs: 0,
              endsMs: 10000,
            ),
          ],
          checked: true,
        ),
      );
      it.sala.openTheEnsaioFinal();
      await settle();
      it.sala.startRetro();
      await settle();
      if (listaPorUltimo) harness.room.finishHeldTakesList();
      await settle();

      expect(
        [for (final trecho in it.estado.btTrechos) trecho.parte],
        [0, 1],
        reason:
            'a listagem que chegava depois da entrada não punha o trecho na parte',
      );
    });
  }

  test('a listing of the passage the team left lands in the next one with '
      'none of its stretches', () async {
    final harness = SalaHarness();
    harness.room
      ..takes.add(
        const TakeView(
          takeId: 'velha-de-fora',
          kind: 'ensaio',
          scope: 'inteiro',
        ),
      )
      ..holdNextTakesList();
    final it = await _reabrir(
      harness,
      partes: 2,
      contado: BackTranslationProgress(
        segments: [_contadoDaqui.segments.first],
        stale: const [
          SegmentView(
            segmentId: 'velho',
            takeId: 'velha-de-fora',
            startsMs: 0,
            endsMs: 10000,
            frase: 1,
          ),
        ],
      ),
    );
    harness.room.retroSoFar = null;
    await it.sala.abrirEscolha();
    await settle();
    await it.sala.goConversa(book: 'Ruth', pericope: 'P02');
    await settle();
    harness.room.finishHeldTakesList();
    await settle();

    expect(
      it.estado.btTrechosRegravados,
      isEmpty,
      reason:
          'a listagem da passagem deixada gravava os trechos dela na seguinte',
    );
  });

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
