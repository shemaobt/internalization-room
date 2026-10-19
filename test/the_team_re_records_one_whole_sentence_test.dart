import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show cabeca, confirmar, entrarNaTraducao, parte, tesoura, tocar;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Finder _circulo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

Future<void> _tocarOCirculo(WidgetTester tester) async {
  await tester.tap(_circulo());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _traduzir(WidgetTester tester) async {
  await _tocarOCirculo(tester);
  await _tocarOCirculo(tester);
  await tocar(tester, confirmar);
}

Future<ProviderContainer> _quatroFrases(
  WidgetTester tester,
  SalaHarness harness, {
  bool emWav = true,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (emWav) {
    harness.recorder.rehearsalSpeaks = aSpokenWav(length: parte);
  }
  final container = await entrarNaTraducao(tester, harness);
  for (var contada = 1; contada <= 2; contada++) {
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await _traduzir(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await _traduzir(tester);
    await waitFor(
      'a parte $contada ficar contada em duas frases',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          contada * 2,
      step: () => _passo(tester),
    );
  }
  await _passo(tester);
  return container;
}

Finder _naLista(String label) =>
    find.descendant(of: find.byType(FraseList), matching: byLabel(label));

bool _acesa(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_naLista(label)).properties.enabled ?? false;

void main() {
  testWidgets('every frase of a wav recording offers its whole sentence to '
      'be recorded again, lit', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);

    for (var n = 1; n <= 4; n++) {
      expect(_naLista('regravar a frase $n'), findsOneWidget);
      expect(
        _acesa(tester, 'regravar a frase $n'),
        isTrue,
        reason:
            'a frase $n não oferecia regravar, e um detalhe custava a parte',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('a recording not in wav offers no sentence on any row', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness, emWav: false);

    expect(find.byType(FraseList), findsOneWidget);
    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason: 'a sala não pode trocar uma frase de uma parte que não é wav',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('the first re-record of a visit says her two lines with the '
      'sentence as it is between them, then waits for the circle', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    harness.voice.fixedLines.clear();

    await tocar(tester, 'regravar a frase 3');

    expect(harness.voice.fixedLines, [('N6', 'pt')]);
    expect(
      harness.playback.ranges.last,
      '0-4000',
      reason: 'a frase como está agora não tocava antes de pedirem a nova',
    );
    expect(find.text('gravem a frase inteira'), findsNothing);

    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('N6', 'pt'), ('N7', 'pt')],
      reason: 'a voz não pedia a frase inteira depois de tocá-la',
    );
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence whose playing never ends goes on to her second line '
      'after its own length and four seconds, not before', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    harness.voice.fixedLines.clear();

    await tocar(tester, 'regravar a frase 3');
    await tester.pump(const Duration(milliseconds: 7500));

    expect(harness.voice.fixedLines, [('N6', 'pt')]);

    await tester.pump(const Duration(milliseconds: 700));

    expect(
      harness.voice.fixedLines,
      [('N6', 'pt'), ('N7', 'pt')],
      reason:
          'um player que não terminava deixava a regravação parada para sempre',
    );
    closeTheRoom(container);
  });

  testWidgets('while a sentence is being recorded again only its own row is '
      'lit, and that button closes it with nothing sent', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(_acesa(tester, 'regravar a frase 1'), isFalse);
    expect(_acesa(tester, 'regravar a frase 3'), isTrue);
    harness.voice.fixedLines.clear();

    await tocar(tester, 'regravar a frase 3');

    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsNothing,
      reason:
          'a regravação começada não tinha saída a não ser deixar a passagem',
    );
    expect(harness.voice.fixedLines, isEmpty);
    expect(_acesa(tester, 'regravar a frase 1'), isTrue);
    closeTheRoom(container);
  });

  Future<void> regravarAte(
    WidgetTester tester,
    SalaHarness harness,
    int n,
  ) async {
    await tocar(tester, 'regravar a frase $n');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);
  }

  testWidgets('a second re-record in the same visit says nothing and still '
      'plays the sentence, with the hint standing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await regravarAte(tester, harness, 3);
    await tocar(tester, 'regravar a frase 3');
    harness.voice.fixedLines.clear();
    final tocadas = harness.playback.ranges.length;

    await regravarAte(tester, harness, 2);

    expect(
      harness.voice.fixedLines,
      isEmpty,
      reason: 'as duas falas voltavam em cada regravação da mesma visita',
    );
    expect(harness.playback.ranges.skip(tocadas), ['4000-10000']);
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  testWidgets('a new visit to the telling says her two lines again', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await regravarAte(tester, harness, 3);
    await tocar(tester, 'regravar a frase 3');
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    await _passo(tester);
    notifier.startRetro();
    await _passo(tester);
    harness.voice.fixedLines.clear();

    await regravarAte(tester, harness, 3);

    expect(harness.voice.fixedLines, [('N6', 'pt'), ('N7', 'pt')]);
    closeTheRoom(container);
  });

  Finder pista() => find.descendant(
    of: find.byType(RetroView),
    matching: find.text('gravem a frase inteira'),
  );

  Finder naLinha(String texto) =>
      find.descendant(of: find.byType(FraseList), matching: find.text(texto));

  testWidgets('the circle records the whole sentence, and a sentence kept '
      'opens its review on the row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await regravarAte(tester, harness, 3);

    await _tocarOCirculo(tester);

    expect(harness.recorder.lastOwner, MicOwner.rehearsal);
    harness.recorder.rehearsalSpeaks = aSpokenWav(
      length: const Duration(seconds: 2),
    );
    await _tocarOCirculo(tester);
    await _passo(tester);
    final gravada = harness.recorder.lastPath;

    expect(_naLista('Ouvir — 3'), findsOneWidget);
    expect(naLinha('gravar de novo'), findsOneWidget);
    expect(naLinha('usar esta'), findsOneWidget);
    expect(pista(), findsNothing);

    await tocar(tester, 'Ouvir — 3');
    expect(
      harness.playback.played.last,
      gravada,
      reason: 'a equipe não podia ouvir a frase que acabou de gravar',
    );

    await tester.tap(naLinha('gravar de novo'));
    await _passo(tester);

    expect(naLinha('usar esta'), findsNothing);
    expect(pista(), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a tap shorter than a third of a second is an accident and '
      'opens no review', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);
    harness.recorder.rehearsalSpeaks = aSpokenWav(
      length: const Duration(milliseconds: 200),
    );

    await _tocarOCirculo(tester);
    await _passo(tester);

    expect(
      naLinha('usar esta'),
      findsNothing,
      reason: 'um toque sem querer virava uma frase para enviar',
    );
    expect(pista(), findsOneWidget);
    closeTheRoom(container);
  });

  Future<void> gravarAFrase(
    WidgetTester tester,
    SalaHarness harness,
    int n, {
    Duration dura = const Duration(seconds: 2),
  }) async {
    await regravarAte(tester, harness, n);
    await _tocarOCirculo(tester);
    harness.recorder.rehearsalSpeaks = aSpokenWav(length: dura);
    await _tocarOCirculo(tester);
    await _passo(tester);
  }

  testWidgets('«usar esta» sends the sentence under the id its recording was '
      'kept by, and the row says «enviando…» while it is in the air', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.holdTheSentence = Completer<void>();

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    final guardada = (harness.takes as FakeTakeQueue).rows.singleWhere(
      (row) => row.kind == 'frase',
    );
    expect(harness.room.sentencesSent, [
      (sentenceId: guardada.id, segmentId: 'trecho-3'),
    ]);
    expect(
      naLinha('enviando…'),
      findsOneWidget,
      reason: 'a frase ia para a sala sem a equipe ver que estava indo',
    );
    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    closeTheRoom(container);
  });
}
