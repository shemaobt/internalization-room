import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/main.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show gravarAFraseAberta, tocarNaLista, tocarOCirculo;
import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart' show tocar;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

typedef _Words = ({
  String terminei,
  String aprovar,
  String approvedSentence,
  String salvo,
  String pronto,
  String conferida,
  String badge,
  String checagem,
  String ponto,
});

String _sentencePt(int v) =>
    'Aprovado como rascunho final da equipe (v$v). Próximo passo: a '
    'checagem externa — o botão aqui embaixo.';

String _sentenceEn(int v) =>
    "Approved as the team's final draft (v$v). Next step: the external "
    'check — the button below.';

_Words _pt(int v) => (
  terminei: 'terminei',
  aprovar: 'Aprovar como rascunho final',
  approvedSentence: _sentencePt(v),
  salvo: 'Ensaio salvo',
  pronto: 'Pronto',
  conferida: '✓ traduzida e conferida',
  badge: '✓ aprovado como rascunho final (v$v)',
  checagem: 'Checagem externa',
  ponto: 'Gravar o ensaio de vocês',
);

_Words _en(int v) => (
  terminei: 'done',
  aprovar: 'Approve as the final draft',
  approvedSentence: _sentenceEn(v),
  salvo: 'Rehearsal saved',
  pronto: 'Done',
  conferida: '✓ translated and checked',
  badge: '✓ approved as the final draft (v$v)',
  checagem: 'External check',
  ponto: 'Record your rehearsal',
);

const _p3Pt = ('P3', 'pt');
const _p3En = ('P3', 'en');

bool? _habilitado(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

/// One part told back whole and the check clean: the team standing on the approval press.
Future<ProviderContainer> _ateAConferida(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.verdictChecked = true;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = container.read(salaSessionProvider.notifier);
  await sala.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.gravarACena(1);
  sala.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  sala.retroTap();
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  harness.room
    ..release = const ApprovalAnswer(releaseId: 'solta-1', version: 1)
    ..approvedDraft = const ApprovedDraft(version: 1);
  return container;
}

Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.ensureVisible(byLabel(label).first);
  await tester.tap(byLabel(label).first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// The approval pressed with the voice holding P3, the screen read 300 ms in.
Future<void> _approveWithP3Held(
  WidgetTester tester,
  SalaHarness harness,
  _Words w,
) async {
  harness.voice.holdNextLine();
  await pressTheApproval(tester, w.aprovar);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _finishP3(WidgetTester tester, SalaHarness harness) async {
  harness.voice.finishHeldLine();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _prontoEDeVoltaPeloPonto(
  WidgetTester tester,
  SalaHarness harness,
  _Words w,
) async {
  harness.room.readsChecked = true;
  await _tapAndSettle(tester, w.pronto);
  await _tapAndSettle(tester, w.ponto);
}

void _expectTheButtonStands(WidgetTester tester, _Words w) {
  expect(find.text(w.badge), findsOneWidget);
  expect(byLabel(w.checagem), findsOneWidget);
  expect(_habilitado(tester, w.checagem), isTrue);
  expect(byLabel(w.aprovar), findsNothing);
}

void main() {
  testWidgets(
    'approved from the check screen: the sentence, P3 once, «Ensaio salvo», '
    'and «Pronto», then the dot, lands on the home with «Checagem externa»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _ateAConferida(tester, harness);
      final w = _pt(1);
      final antes = harness.voice.fixedLines.length;

      await _approveWithP3Held(tester, harness, w);

      expect(find.text(w.approvedSentence), findsOneWidget);
      expect(harness.voice.fixedLines.skip(antes), [_p3Pt]);
      expect(find.text(w.salvo), findsNothing);

      await _finishP3(tester, harness);

      expect(find.text(w.salvo), findsOneWidget);
      expect(find.text(w.approvedSentence), findsOneWidget);
      expect(byLabel(w.pronto), findsOneWidget);
      expect(byLabel(w.checagem), findsNothing);

      final sonsAntesDoPronto = List.of(harness.sounds);
      harness.room.readsChecked = true;
      await _tapAndSettle(tester, w.pronto);

      expect(find.text(w.salvo), findsNothing);
      expect(harness.sounds, sonsAntesDoPronto);

      await _tapAndSettle(tester, w.ponto);

      expect(find.text(w.conferida), findsOneWidget);
      _expectTheButtonStands(tester, w);
      expect(harness.room.releasesAsked, hasLength(1));
      expect(harness.voice.fixedLines.skip(antes), [_p3Pt]);

      await tester.pump(harness.fimLinger + const Duration(seconds: 2));

      expect(find.text(w.conferida), findsOneWidget);
      _expectTheButtonStands(tester, w);
      closeTheRoom(container);
    },
  );

  testWidgets('in an English session: the English P3, the English sentence and '
      '«External check»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _ateAConferida(tester, harness);
    final w = _en(1);
    final antes = harness.voice.fixedLines.length;

    expect(byLabel(w.aprovar), findsOneWidget);
    expect(
      find.text(w.conferida),
      findsNothing,
      reason:
          'a tela da checagem em inglês escrevia «✓ translated and checked»',
    );

    await _approveWithP3Held(tester, harness, w);

    expect(find.text(w.approvedSentence), findsOneWidget);
    expect(harness.voice.fixedLines.skip(antes), [_p3En]);

    await _finishP3(tester, harness);

    expect(find.text(w.salvo), findsOneWidget);
    expect(find.text(w.approvedSentence), findsOneWidget);
    expect(byLabel(w.pronto), findsOneWidget);

    await _prontoEDeVoltaPeloPonto(tester, harness, w);

    expect(find.text(w.conferida), findsOneWidget);
    _expectTheButtonStands(tester, w);
    expect(harness.voice.fixedLines.skip(antes), [_p3En]);
    closeTheRoom(container);
  });

  testWidgets('while her line plays the check draws the sentence and the badge '
      'with no «Checagem externa», and the home\'s button is lit after '
      '«Pronto»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    final w = _pt(1);

    await _approveWithP3Held(tester, harness, w);

    expect(find.text(w.approvedSentence), findsOneWidget);
    expect(find.text(w.badge), findsOneWidget);
    expect(byLabel(w.checagem), findsNothing);

    await _finishP3(tester, harness);
    await _prontoEDeVoltaPeloPonto(tester, harness, w);

    expect(_habilitado(tester, w.checagem), isTrue);
    closeTheRoom(container);
  });

  testWidgets('one tap on «Checagem externa» after «Pronto» opens the '
      'Checagem externa, with no code', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    final w = _pt(1);
    await _approveWithP3Held(tester, harness, w);
    await _finishP3(tester, harness);
    await _prontoEDeVoltaPeloPonto(tester, harness, w);
    final falas = List.of(harness.voice.fixedLines);

    await _tapAndSettle(tester, w.checagem);

    expect(harness.room.externalChecksOpened, [
      container.read(salaSessionProvider).sessionId,
    ]);
    expect(find.text(w.checagem), findsOneWidget);
    expect(byLabel('Novo ouvinte'), findsOneWidget);
    expect(find.byType(CodigoView), findsNothing);
    expect(harness.voice.fixedLines, falas);
    closeTheRoom(container);
  });

  testWidgets('re-opening the draft takes the button away, and approving v2 '
      'brings it back through the same order', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final w1 = _pt(1);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.verdictChecked = true;
    await tocar(tester, w1.terminei);
    await waitFor(
      'a sala conferir',
      () => byLabel(w1.aprovar).evaluate().isNotEmpty,
      step: () => _passo(tester),
    );
    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    await tocar(tester, w1.aprovar);
    await waitFor(
      'o ensaio salvo',
      () => find.text(w1.salvo).evaluate().isNotEmpty,
      step: () => _passo(tester),
    );
    await _prontoEDeVoltaPeloPonto(tester, harness, w1);
    _expectTheButtonStands(tester, w1);
    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a retrotradução aprovada voltar conferida',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    harness.room.readsChecked = false;
    await tester.pump(const Duration(milliseconds: 800));

    await tocarNaLista(tester, 'regravar a frase 2');
    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(
      tester,
      'toquem de novo: isto abre de novo o rascunho aprovado',
    );
    await gravarAFraseAberta(tester, harness);
    harness.room.approvedDraft = null;
    await tester.tap(find.text('usar esta'));
    await tester.pump(const Duration(seconds: 1));
    harness.playback.finishPlayback();
    await _passo(tester);

    expect(harness.room.sentencesSentReopening, hasLength(1));
    expect(byLabel(w1.checagem), findsNothing);
    expect(find.text(w1.badge), findsNothing);
    expect(find.textContaining('Aprovado como rascunho final'), findsNothing);

    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await _passo(tester);
    await _passo(tester);
    await waitFor(
      'a gravação ouvida até o fim',
      () => container.read(salaSessionProvider).btClipEnded,
      step: () async {
        if (container.read(salaSessionProvider).btClipRodando) {
          harness.playback.finishPlayback();
        } else {
          container.read(salaSessionProvider.notifier).ouvirGravacao();
        }
        await _passo(tester);
      },
    );
    await tocar(tester, w1.terminei);
    await waitFor(
      'a sala conferir de novo',
      () => byLabel(w1.aprovar).evaluate().isNotEmpty,
      step: () => _passo(tester),
    );
    harness.room
      ..release = const ApprovalAnswer(releaseId: 'solta-2', version: 2)
      ..approvedDraft = const ApprovedDraft(version: 2);
    final w2 = _pt(2);
    final antes = harness.voice.fixedLines.length;

    await _approveWithP3Held(tester, harness, w2);

    expect(harness.room.releasesAsked, hasLength(2));
    expect(find.text(w2.approvedSentence), findsOneWidget);
    expect(harness.voice.fixedLines.skip(antes), [_p3Pt]);

    await _finishP3(tester, harness);

    expect(find.text(w2.salvo), findsOneWidget);
    expect(find.text(w2.approvedSentence), findsOneWidget);

    await _prontoEDeVoltaPeloPonto(tester, harness, w2);

    _expectTheButtonStands(tester, w2);
    closeTheRoom(container);
  });

  testWidgets('an approval line not heard whole still ends on «Ensaio salvo», '
      'and the home after «Pronto» shows «Checagem externa»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    final w = _pt(1);
    harness.voice.refuses.add('P3');

    await pressTheApproval(tester, w.aprovar);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(w.salvo), findsOneWidget);
    expect(find.text(w.approvedSentence), findsOneWidget);
    expect(byLabel(w.pronto), findsOneWidget);

    await _prontoEDeVoltaPeloPonto(tester, harness, w);

    _expectTheButtonStands(tester, w);
    expect(harness.room.releasesAsked, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('while P3 plays the check offers no «Checagem externa», and '
      '«Ensaio salvo» still follows the line', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    final w = _pt(1);
    final antes = harness.voice.fixedLines.length;
    await _approveWithP3Held(tester, harness, w);

    expect(
      byLabel(w.checagem),
      findsNothing,
      reason: 'a tela da checagem oferecia a «Checagem externa» com a P3 no ar',
    );
    expect(harness.room.externalChecksOpened, isEmpty);
    expect(find.text(w.salvo), findsNothing);

    await _finishP3(tester, harness);

    expect(find.text(w.salvo), findsOneWidget);
    expect(harness.room.externalChecksOpened, isEmpty);

    await _prontoEDeVoltaPeloPonto(tester, harness, w);

    _expectTheButtonStands(tester, w);
    expect(harness.room.releasesAsked, hasLength(1));
    expect(harness.voice.fixedLines.skip(antes), [_p3Pt]);
    closeTheRoom(container);
  });

  for (final (lingua, w) in [('pt', _pt(1)), ('en', _en(1))]) {
    testWidgets('«OBT Refine» is never shown after an approval ($lingua)', (
      tester,
    ) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: lingua);
      final container = await _ateAConferida(tester, harness);
      await _approveWithP3Held(tester, harness, w);
      expect(find.textContaining('Refine'), findsNothing);
      await _finishP3(tester, harness);
      expect(find.textContaining('Refine'), findsNothing);
      await _prontoEDeVoltaPeloPonto(tester, harness, w);
      expect(find.textContaining('Refine'), findsNothing);
      closeTheRoom(container);
    });
  }
}
