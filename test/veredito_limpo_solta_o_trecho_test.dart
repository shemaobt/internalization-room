import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const _micRetro = 'Traduzir de novo só em português';

Finder _byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// Which places on the cord are drawn drained, by their order along it.
///
/// The painter's own rule read from outside: a band is emptied — and wears the halo —
/// exactly when the stretch it draws is the one the cord was told to point at. The whole
/// list rather than one place at a time, so the answer can be wrong: asking only about the
/// place the finding named can never catch a cord pointing somewhere else.
List<int> _faixasVazias(WidgetTester tester, ProviderContainer container) {
  final cord = tester.widget<RetroCord>(find.byType(RetroCord));
  final trechos = container.read(salaSessionProvider).btTrechos;
  return [
    for (var lugar = 0; lugar < trechos.length; lugar++)
      if (cord.apontado != null && trechos[lugar].segmentId == cord.apontado)
        lugar,
  ];
}

/// A team standing at the question, with a finding on the first of two stretches.
///
/// The kind is scenery, not subject: nothing here reads it, and what every case needs is
/// only a finding that names a stretch and a correction route out of it. It is named
/// rather than left to a default because one kind is no longer interchangeable — a finding
/// of *falta* draws no grid of voices at all, since asking which voice the error lives in
/// has no answer when the team told truly and told too little. Proven by experiment before
/// it was written down: a copy of this file with the kind swapped and nothing else changed
/// passes, and still fails without the fix.
Future<ProviderContainer> _pumpToPergunta(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingSegmentId = 'trecho-1';
  _harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = _notifier(container);
  await sala.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    sala.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    sala.retroTap();
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
  _harnessDaVez!.room.replaceCaptured = false;
  await tester.tap(_byLabel(_micRetro));
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 500));
  _harnessDaVez!.room.replaceCaptured = true;
}

/// The team takes the correction on: the microphone opens on that stretch.
Future<void> _comecarOConserto(WidgetTester tester) async {
  await tester.tap(_byLabel(_micRetro));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Hand the correction over, and let the room reach whatever result follows.
///
/// Asking for the result is the room's own last step of a correction that lands, so the
/// verdict has to be armed before this — a stretch named afterwards is answering a
/// question that was already asked.
Future<void> _entregarOConserto(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 500));
}

/// The team says they have finished, and the analyst has no more objections.
Future<void> _oVeredictoVoltaLimpo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _harnessDaVez!.room.verdictChecked = true;
  _harnessDaVez!.room.verdictFinding = null;
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
  testWidgets('uma passagem conferida não deixa faixa vazia no colar', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'o achado apontou o primeiro trecho — se não apontar, este '
          'cenário não chega ao que mede',
    );

    await _consertoQueNaoPegou(tester, container);
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'e o conserto não pegou, então o trecho segue esperando e o '
          'ponteiro segue nomeando um trecho que está lá',
    );

    await _oVeredictoVoltaLimpo(tester, container);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'a sala deu a passagem por conferida',
    );
    expect(
      _faixasVazias(tester, container),
      isEmpty,
      reason:
          'e o colar tem de concordar com ela. Uma faixa vazia sob uma '
          'passagem conferida é a única coisa que a equipe tem para ler '
          'dizendo que ainda há trabalho, e não há',
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

  testWidgets('a conferida também desliga a bandeira de conserto', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);

    await _comecarOConserto(tester);
    expect(
      container.read(salaSessionProvider).btConsertando,
      isTrue,
      reason:
          'a bandeira acende quando a equipe assume o conserto — se não '
          'acender, este cenário não chega ao que mede',
    );

    // Armado antes da entrega, e a equipe entrega com a bandeira acesa. Pedir o
    // resultado é o último passo que a própria sala dá num conserto que pega, então um
    // veredito nomeado depois responderia uma pergunta já feita. A chamada manual abaixo
    // é o mesmo gesto para uma sala que ainda não pede sozinha: onde ela já pede, cai na
    // guarda de `canFinishBackTranslation` e não faz nada.
    _harnessDaVez!.room.verdictChecked = true;
    _harnessDaVez!.room.verdictFinding = null;
    _harnessDaVez!.room.verdictFindingSegmentId = null;
    await _entregarOConserto(tester, container);
    await _oVeredictoVoltaLimpo(tester, container);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'e o conserto chegou mesmo ao veredito limpo',
    );

    expect(
      container.read(salaSessionProvider).btConsertando,
      isFalse,
      reason:
          'não há conserto em curso debaixo de uma passagem conferida. A '
          'bandeira sobrevivia ao fim da sessão, e quem viesse depois '
          'encontraria meia limpeza: o ponteiro solto e ela ainda de pé',
    );
    expect(
      container.read(salaSessionProvider).btEsperandoConserto,
      isNull,
      reason: 'e as duas metades concordam — é o par que decide a faixa',
    );

    await _deixarOColarFechar(tester);
  });

  testWidgets('um veredito que ainda aponta um trecho deixa a faixa vazia', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    await _consertoQueNaoPegou(tester, container);

    // O analista continua insatisfeito com o mesmo trecho.
    harness.room.verdictChecked = false;
    harness.room.verdictFinding = BtFindingKind.addition;
    harness.room.verdictFindingSegmentId = 'trecho-1';
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await _notifier(container).finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.findings,
      reason: 'um veredito com achado não confere a passagem',
    );
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'e a faixa daquele trecho continua vazia: soltar o trecho é '
          'coisa do veredito limpo, e alargar isso para o ramo com achado '
          'apagaria a única indicação de onde está o problema',
    );
  });

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
