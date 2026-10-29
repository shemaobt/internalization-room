import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

List<int> _apontados(ProviderContainer container) {
  final sessao = container.read(salaSessionProvider);
  return [
    for (final (lugar, trecho) in sessao.btTrechos.indexed)
      if (trecho.segmentId != null &&
          trecho.segmentId == sessao.btFindingSegmentId)
        lugar,
  ];
}

void _oTrechoEsperaOConserto(ProviderContainer container, {String? reason}) {
  final sessao = container.read(salaSessionProvider);
  expect(sessao.btPhase, isNot(BtPhase.capturing), reason: reason);
  expect(
    sessao.btTraducaoPendente,
    anyOf(isNull, sessao.btTraducaoEmprestada),
    reason: reason,
  );
  expect(_apontados(container), [0], reason: reason);
}

/// A team standing at the question, with a finding on the first of two stretches.
///
/// The kind is scenery, not subject: nothing here reads it, and swapping it for any other
/// leaves every case as it is. What every case needs is only a finding that names a
/// stretch, and a correction route out of it.
Future<ProviderContainer> _pumpToPergunta(
  WidgetTester tester, {
  Duration? takeLandsInRealTime,
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
    ..room.verdictFindingSegmentId = 'trecho-1'
    ..room.takeLandsInRealTime = takeLandsInRealTime;
  _harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = _notifier(container);
  await sala.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.gravarACena(1);
  sala.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    sala.retroTap();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// A correction the room made nothing of.
///
/// This is what leaves the pointer naming a stretch that is still there: no version was
/// written, so no name was retired. A correction that lands retires the name it replaces
/// and the pointer goes stale on its own, which is why the whole defect only shows after a
/// correction that did not take.
Future<void> _consertoQueNaoPegou(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _harnessDaVez!.room.failReplaceWith = const Refused(
    RefusalCode.wordlessTelling,
  );
  traduzirOApontadoDeNovo(container);
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 500));
  _harnessDaVez!.room.failReplaceWith = null;
}

/// The team says they have finished, and the analyst has no more objections.
Future<void> _oVeredictoVoltaLimpo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _harnessDaVez!.room.verdictChecked = true;
  _harnessDaVez!.room.verdictHasFinding = false;
  _harnessDaVez!.room.verdictFindingSegmentId = null;
  _harnessDaVez!.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await _notifier(container).finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Let the closing necklace run its chain of timers out, and the room linger and leave.
///
/// Called after the assertions and never before them: running it takes the room off the
/// telling-back screen, and the window this file is about is the one where the room has
/// said the passage is checked and the cord is still up.
Future<void> _deixarOColarFechar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 35));
}

void main() {
  testWidgets(
    'the retro opens on a part the room has named, not on one still in the air',
    (tester) async {
      final container = await _pumpToPergunta(
        tester,
        takeLandsInRealTime: const Duration(milliseconds: 300),
      );

      expect(
        container.read(salaSessionProvider).partes.single.takeId,
        'gravacao-1',
        reason:
            'a parte entrava no retro antes de a sala dar o nome, e o '
            'trecho contado de volta não tinha de quem ser',
      );
    },
  );

  testWidgets('uma passagem conferida não deixa trecho à espera do conserto', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    _oTrechoEsperaOConserto(
      container,
      reason:
          'o achado apontou o primeiro trecho — se não apontar, este '
          'cenário não chega ao que mede',
    );

    await _consertoQueNaoPegou(tester, container);
    _oTrechoEsperaOConserto(
      container,
      reason:
          'o conserto não pegou e nada fica pendente sobre o trecho: ele '
          'volta a esperar o conserto, e o ponteiro segue nomeando um '
          'trecho que está lá',
    );

    await _oVeredictoVoltaLimpo(tester, container);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'a sala deu a passagem por conferida',
    );
    expect(
      _apontados(container),
      isEmpty,
      reason:
          'a passagem conferida ainda deixava um trecho apontado, dizendo '
          'que havia trabalho onde não havia',
    );

    await _deixarOColarFechar(tester);
  });

  testWidgets('a conferida desenha o anel telha dela, que não responde ao '
      'toque, nunca um círculo de barro', (tester) async {
    final container = await _pumpToPergunta(tester);
    await _consertoQueNaoPegou(tester, container);
    await _oVeredictoVoltaLimpo(tester, container);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    await tester.pump(const Duration(milliseconds: 1000));

    final circulo = tester.widget<FacilitatorCircle>(
      find.byType(FacilitatorCircle),
    );
    expect(circulo.answersATouch, isFalse);
    final pintados = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(FacilitatorCircle),
            matching: find.byType(Container),
          ),
        )
        .map((caixa) => caixa.decoration)
        .whereType<BoxDecoration>()
        .toList();

    expect(
      [
        for (final pintado in pintados)
          if (pintado.border case final Border borda) borda.top,
      ],
      [const BorderSide(color: Color(0xFFBE4A01), width: 1.5)],
      reason:
          'com a checagem limpa o .check-circle dela segue na tela em '
          'data-state idle, só desabilitado (Drafting.tsx:2404-2406, '
          'globals.css:379, :385); o nosso trocava por um círculo de barro '
          'com borda cord',
    );
    expect(
      pintados.expand((pintado) => pintado.gradient?.colors ?? <Color>[]),
      everyElement(predicate<Color>((cor) => cor.a < 1)),
      reason: 'o anel dela é vazado: por dentro só o areia translúcido',
    );

    await _deixarOColarFechar(tester);
  });

  testWidgets('a conferida solta o trecho que o achado apontava', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    await _consertoQueNaoPegou(tester, container);
    expect(container.read(salaSessionProvider).btFindingSegmentId, 'trecho-1');

    await _oVeredictoVoltaLimpo(tester, container);

    expect(
      container.read(salaSessionProvider).btFindingSegmentId,
      isNull,
      reason:
          'o analista não tem mais objeção, então não há trecho apontado. '
          'O ponteiro sobrevivia ao veredito limpo porque este ramo devolve '
          'antes de chegar onde ele é resolvido',
    );
    expect(
      container.read(salaSessionProvider).btFindingTrecho,
      isNull,
      reason: 'e nada mais na sala pode agir sobre um achado que acabou',
    );

    await _deixarOColarFechar(tester);
  });

  testWidgets(
    'um veredito que ainda aponta um trecho o deixa à espera do conserto',
    (tester) async {
      final container = await _pumpToPergunta(tester);
      final harness = _harnessDaVez!;
      await _consertoQueNaoPegou(tester, container);

      // O analista continua insatisfeito com o mesmo trecho.
      harness.room.verdictChecked = false;
      harness.room.verdictHasFinding = true;
      harness.room.verdictFindingSegmentId = 'trecho-1';
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
      await _notifier(container).finishBackTranslation();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(salaSessionProvider).btPhase,
        BtPhase.playing,
        reason: 'um veredito com achado não confere a passagem',
      );
      _oTrechoEsperaOConserto(
        container,
        reason:
            'o ramo com achado soltava o trecho, que é coisa do veredito '
            'limpo, e apagava a indicação de onde estava o problema',
      );
    },
  );

  testWidgets('o ramo limpo não mexe em mais nada do estado', (tester) async {
    final container = await _pumpToPergunta(tester);
    await _consertoQueNaoPegou(tester, container);
    final antes = container.read(salaSessionProvider);
    final trechosAntes = [
      for (final trecho in antes.btTrechos)
        '${trecho.segmentId}@${trecho.takeId}:'
            '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
    ];

    await _oVeredictoVoltaLimpo(tester, container);

    final depois = container.read(salaSessionProvider);
    expect(
      [
        for (final trecho in depois.btTrechos)
          '${trecho.segmentId}@${trecho.takeId}:'
              '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
      ],
      trechosAntes,
      reason:
          'os trechos são os mesmos: conferir não reescreve o que a '
          'equipe contou',
    );
    expect(depois.btChunkFailures, antes.btChunkFailures);
    expect(depois.btPass, antes.btPass);
    expect(
      depois.keptTakes.length,
      antes.keptTakes.length,
      reason: 'e o ensaio da equipe continua inteiro',
    );
    expect(
      depois.voice,
      VoiceState.done,
      reason: 'só a fase e a voz mudam, que é o que conferir significa',
    );

    await _deixarOColarFechar(tester);
  });
}
