import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/status_lines.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        fimDaGravacao,
        gravarATraducao,
        parte,
        terminar,
        tocar,
        tocarNoCirculo;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _duasFrasesNoTerminei(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await contarAteOFimDaParte(tester, harness);
  await waitFor(
    'o terminei acender',
    () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
    step: () => _passo(tester),
  );
  return container;
}

Future<void> _recusado(WidgetTester tester, ProviderContainer container) async {
  await tocar(tester, conferir);
  await waitFor('a recusa voltar', () {
    final estado = container.read(salaSessionProvider);
    return !estado.btConferindo &&
        (estado.btPhase == BtPhase.playing || estado.needsPerson);
  }, step: () => _passo(tester));
  await _passo(tester);
}

void main() {
  test('every refusal the check answers is read by its name, and one this '
      'build does not handle reads as none', () {
    CheckRefusal? lida(Object? code) => BackTranslationVerdict.fromJson({
      'session_id': 'sessao-1',
      'checked': false,
      'refusal': code,
    }).refusal;

    expect(
      [
        lida('FRASE_AWAITING'),
        lida('PART_UNHEARD'),
        lida('STRETCH_UNTRANSLATED'),
        lida('NOTHING_TRANSLATED'),
        lida('CHECK_UNAVAILABLE'),
      ],
      [
        CheckRefusal.fraseAwaiting,
        CheckRefusal.partUnheard,
        CheckRefusal.stretchUntranslated,
        CheckRefusal.nothingTranslated,
        CheckRefusal.checkUnavailable,
      ],
      reason: 'o app não lia o campo refusal, e toda recusa virava silêncio',
    );
    expect(lida('A_REFUSAL_FROM_A_NEWER_ROOM'), isNull);
    expect(lida(null), isNull);
  });

  testWidgets('a part the player cannot measure, heard to its end with no '
      'frase told, never opens «terminei»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(
      tester,
      harness,
      partes: 1,
      medida: null,
    );

    harness.playback.at = Duration.zero;
    harness.playback.finishPlayback();
    await waitFor(
      'a parte acabar',
      () => container.read(salaSessionProvider).btClipEnded,
      step: () => _passo(tester),
    );

    expect(
      aceso(tester, conferir),
      isFalse,
      reason:
          'uma parte sem medida abria o terminei sem nenhuma frase traduzida',
    );
    await tester.tap(byLabel(conferir));
    await _passo(tester);
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'o toque pedia a conferência de uma tradução que não existe',
    );
    closeTheRoom(container);
  });

  testWidgets('a check refused with nothing translated says so in her words, '
      'voices nothing, and leaves «terminei» to press again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.nothingTranslated;
    harness.voice.refuses.add('');
    final falas = [...harness.voice.played];

    await _recusado(tester, container);

    expect(
      find.text('ainda não tem frase traduzida'),
      findsOneWidget,
      reason: 'a recusa sem frase traduzida não dizia nada na tela',
    );
    expect(
      harness.voice.played,
      falas,
      reason: 'a sala tentava tocar um endereço vazio onde ela não diz nada',
    );
    expect(aceso(tester, conferir), isTrue);
    closeTheRoom(container);
  });

  testWidgets('a check whose model cannot answer says so in her words, and '
      '«terminei» pressed again sends exactly one more check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
    harness.voice.refuses.add('');
    final falas = [...harness.voice.played];

    await _recusado(tester, container);

    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
      reason: 'a conferência que não pôde rodar voltava sem nada na tela',
    );
    expect(harness.voice.played, falas);
    expect(aceso(tester, conferir), isTrue);

    await _recusado(tester, container);
    expect(
      harness.room.playedByTakeSent,
      hasLength(2),
      reason: 'terminei é o jeito de tentar de novo, uma vez por toque',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a check the room refuses says her «não deu para conferir», plays '
    'nothing, and leaves the telling where it was',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _duasFrasesNoTerminei(tester, harness);
      harness.room.failFinishWith = const Refused('BAD_REQUEST');
      final falas = [...harness.voice.played];
      final tocadas = harness.playback.played.length;

      await _recusado(tester, container);

      expect(
        find.text('não deu para conferir agora — tentem de novo'),
        findsOneWidget,
        reason: 'a recusa da sala ao terminei voltava sem nada na tela',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
      expect(harness.voice.played, falas);
      expect(harness.playback.played.skip(tocadas), isEmpty);
      expect(aceso(tester, conferir), isTrue);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a verdict whose sound the player refuses twice says her «não deu para '
    'conferir», calls nobody, and lights «terminei» again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..voice.refuses.add(falaDoVeredito);
      final container = await _duasFrasesNoTerminei(tester, harness);

      await _recusado(tester, container);
      await _passo(tester);

      expect(
        find.text('não deu para conferir agora — tentem de novo'),
        findsOneWidget,
        reason:
            'o veredito que não soava voltava sem palavra na tela, e a '
            'chamada por uma pessoa ficava esperando a conversa',
      );
      final estado = container.read(salaSessionProvider);
      expect(estado.needsPerson, isFalse);
      expect(estado.machine.aHaltWaitsForTheCanvas, isNull);
      expect(estado.btPhase, BtPhase.playing);
      expect(aceso(tester, conferir), isTrue);
      closeTheRoom(container);
    },
  );

  testWidgets('a check whose session is gone takes the team back to the '
      'choice, not to her «não deu para conferir»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.failFinishWith = const SessionGone();

    await tocar(tester, conferir);
    await waitFor(
      'a sessão sumida voltar',
      () => container.read(salaSessionProvider).stage == SalaStage.escolha,
      step: () => _passo(tester),
    );
    await _passo(tester);

    final estado = container.read(salaSessionProvider);
    expect(
      estado.stage,
      SalaStage.escolha,
      reason: 'a sessão sumida no terminei não voltava para a escolha',
    );
    expect(estado.needsPerson, isFalse);
    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsNothing,
    );
    closeTheRoom(container);
  });

  testWidgets('three checks in a row whose model cannot answer call no '
      'person', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
    harness.voice.refuses.add('');

    for (var vez = 0; vez < 3; vez++) {
      await _recusado(tester, container);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      estado.needsPerson,
      isFalse,
      reason: 'cada conferência sem modelo contava como uma fala que falhou',
    );
    expect(harness.room.playedByTakeSent, hasLength(3));
    closeTheRoom(container);
  });

  testWidgets('a part not heard through is refused with her line on the '
      'screen and her P2 by its name, and nothing plays after it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    final aParte = container.read(salaSessionProvider).partes.single;
    harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [aParte.takeId!];
    final linhas = harness.voice.fixedLines.length;
    final tocadas = harness.playback.played.length;

    await _recusado(tester, container);
    await _passo(tester);

    expect(
      find.descendant(
        of: find.byType(StatusLines),
        matching: find.text('ainda falta ouvir um trecho da gravação'),
      ),
      findsOneWidget,
      reason: 'a parte não ouvida tinha a fala dela e nada na tela',
    );
    expect(
      [for (final (linha, _) in harness.voice.fixedLines.skip(linhas)) linha],
      ['P2'],
      reason: 'a fala da parte não ouvida é a P2 dela, pedida pelo nome',
    );
    expect(
      harness.playback.played.skip(tocadas),
      isEmpty,
      reason:
          'depois da P2 a sala tocava sozinha a parte não ouvida; a dela '
          'para na linha escrita até a equipe tocar no play',
    );
    expect(
      aceso(tester, conferir),
      isFalse,
      reason:
          'o terminei acendia debaixo da linha que diz que falta ouvir; o '
          'dela só volta quando a sala conta tudo ouvido',
    );
    closeTheRoom(container);
  });

  testWidgets('a part refused as unheard writes her line under terminei too, '
      'as hers, not only in the status above', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [
        container.read(salaSessionProvider).partes.single.takeId!,
      ];

    await _recusado(tester, container);
    await _passo(tester);

    final linhas = find.text('ainda falta ouvir um trecho da gravação');
    expect(
      linhas,
      findsNWidgets(2),
      reason:
          'a recusa dizia a parte não ouvida só lá em cima, e ela diz '
          'também debaixo do terminei',
    );
    expect(
      tester.getRect(linhas.last).top,
      greaterThanOrEqualTo(tester.getRect(byLabel(conferir)).bottom),
    );
    closeTheRoom(container);
  });

  testWidgets('a stretch the room named untranslated keeps her hint under '
      'terminei when a failed play takes the status line, never nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room
      ..verdictRefusal = CheckRefusal.stretchUntranslated
      ..verdictFixedLine = 'N2'
      ..verdictUntranslated = [
        UntranslatedPart(
          takeId: container.read(salaSessionProvider).partes.single.takeId!,
          scene: 1,
          from: cabeca,
        ),
      ];

    await _recusado(tester, container);
    await waitFor(
      'o trecho voltar ao ar',
      () => harness.playback.sounding,
      step: () => _passo(tester),
    );
    expect(
      find.textContaining(
        "falta traduzir um trecho — ouçam e traduzam, depois toquem em "
        "'terminei'",
      ),
      findsOneWidget,
      reason: 'com a dica já na linha de estado, ela não a escreve de novo',
    );
    harness.playback.failPlayback();
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btRecusa,
      CheckRefusal.stretchUntranslated,
    );
    expect(
      find.descendant(
        of: find.byType(StatusLines),
        matching: find.text('não deu para conferir agora — tentem de novo'),
      ),
      findsOneWidget,
    );
    final dica = find.text(
      "falta traduzir um trecho — ouçam e traduzam, depois toquem em 'terminei'",
    );
    expect(
      dica,
      findsOneWidget,
      reason:
          'com o aviso no lugar da dica, o terminei apagado não levava linha '
          'nenhuma, e ela escreve a dica debaixo dele',
    );
    expect(
      tester.getRect(dica).top,
      greaterThanOrEqualTo(tester.getRect(byLabel(conferir)).bottom),
    );
    expect(find.text('ainda falta ouvir um trecho da gravação'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a frase awaiting its words is refused with her N5 by its name, '
      'and that frase opens to be translated', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room
      ..verdictRefusal = CheckRefusal.fraseAwaiting
      ..verdictFixedLine = 'N5'
      ..verdictUntoldSegmentId = 'trecho-1';
    final linhas = harness.voice.fixedLines.length;

    await tocar(tester, conferir);
    await waitFor(
      'a frase que espera abrir',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechoTraduzidoDeNovo
              ?.segmentId ==
          'trecho-1',
      step: () => _passo(tester),
    );

    expect(
      [for (final (linha, _) in harness.voice.fixedLines.skip(linhas)) linha],
      ['N5'],
      reason: 'a frase regravada que espera é a N-6 dela, pedida pelo nome N5',
    );
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-1',
    );
    expect(
      harness.playback.ranges.last,
      '0-4000',
      reason: 'a frase que espera toca a sua própria fatia',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase awaiting its words with no line of hers voices nothing, '
      'and that frase still opens', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room
      ..verdictRefusal = CheckRefusal.fraseAwaiting
      ..verdictUntoldSegmentId = 'trecho-1';
    harness.voice.refuses.add('');
    final falas = [...harness.voice.played];

    await tocar(tester, conferir);
    await waitFor(
      'a frase que espera abrir',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechoTraduzidoDeNovo
              ?.segmentId ==
          'trecho-1',
      step: () => _passo(tester),
    );

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-1',
      reason: 'a recusa calada tentava tocar o vazio e nunca abria a frase',
    );
    expect(harness.voice.played, falas);
    expect(harness.playback.ranges.last, '0-4000');
    closeTheRoom(container);
  });

  testWidgets('a refusal\'s line leaves the moment «terminei» is pressed '
      'again, not when the next answer comes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.nothingTranslated;
    await _recusado(tester, container);
    expect(find.text('ainda não tem frase traduzida'), findsOneWidget);

    harness.room.holdNextVerdict();
    await tocar(tester, conferir);
    await waitFor(
      'a conferência estar no ar',
      () => container.read(salaSessionProvider).btConferindo,
      step: () => _passo(tester),
    );

    expect(
      find.text('ainda não tem frase traduzida'),
      findsNothing,
      reason:
          'a linha da recusa anterior ficava na tela durante a nova conferência',
    );
    harness.room.finishHeldVerdict();
    closeTheRoom(container);
  });

  testWidgets('a frase sent after a refusal takes the refusal\'s line away, so '
      'what the screen says is about the frase', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = parte - const Duration(milliseconds: 500);
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await waitFor(
      'o terminei acender',
      () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
      step: () => _passo(tester),
    );
    harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
    await _recusado(tester, container);
    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
    );

    await tocar(tester, fimDaGravacao);
    await tocar(tester, fimDaGravacao);
    harness.room.failChunkWith = const Refused(RefusalCode.wordlessTelling);
    await tocar(tester, terminar);
    await waitFor(
      'a sala não entender a frase',
      () => container.read(salaSessionProvider).wordlessTelling,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('não entendi — traduzam de novo esse pedaço'),
      findsOneWidget,
      reason: 'a linha da recusa tapava a da frase que a sala não entendeu',
    );
    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsNothing,
    );
    closeTheRoom(container);
  });

  testWidgets('a frase whose send fails on the network says «não entendi», '
      'keeps its pause, and is never sent again on its own', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.failChunkWith = const NetworkFailed('sem rede');
    await tocar(tester, terminar);
    await waitFor('a frase voltar da rede', () {
      final estado = container.read(salaSessionProvider);
      return estado.wordlessTelling;
    }, step: () => _passo(tester));
    harness.room.failChunkWith = null;
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    expect(
      find.text('não entendi — traduzam de novo esse pedaço'),
      findsOneWidget,
      reason: 'a frase que a rede perdeu virava sem conexão, sem a fala dela',
    );
    expect(
      harness.room.chunkKeys,
      hasLength(1),
      reason: 'a frase perdida era reenviada sozinha quando a rede voltava',
    );

    await tester.tap(find.byType(FacilitatorCircle));
    await _passo(tester);
    await tester.tap(find.byType(FacilitatorCircle));
    await _passo(tester);
    expect(
      harness.room.chunkSpans.last,
      '0-4000',
      reason: 'a pausa fica onde estava, e a frase é contada de novo ali',
    );
    closeTheRoom(container);
  });

  testWidgets('three frases in a row whose send fails on the network call no '
      'person', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.failChunkWith = const NetworkFailed('sem rede');

    for (var vez = 1; vez <= 3; vez++) {
      if (vez == 1) {
        await tocar(tester, terminar);
      } else {
        await tester.tap(find.byType(FacilitatorCircle));
        await _passo(tester);
        await tester.tap(find.byType(FacilitatorCircle));
        await _passo(tester);
      }
      await waitFor('a frase $vez voltar da rede', () {
        final estado = container.read(salaSessionProvider);
        return harness.room.chunkKeys.length >= vez && estado.wordlessTelling;
      }, step: () => _passo(tester));
    }
    await _passo(tester);

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(harness.room.chunkKeys, hasLength(3));
    closeTheRoom(container);
  });

  testWidgets('in an English session each refusal says her English line', (
    tester,
  ) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, retroLabelFor('pauseAtTheTap', 'en'));
    await tocar(tester, retroLabelFor('recording', 'en'));
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await _passo(tester);
    await tocar(tester, retroLabelFor('endOfTheRecording', 'en'));
    await tocar(tester, retroLabelFor('endOfTheRecording', 'en'));
    await tocar(tester, retroLabelFor('recording', 'en'));
    await waitFor(
      'o terminei acender',
      () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
      step: () => _passo(tester),
    );
    final aParte = container.read(salaSessionProvider).partes.single;
    harness.voice.refuses.add('');

    Future<void> recusadoCom(CheckRefusal recusa) async {
      harness.room
        ..verdictRefusal = recusa
        ..verdictFixedLine = recusa == CheckRefusal.partUnheard ? 'P2' : ''
        ..verdictUnheardTakeIds = recusa == CheckRefusal.partUnheard
            ? [aParte.takeId!]
            : const [];
      await tester.ensureVisible(byLabel('done'));
      await tester.tap(byLabel('done'));
      await waitFor('a recusa voltar', () {
        final estado = container.read(salaSessionProvider);
        return !estado.btConferindo && estado.btRecusa == recusa;
      }, step: () => _passo(tester));
      await _passo(tester);
    }

    await recusadoCom(CheckRefusal.nothingTranslated);
    expect(find.text('no sentence translated yet'), findsOneWidget);
    await recusadoCom(CheckRefusal.checkUnavailable);
    expect(find.text('couldn\'t check right now — try again'), findsOneWidget);
    await recusadoCom(CheckRefusal.partUnheard);
    expect(
      find.descendant(
        of: find.byType(StatusLines),
        matching: find.text(
          'there is still a part of the recording to listen to',
        ),
      ),
      findsOneWidget,
      reason: 'a sessão em inglês mostrava as linhas dela em português',
    );
    closeTheRoom(container);
  });
}
