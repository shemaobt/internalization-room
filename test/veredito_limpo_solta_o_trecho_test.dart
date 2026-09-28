import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _micRetro = 'Traduzir este trecho de novo';

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// Which stretches are drawn drained, by their order.
///
/// A stretch is drained exactly when it is the one waiting to be mended. The whole
/// list rather than one place at a time, so the answer can be wrong: asking only about the
/// place the finding named can never catch a pointer somewhere else.
List<int> _faixasVazias(WidgetTester tester, ProviderContainer container) => [
  for (final (lugar, conta)
      in tester
          .widget<BeadRow>(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(BeadRow),
            ),
          )
          .entries
          .indexed)
    if (conta.fill == BeadFill.drained) lugar,
];

/// A team standing at the question, with a finding on the first of two stretches.
///
/// The kind is scenery, not subject: nothing here reads it, and swapping it for any other
/// leaves every case as it is. What every case needs is only a finding that names a
/// stretch, and a correction route out of it.
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
  _harnessDaVez!.room.replaceCaptured = false;
  await tester.tap(byLabel(_micRetro));
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  await _notifier(container).confirmarTraducao();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 500));
  _harnessDaVez!.room.replaceCaptured = true;
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
      isEmpty,
      reason:
          'o conserto não pegou e a tradução nova segue pendente sobre o '
          'trecho: translúcida, como toda regravação pendente (ADR 0040), '
          'e o ponteiro segue nomeando um trecho que está lá',
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
