import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        confirmar,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravar,
        gravarATraducao,
        parte,
        tesoura,
        tocar;

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
  await tocar(tester, tesoura);
  await gravarATraducao(tester);
  await tocar(tester, confirmar);
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
        lida('NOTHING_TRANSLATED'),
        lida('CHECK_UNAVAILABLE'),
      ],
      [
        CheckRefusal.fraseAwaiting,
        CheckRefusal.partUnheard,
        CheckRefusal.nothingTranslated,
        CheckRefusal.checkUnavailable,
      ],
      reason: 'o app não lia o campo refusal, e toda recusa virava silêncio',
    );
    expect(lida('STRETCH_UNTRANSLATED'), isNull);
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

  testWidgets('three checks in a row whose model cannot answer call no person '
      'and never show the room as gone', (tester) async {
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
    expect(
      estado.offline,
      isFalse,
      reason: 'a conferência sem modelo vinha como 502 e virava sem conexão',
    );
    expect(estado.unreachable, isFalse);
    expect(harness.room.playedByTakeSent, hasLength(3));
    closeTheRoom(container);
  });

  testWidgets('a part not heard through is refused with her line on the '
      'screen, her P2 by its name, and that part played from its start', (
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

    await _recusado(tester, container);

    expect(
      find.text('ainda falta ouvir um trecho da gravação'),
      findsOneWidget,
      reason: 'a parte não ouvida tinha a fala dela e nada na tela',
    );
    expect(
      [for (final (linha, _) in harness.voice.fixedLines.skip(linhas)) linha],
      ['P2'],
      reason: 'a fala da parte não ouvida é a P2 dela, pedida pelo nome',
    );
    expect(harness.playback.played.last, aParte.path);
    expect(harness.playback.playedFrom.last, Duration.zero);
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
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
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

    await gravarATraducao(tester, circulo: gravar);
    harness.room.failChunkWith = const Refused(RefusalCode.wordlessTelling);
    await tocar(tester, confirmar);
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
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    harness.room.failChunkWith = const NetworkFailed('sem rede');
    await tocar(tester, confirmar);
    await waitFor('a frase voltar da rede', () {
      final estado = container.read(salaSessionProvider);
      return estado.wordlessTelling || estado.unreachable;
    }, step: () => _passo(tester));
    harness.room.failChunkWith = null;
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      find.text('não entendi — traduzam de novo esse pedaço'),
      findsOneWidget,
      reason: 'a frase que a rede perdeu virava sem conexão, sem a fala dela',
    );
    expect(estado.offline, isFalse);
    expect(estado.unreachable, isFalse);
    expect(
      harness.room.chunkKeys,
      hasLength(1),
      reason: 'a frase perdida era reenviada sozinha quando a rede voltava',
    );

    await tester.tap(find.byType(FacilitatorCircle));
    await _passo(tester);
    await tester.tap(find.byType(FacilitatorCircle));
    await _passo(tester);
    await tocar(tester, confirmar);
    expect(
      harness.room.chunkSpans.last,
      '0-4000',
      reason: 'a pausa fica onde estava, e a frase é contada de novo ali',
    );
    closeTheRoom(container);
  });

  testWidgets('three frases in a row whose send fails on the network call no '
      'person and never show the room as gone', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    harness.room.failChunkWith = const NetworkFailed('sem rede');

    for (var vez = 1; vez <= 3; vez++) {
      if (vez > 1) {
        await tester.tap(find.byType(FacilitatorCircle));
        await _passo(tester);
        await tester.tap(find.byType(FacilitatorCircle));
        await _passo(tester);
      }
      await tocar(tester, confirmar);
      await waitFor('a frase $vez voltar da rede', () {
        final estado = container.read(salaSessionProvider);
        return harness.room.chunkKeys.length >= vez &&
            (estado.wordlessTelling || estado.unreachable);
      }, step: () => _passo(tester));
    }
    await _passo(tester);

    final estado = container.read(salaSessionProvider);
    expect(
      estado.offline,
      isFalse,
      reason: 'cada frase que a rede perdia punha a sala em sem conexão',
    );
    expect(estado.needsPerson, isFalse);
    expect(harness.room.chunkKeys, hasLength(3));
    closeTheRoom(container);
  });
}
