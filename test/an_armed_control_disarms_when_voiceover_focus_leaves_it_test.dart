import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida, gravarAFraseAberta, tocarNaLista;
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, voiceOverFocusLeaves;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

const _armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _tentarDeNovo = 'não deu para guardar a frase — tentar de novo';
const _ouvirAFrase = ('N6', 'pt');

String _regravar(int n) => 'regravar a frase $n';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Finder _naLista(String label) =>
    find.descendant(of: find.byType(FraseList), matching: byLabel(label));

void _oFocoPousaEm(WidgetTester tester, Finder control) =>
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.didGainAccessibilityFocus,
        viewId: tester.view.viewId,
        nodeId: tester.getSemantics(control).id,
      ),
    );

void main() {
  testWidgets('an armed «regravar a frase 2» that VoiceOver focus leaves reads '
      'its own label again, and the next tap only arms', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.voice.fixedLines.clear();
    await tocarNaLista(tester, _regravar(2));
    await tester.pump(const Duration(seconds: 2));
    expect(_naLista(_armado), findsOneWidget);

    voiceOverFocusLeaves(tester, _naLista(_armado));
    await _passo(tester);

    expect(
      _naLista(_regravar(2)),
      findsOneWidget,
      reason:
          'o controle continuava armado depois que o foco do VoiceOver saiu '
          'dele, e um toque duplo mais tarde abria a frase sem armar de novo',
    );
    expect(_naLista(_armado), findsNothing);

    await tocarNaLista(tester, _regravar(2));

    expect(_naLista(_armado), findsOneWidget);
    expect(
      harness.voice.fixedLines,
      isNot(contains(_ouvirAFrase)),
      reason: 'o toque seguinte abria a frase em vez de só armar',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('focus that lands on the armed «regravar a frase 2» and stays '
      'keeps it armed until the lapse', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    await tocarNaLista(tester, _regravar(2));

    _oFocoPousaEm(tester, _naLista(_armado));
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.getSemantics(_naLista(_armado)),
      isSemantics(hasToggledState: true, isToggled: true),
      reason: 'o foco pousando no controle armado o desarmava',
    );
    expect(_naLista(_regravar(2)), findsNothing);

    await tester.pump(const Duration(seconds: 6));

    expect(_naLista(_regravar(2)), findsOneWidget);
    expect(_naLista(_armado), findsNothing);
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('focus leaving another row\'s «regravar a frase 1» leaves '
      '«regravar a frase 2» armed', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await tester.pump(const Duration(seconds: 2));

    voiceOverFocusLeaves(tester, _naLista(_regravar(1)));
    await _passo(tester);

    expect(
      _naLista(_armado),
      findsOneWidget,
      reason: 'o foco saindo de outro controle desarmava o que estava armado',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('focus leaving «regravar a frase 2» while it is still asleep '
      'disarms it too', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    expect(_naLista(_armado), findsOneWidget);

    voiceOverFocusLeaves(tester, _naLista(_armado));
    await _passo(tester);

    expect(
      _naLista(_regravar(2)),
      findsOneWidget,
      reason: 'o foco saindo antes do despertar deixava o controle armado',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('an armed «tentar de novo» that VoiceOver focus leaves reads '
      'its own line again, and the next tap only arms', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await gravarAFraseAberta(tester, harness);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(
      find.descendant(
        of: find.byType(FraseList),
        matching: find.text('usar esta'),
      ),
    );
    await _passo(tester);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'));
    segura.complete();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNaLista(tester, _tentarDeNovo);
    await tester.pump(const Duration(seconds: 2));
    expect(_naLista(_armado), findsOneWidget);

    voiceOverFocusLeaves(tester, _naLista(_armado));
    await _passo(tester);

    expect(
      _naLista(_tentarDeNovo),
      findsOneWidget,
      reason: 'o tentar de novo seguia armado depois que o foco saiu dele',
    );

    await tocarNaLista(tester, _tentarDeNovo);

    expect(_naLista(_armado), findsOneWidget);
    expect(
      harness.room.sentencesSentReopening,
      isEmpty,
      reason: 'o toque seguinte reenviava a frase em vez de só armar',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });
}
