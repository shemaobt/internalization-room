import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        confirmar,
        conferir,
        entrarNaTraducao,
        gravar,
        gravarATraducao,
        ouvir,
        parte,
        passaDoCursor,
        tesoura,
        terminar,
        tocar;

const linha = 'Não entendi — traduzam de novo esse pedaço';
const line = 'I didn\'t catch that — translate that piece again';

const vazia = Refused(RefusalCode.wordlessTelling);

String rotuloDoCirculo(WidgetTester tester) => tester
    .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
    .semanticLabel;

Future<void> tocarOCirculo(WidgetTester tester) async {
  await tester.tap(find.byType(FacilitatorCircle));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> contarDeNovo(WidgetTester tester) async {
  await tocarOCirculo(tester);
  await tocarOCirculo(tester);
}

Future<void> cortarEGravar(WidgetTester tester, SalaHarness harness) async {
  harness.playback.at = cabeca;
  await tocar(tester, tesoura);
  await gravarATraducao(tester);
}

Future<void> confirmarSemPalavras(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.failChunkWith = vazia;
  await tocar(tester, confirmar);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> ateACapturaVazia(WidgetTester tester, SalaHarness harness) async {
  await cortarEGravar(tester, harness);
  await confirmarSemPalavras(tester, harness);
}

Future<void> confirmarComPalavras(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.failChunkWith = null;
  await tocar(tester, confirmar);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<String?> ateOTrechoNomeado(
  WidgetTester tester,
  SalaHarness harness,
) async {
  await cortarEGravar(tester, harness);
  final daPrimeira = harness.recorder.lastPath;
  await tocar(tester, confirmar);
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
  await gravarATraducao(tester);
  await tocar(tester, confirmar);
  harness.room
    ..verdictChecked = false
    ..verdictUntoldSegmentId = 'trecho-1';
  await tocar(tester, conferir);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
  harness.room.verdictUntoldSegmentId = null;
  await gravarATraducao(tester);
  return daPrimeira;
}

void main() {
  testWidgets('a first telling the room makes nothing of keeps the room paused '
      'on the stretch, shows her line and plays nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await cortarEGravar(tester, harness);
    final falado = harness.voice.played.length;
    final tocado = harness.playback.played.length;

    await confirmarSemPalavras(tester, harness);

    expect(byLabel(linha), findsWidgets);
    expect(harness.voice.played, hasLength(falado), reason: 'nada é falado');
    expect(harness.playback.played, hasLength(tocado));
    expect(harness.playback.sounding, isFalse, reason: 'a parte segue parada');
    expect(harness.room.chunksSent, 0, reason: 'nenhum trecho foi guardado');

    await contarDeNovo(tester);
    await confirmarComPalavras(tester, harness);

    expect(harness.room.chunkSpans, [
      '0-4000',
    ], reason: 'o cursor ficou no trecho');
    closeTheRoom(container);
  });

  testWidgets('a tap after an empty telling opens the microphone for the same '
      'stretch', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final gravacao = harness.room.takeIds.first;
    await ateACapturaVazia(tester, harness);
    final capturas = harness.recorder.captures;

    await tocarOCirculo(tester);

    expect(harness.recorder.captures, capturas + 1);

    await tocarOCirculo(tester);
    await confirmarComPalavras(tester, harness);

    expect(harness.room.chunkSpans.last, '0-4000');
    expect(harness.room.chunkTakes.last, gravacao);
    closeTheRoom(container);
  });

  testWidgets('a replacement the room makes nothing of leaves the earlier '
      'telling and does not resume the part', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final sala = container.read(salaSessionProvider.notifier);
    final daPrimeira = await ateOTrechoNomeado(tester, harness);
    final pedidos = harness.room.replaceKeys.length;
    final falado = harness.voice.played.length;
    final tocado = harness.playback.played.length;

    harness.room.failReplaceWith = vazia;
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(byLabel(linha), findsWidgets);
    expect(harness.room.replaceKeys, hasLength(pedidos + 1));
    expect(harness.playback.played, hasLength(tocado), reason: 'nada toca');
    expect(harness.playback.sounding, isFalse);
    expect(harness.voice.played, hasLength(falado), reason: 'nada é falado');

    sala.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.playback.played.last,
      daPrimeira,
      reason: 'o trecho segue com a tradução de antes',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room.failReplaceWith = null;
    await contarDeNovo(tester);
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.replacesAsked.last,
      'trecho-1@${harness.room.takeIds.first}:0-4000',
      reason: 'o círculo reabre o microfone no trecho nomeado',
    );
    closeTheRoom(container);
  });

  testWidgets('a telling with words is told as before', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await cortarEGravar(tester, harness);

    await confirmarComPalavras(tester, harness);

    expect(harness.room.chunkSpans, ['0-4000']);
    expect(harness.playback.sounding, isTrue, reason: 'a parte segue tocando');
    expect(harness.playback.playedFrom.last, cabeca);
    expect(byLabel(linha), findsNothing);
    harness.playback.at = cabeca + passaDoCursor;
    await tester.pump(passaDoCursor);
    expect(rotuloDoCirculo(tester), gravar);
    closeTheRoom(container);
  });

  testWidgets('an empty telling is never counted toward calling a person', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await ateACapturaVazia(tester, harness);

    for (var vez = 0; vez < 2; vez++) {
      await contarDeNovo(tester);
      await confirmarSemPalavras(tester, harness);
    }

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(rotuloDoCirculo(tester), isNot(circleLabelFor('needsPerson', 'pt')));
    expect(byLabel(linha), findsWidgets);

    await contarDeNovo(tester);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'a recusa que conta é a primeira, não a quarta',
    );

    await confirmarComPalavras(tester, harness);

    expect(harness.room.chunkSpans, ['0-4000']);
    expect(harness.playback.sounding, isTrue);
    expect(byLabel(linha), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('after an empty telling only the circle is offered', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await cortarEGravar(tester, harness);
    final recusada = harness.recorder.lastPath;

    await confirmarSemPalavras(tester, harness);
    await letTheRehearsalReachTheRoom(tester);

    expect(aceso(tester, confirmar), isFalse);
    expect(aceso(tester, ouvir), isFalse);
    expect(aceso(tester, tesoura), isFalse);
    expect(rotuloDoCirculo(tester), linha);
    expect(
      [
        for (final guardada in (harness.takes as FakeTakeQueue).rows)
          if (guardada.path == recusada) guardada.kind,
      ],
      ['retro'],
      reason: 'a cópia da gravação recusada fica na fila',
    );
    closeTheRoom(container);
  });

  testWidgets('the refused recording\'s file goes with it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await cortarEGravar(tester, harness);
    final recusada = harness.recorder.lastPath;

    await confirmarSemPalavras(tester, harness);

    expect(harness.recorder.deleted, contains(recusada));
    closeTheRoom(container);
  });

  testWidgets('a correction answered after an empty one lands as the '
      'team\'s own when the room says the stretch moved on', (tester) async {
    final harness = SalaHarness(
      filaEmMemoria: true,
      retryBackoff: const [Duration(seconds: 2)],
    )..room.forgetsTheKeys = true;
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final fila = harness.takes as FakeTakeQueue;
    await ateOTrechoNomeado(tester, harness);
    harness.room.failReplaceWith = vazia;
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));
    harness.room.failReplaceWith = null;
    await contarDeNovo(tester);
    final contada = harness.recorder.lastPath;

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var passo = 0; passo < 8; passo++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(aceso(tester, confirmar), isFalse, reason: 'a contada pousou');
    expect(
      container.read(salaSessionProvider).btTrechos.map((t) => t.segmentId),
      harness.room.segments.map((s) => s.segmentId),
    );
    expect([
      for (final guardada in fila.rows)
        if (guardada.path == contada) guardada.kind,
    ], isEmpty);
    closeTheRoom(container);
  });

  Future<void> aSalaParaDeVez(WidgetTester tester, SalaHarness harness) async {
    harness.room.serverHalt = HaltKind.blocking;
    for (var passo = 0; passo < 40; passo++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('under a person sign the circle says the sign, not her line', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await ateACapturaVazia(tester, harness);
    expect(byLabel(linha), findsWidgets);

    await aSalaParaDeVez(tester, harness);

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(rotuloDoCirculo(tester), circleLabelFor('needsPerson', 'pt'));
    closeTheRoom(container);
  });

  testWidgets('a blocking halt hides her mark', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await ateACapturaVazia(tester, harness);
    expect(byLabel(linha), findsWidgets);

    await aSalaParaDeVez(tester, harness);

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(byLabel(linha), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('her line leaves when the microphone reopens', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await ateACapturaVazia(tester, harness);
    expect(byLabel(linha), findsWidgets);

    await tocarOCirculo(tester);

    expect(byLabel(linha), findsNothing);
    expect(rotuloDoCirculo(tester), terminar);
    closeTheRoom(container);
  });

  testWidgets('her line leaves with the team leaving the Back-translation', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final sala = container.read(salaSessionProvider.notifier);
    await ateACapturaVazia(tester, harness);
    expect(byLabel(linha), findsWidgets);

    sala.leaveThePassage();
    await tester.pump(const Duration(milliseconds: 300));
    await sala.returnToTheLeftEntry();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(RetroView), findsOneWidget);
    expect(byLabel(linha), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('asking for the verdict takes her line away', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = parte - const Duration(milliseconds: 500);
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await confirmarComPalavras(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await gravarATraducao(tester);
    await confirmarSemPalavras(tester, harness);
    expect(byLabel(linha), findsWidgets);
    expect(aceso(tester, conferir), isTrue);

    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(byLabel(linha), findsNothing);
    expect(rotuloDoCirculo(tester), isNot(linha));
    closeTheRoom(container);
  });

  testWidgets('the mark and the circle say her line to VoiceOver, and nothing '
      'on screen is written', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    await ateACapturaVazia(tester, harness);

    expect(byLabel(linha), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    closeTheRoom(container);
  });

  testWidgets('in an English session the mark and the circle say her line in '
      'English', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocar(tester, 'Cut here');
    await tocar(tester, 'Tap to record this stretch\'s translation');
    await tocar(tester, 'Tap when you finish');
    harness.room.failChunkWith = vazia;
    await tocar(tester, 'Confirm the translation and go on');
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel(line), findsNWidgets(2));
    closeTheRoom(container);
  });
}
