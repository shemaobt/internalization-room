import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, thePersonSign;
import 'the_back_translation_is_told_by_beads_test.dart' show tocar;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

const _armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _badge = '✓ aprovado como rascunho final (v1)';
const _recomecar = 'recomeçar a tradução';
const _recomecoArmado = 'toque de novo para apagar as 4 frases traduzidas';
const _tentarDeNovo = 'não deu para guardar a frase — tentar de novo';
const _sinal = 'Um momento para uma pessoa';
const _ouvirAFrase1 = 'ouvir a minha tradução da frase 1';
const _ouvirAFrase = ('N6', 'pt');

String _regravar(int n) => 'regravar a frase $n';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Finder _naLista(String label) =>
    find.descendant(of: find.byType(FraseList), matching: byLabel(label));

Finder _textoNaLista(String texto) =>
    find.descendant(of: find.byType(FraseList), matching: find.text(texto));

bool _acesa(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_naLista(label)).properties.enabled ?? true;

Future<void> tocarNaLista(WidgetTester tester, String label) async {
  await tester.ensureVisible(_naLista(label));
  await tester.tap(_naLista(label));
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _circulo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

Future<void> tocarOCirculo(WidgetTester tester) async {
  await tester.ensureVisible(_circulo());
  await tester.tap(_circulo());
  await tester.pump(const Duration(milliseconds: 300));
}

typedef Caminho = ({
  String terminei,
  String aprovar,
  String salvo,
  String pronto,
});

const caminhoEmPortugues = (
  terminei: 'terminei',
  aprovar: 'Aprovar como rascunho final',
  salvo: 'Ensaio salvo',
  pronto: 'Pronto',
);

Future<ProviderContainer> aprovadaNaCasa(
  WidgetTester tester,
  SalaHarness harness, {
  ApprovedDraft approved = const ApprovedDraft(version: 1),
  Caminho caminho = caminhoEmPortugues,
}) async {
  final container = await quatroFrasesEmWav(tester, harness);
  harness.room.verdictChecked = true;
  await tocar(tester, caminho.terminei);
  await waitFor(
    'a sala conferir',
    () => byLabel(caminho.aprovar).evaluate().isNotEmpty,
    step: () => _passo(tester),
  );
  harness.room.approvedDraft = approved;
  await tocar(tester, caminho.aprovar);
  await waitFor(
    'o ensaio salvo',
    () => find.text(caminho.salvo).evaluate().isNotEmpty,
    step: () => _passo(tester),
  );
  await tester.tap(byLabel(caminho.pronto));
  await tester.pump(const Duration(milliseconds: 800));
  final sala = container.read(salaSessionProvider.notifier);
  harness.room.readsChecked = true;
  sala.openTheEnsaioFinal();
  await waitFor(
    'a casa da gravação abrir pelo ponto',
    () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
    step: () => _passo(tester),
  );
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

/// Four frases told over WAV parts, checked, approved as [approved], and «Pronto»
/// pressed: the team back on the approved draft's Back-translation.
Future<ProviderContainer> aprovadaNaConferida(
  WidgetTester tester,
  SalaHarness harness, {
  ApprovedDraft approved = const ApprovedDraft(version: 1),
  Caminho caminho = caminhoEmPortugues,
}) async {
  final container = await aprovadaNaCasa(
    tester,
    harness,
    approved: approved,
    caminho: caminho,
  );
  final sala = container.read(salaSessionProvider.notifier);
  sala.startRetro();
  await waitFor(
    'a retrotradução aprovada voltar conferida',
    () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
    step: () => _passo(tester),
  );
  harness.room.readsChecked = false;
  await tester.pump(const Duration(milliseconds: 800));
  return container;
}

Future<ProviderContainer> _aprovada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await aprovadaNaConferida(tester, harness);
  expect(
    find.text(_badge),
    findsOneWidget,
    reason: 'o cenário só mede alguma coisa sobre um rascunho aprovado',
  );
  return container;
}

Future<void> gravarAFraseAberta(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.playback.finishPlayback();
  await _passo(tester);
  await _passo(tester);
  await tocarOCirculo(tester);
  harness.recorder.rehearsalSpeaks = aSpokenWav(
    length: const Duration(seconds: 2),
  );
  await tocarOCirculo(tester);
  await _passo(tester);
}

String _guardada(SalaHarness harness) => (harness.takes as FakeTakeQueue).rows
    .singleWhere((row) => row.kind == 'frase')
    .id;

void main() {
  testWidgets('over an approved draft, «regravar a frase 2» arms first and '
      'opens the sentence on a second tap two seconds later', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista(_regravar(n)),
        findsOneWidget,
        reason: 'a frase $n de um rascunho aprovado não oferecia regravar',
      );
    }
    harness.voice.fixedLines.clear();

    await tocarNaLista(tester, _regravar(2));

    expect(_textoNaLista(_armado), findsOneWidget);
    expect(
      harness.voice.fixedLines,
      isNot(contains(_ouvirAFrase)),
      reason: 'o primeiro toque já abria a frase de um rascunho aprovado',
    );
    expect(find.text(_badge), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(tester, _armado);

    expect(
      harness.voice.fixedLines,
      contains(_ouvirAFrase),
      reason: 'a segunda batida no tempo não abria a frase',
    );
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the armed «regravar a frase 2» reads '
      'pressed to VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);

    await tocarNaLista(tester, _regravar(2));

    expect(
      tester.getSemantics(_naLista(_armado)),
      isSemantics(hasToggledState: true, isToggled: true),
      reason: 'o regravar armado soava solto para o VoiceOver',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('the sentence of a confirmed armed tap goes up with the '
      're-open, and the badge leaves with the next read', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(tester, _armado);
    await gravarAFraseAberta(tester, harness);
    final segura = harness.room.holdTheSentence = Completer<void>();

    await tester.tap(_textoNaLista('usar esta'));
    await _passo(tester);
    final frase = _guardada(harness);
    harness.room.approvedDraft = null;
    segura.complete();
    await waitFor(
      'a frase entrar no lugar',
      () => harness.room.sentencesLaid.isNotEmpty,
      step: () => _passo(tester),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(harness.room.sentencesSentReopening, [frase]);
    expect(
      find.text(_badge),
      findsNothing,
      reason: 'o selo ficava depois que a frase reabriu o rascunho',
    );
    harness.voice.fixedLines.clear();
    await tocarNaLista(tester, _regravar(2));
    expect(
      _textoNaLista(_armado),
      findsNothing,
      reason: 'o tablet seguia tomando o rascunho reaberto por aprovado',
    );
    closeTheRoom(container);
  });

  testWidgets('a read of the stretches that went out while the sentence was in '
      'the air never brings the old sentence back over the kept one', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(tester, _armado);
    await gravarAFraseAberta(tester, harness);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(_textoNaLista('usar esta'));
    await _passo(tester);
    harness.room.approvedDraft = null;
    harness.room.keptRetellings = const [
      KeptRetelling(scope: 'parte-1', turnNumber: 1, audioUrl: 'ouvinte.mp3'),
    ];
    harness.room.holdTheNextRead();
    harness.room.holdTheNextRead();
    container.read(salaSessionProvider.notifier).abrirAChecagemExterna();
    await waitFor(
      'a leitura sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );
    segura.complete();
    await waitFor(
      'a frase entrar no lugar',
      () => harness.room.sentencesLaid.isNotEmpty,
      step: () => _passo(tester),
    );
    await waitFor(
      'a leitura depois da frase sair e ficar presa',
      () => harness.room.heldReads.length == 2,
      step: () => _passo(tester),
    );
    final nova = harness.room.takes.last.takeId;

    harness.room.answerHeldRead(0);
    await _passo(tester);

    expect(
      container
          .read(salaSessionProvider)
          .btTrechos
          .singleWhere((trecho) => trecho.frase == 2)
          .takeId,
      nova,
      reason: 'a leitura de antes da frase voltava a velha por cima da nova',
    );
    expect(
      container.read(salaSessionProvider).btFraseQueAguarda,
      'trecho-2',
      reason: 'a leitura de antes da frase apagava a frase que espera tradução',
    );
    expect(
      container.read(salaSessionProvider).keptRetellings,
      hasLength(1),
      reason: 'a frase mantida jogava fora o que a leitura em voo trazia',
    );
    closeTheRoom(container);
  });

  testWidgets('a second tap after 0.3 s does not count, and the draft stays '
      'approved', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    harness.voice.fixedLines.clear();

    await tester.ensureVisible(_naLista(_regravar(2)));
    await tester.tap(_naLista(_regravar(2)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_naLista(_armado));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_textoNaLista(_armado), findsOneWidget);
    expect(_acesa(tester, _armado), isFalse);
    expect(harness.voice.fixedLines, isNot(contains(_ouvirAFrase)));
    expect(harness.room.sentencesSent, isEmpty);
    expect(find.text(_badge), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('a second tap after 8 s does not count: the arm lapsed and the '
      'tap only arms again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    harness.voice.fixedLines.clear();

    await tocarNaLista(tester, _regravar(2));
    await tester.pump(const Duration(seconds: 8));

    expect(_naLista(_regravar(2)), findsOneWidget);
    expect(_textoNaLista(_armado), findsNothing);

    await tocarNaLista(tester, _regravar(2));

    expect(_textoNaLista(_armado), findsOneWidget);
    expect(harness.voice.fixedLines, isNot(contains(_ouvirAFrase)));
    expect(harness.room.sentencesSent, isEmpty);
    expect(find.text(_badge), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('arming one control disarms the other', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);

    await tocarNaLista(tester, _regravar(2));
    expect(_textoNaLista(_armado), findsOneWidget);
    await tocar(tester, _recomecar);

    expect(find.text(_recomecoArmado), findsOneWidget);
    expect(_naLista(_regravar(2)), findsOneWidget);
    expect(_textoNaLista(_armado), findsNothing);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('a tap on another control disarms the armed frase, and the '
      'next tap on it only arms again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);
    harness.voice.fixedLines.clear();

    await tocarNaLista(tester, _regravar(2));
    await tocarNaLista(tester, _ouvirAFrase1);

    expect(_naLista(_regravar(2)), findsOneWidget);
    expect(_textoNaLista(_armado), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(tester, _regravar(2));

    expect(_textoNaLista(_armado), findsOneWidget);
    expect(harness.voice.fixedLines, isNot(contains(_ouvirAFrase)));
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('over a draft not approved, «regravar a frase N» takes one tap '
      'and goes up without the re-open', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.voice.fixedLines.clear();

    await tocarNaLista(tester, _regravar(2));

    expect(harness.voice.fixedLines, contains(_ouvirAFrase));
    await gravarAFraseAberta(tester, harness);
    await tester.tap(_textoNaLista('usar esta'));
    await waitFor(
      'a frase entrar no lugar',
      () => harness.room.sentencesLaid.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(harness.room.sentencesSent, hasLength(1));
    expect(harness.room.sentencesSentReopening, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('the room refuses a sentence over a draft the tablet did not '
      'know was approved: the sentence is kept and «tentar de novo» arms', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await gravarAFraseAberta(tester, harness);
    final segura = harness.room.holdTheSentence = Completer<void>();

    await tester.tap(_textoNaLista('usar esta'));
    await _passo(tester);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'));
    segura.complete();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_naLista(_tentarDeNovo), findsOneWidget);
    expect(find.text(_sinal), findsNothing);
    expect(thePersonSign, findsNothing);

    final frase = _guardada(harness);
    await tocarNaLista(tester, _tentarDeNovo);

    expect(_textoNaLista(_armado), findsOneWidget);
    expect(harness.room.sentencesSent, hasLength(1));

    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(tester, _armado);
    await waitFor(
      'a frase entrar no lugar',
      () => harness.room.sentencesLaid.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(harness.room.sentencesSentReopening, [frase]);
    closeTheRoom(container);
  });

  testWidgets('the held sentence\'s «tentar de novo», armed over an approved '
      'draft, reads pressed to VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocarNaLista(tester, _regravar(2));
    await gravarAFraseAberta(tester, harness);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(_textoNaLista('usar esta'));
    await _passo(tester);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'));
    segura.complete();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tocarNaLista(tester, _tentarDeNovo);

    expect(
      tester.getSemantics(_naLista(_armado)),
      isSemantics(hasToggledState: true, isToggled: true),
      reason: 'o tentar de novo armado soava solto para o VoiceOver',
    );
    await tester.pump(const Duration(seconds: 8));
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('«recomeçar a tradução» keeps its own armed text over an '
      'approved draft', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aprovada(tester, harness);

    await tocar(tester, _recomecar);

    expect(find.text(_recomecoArmado), findsOneWidget);
    expect(find.text(_armado), findsNothing);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });
}
