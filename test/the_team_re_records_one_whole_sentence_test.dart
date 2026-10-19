import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, cabeca, confirmar, entrarNaTraducao, parte, tesoura, tocar;

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

const _daSala = [
  SegmentView(
    segmentId: 'trecho-1',
    takeId: 'gravacao-1',
    startsMs: 0,
    endsMs: 4000,
    frase: 1,
  ),
  SegmentView(
    segmentId: 'trecho-2',
    takeId: 'gravacao-1',
    startsMs: 4000,
    endsMs: 10000,
    frase: 2,
  ),
  SegmentView(
    segmentId: 'trecho-3',
    takeId: 'gravacao-2',
    startsMs: 0,
    endsMs: 4000,
    frase: 3,
  ),
  SegmentView(
    segmentId: 'trecho-4',
    takeId: 'gravacao-2',
    startsMs: 4000,
    endsMs: 10000,
    frase: 4,
  ),
];

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness, {
  String? aguardando,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1221');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final partes = [
    for (final n in [1, 2])
      KeptTake(
        scopeId: KeptScope.parte(n),
        path: (File(
          '${pasta.path}/p$n.wav',
        )..writeAsBytesSync(aSpokenWav(length: parte))).path,
        takeId: 'gravacao-$n',
      ),
  ];
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: partes,
  );
  harness.room
    ..segments.addAll(_daSala)
    ..takes.addAll([
      for (final n in [1, 2])
        TakeView(
          takeId: 'gravacao-$n',
          kind: 'ensaio',
          scope: KeptScope.parte(n),
          ordinal: n,
        ),
    ])
    ..retroSoFar = BackTranslationProgress(
      segments: _daSala,
      awaitingSegmentId: aguardando,
    );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'a tradução voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length == 4,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
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
    expect(
      aceso(tester, 'terminei'),
      isFalse,
      reason: 'terminei ficava aceso no meio de uma regravação',
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

  bool guardada(SalaHarness harness) =>
      (harness.takes as FakeTakeQueue).rows.any((row) => row.kind == 'frase');

  testWidgets('a sentence over four megabytes is refused before it is sent, '
      'with her line on the row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);
    harness.recorder
      ..rehearsalSpeaks = Uint8List(4 * 1024 * 1024 + 1)
      ..rehearsalSpeaksAs = 'wav';
    await _tocarOCirculo(tester);
    await _passo(tester);

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    expect(naLinha('frase longa demais — regravem a cena'), findsOneWidget);
    expect(
      harness.room.sentencesSent,
      isEmpty,
      reason: 'a frase grande demais subia e só a sala dizia que não cabia',
    );
    expect(guardada(harness), isFalse);
    closeTheRoom(container);
  });

  testWidgets('the room\'s own refusal of a sentence too long says the same '
      'line', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const Refused('SENTENCE_TOO_LONG'));

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    expect(naLinha('frase longa demais — regravem a cena'), findsOneWidget);
    expect(guardada(harness), isFalse);
    closeTheRoom(container);
  });

  for (final code in ['SENTENCE_TOO_SHORT', 'SENTENCE_FORMAT_DIFFERS']) {
    testWidgets('a sentence the room refuses as $code goes back to «gravem a '
        'frase inteira», and nothing of it is kept', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrases(tester, harness);
      await gravarAFrase(
        tester,
        harness,
        3,
        dura: const Duration(milliseconds: 300),
      );
      harness.room.sentenceAnswersFirst.add(Refused(code));

      await tester.tap(naLinha('usar esta'));
      await _passo(tester);
      await _passo(tester);

      expect(
        pista(),
        findsOneWidget,
        reason: 'um toque curto demais ficava preso esperando a sala',
      );
      expect(naLinha('usar esta'), findsNothing);
      expect(guardada(harness), isFalse);
      closeTheRoom(container);
    });
  }

  testWidgets('a sentence whose send fails stays on the tablet, its row says '
      'so, and one tap sends that same recording again, laid in once', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      _naLista(falhou),
      findsOneWidget,
      reason: 'a frase que não subiu sumia sem a equipe saber',
    );
    expect(guardada(harness), isTrue);
    expect(_naLista('regravar a frase 1'), findsNothing);

    await tocar(tester, falhou);
    await _passo(tester);

    final enviadas = harness.room.sentencesSent;
    expect(enviadas, hasLength(2));
    expect(enviadas.last, enviadas.first);
    expect(harness.room.sentencesLaid, [enviadas.first.sentenceId]);
    expect(_naLista(falhou), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a sentence held on the tablet comes back with its session, and '
      'one tap sends that recording under the id it was kept by', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-1221-frase');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final guardada = await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: '3',
    );
    final container = await _voltaATraducao(tester, harness);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      _naLista(falhou),
      findsOneWidget,
      reason: 'a frase guardada sumia da tela depois de recarregar',
    );

    await tocar(tester, falhou);
    await _passo(tester);

    expect(harness.room.sentencesSent, [
      (sentenceId: guardada.id, segmentId: 'trecho-3'),
    ]);
    expect(harness.room.sentencesLaid, [guardada.id]);
    closeTheRoom(container);
  });

  testWidgets('a sentence laid in is announced in her words and plays in its '
      'place on the new take, with a second and a half around it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    final antes = container.read(salaSessionProvider).partes.first;
    await gravarAFrase(tester, harness, 2);
    harness.voice.fixedLines.clear();

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('N4', 'pt')],
      reason: 'a frase nova entrava no lugar sem a voz dizer nada',
    );
    final agora = container.read(salaSessionProvider).partes.first;
    expect(agora.takeId, harness.room.takes.last.takeId);
    expect(agora.path, isNot(antes.path));
    expect(harness.playback.played.last, agora.path);
    expect(
      harness.playback.ranges.last,
      '2500-8700',
      reason: 'a frase nova não tocava no lugar dela, com o que vem em volta',
    );
    closeTheRoom(container);
  });

  testWidgets('a new sentence at the very start of its part plays from the '
      'start, never from before it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(harness.playback.ranges.last, '0-4700');
    closeTheRoom(container);
  });

  Future<void> deitarAFrase(
    WidgetTester tester,
    SalaHarness harness,
    int n,
  ) async {
    await gravarAFrase(tester, harness, n);
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);
    harness.playback.finishPlayback();
    await _passo(tester);
  }

  testWidgets(
    'until its translation, the re-recorded frase says so, «terminei» '
    'is closed and no other frase offers «regravar»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrases(tester, harness);
      await deitarAFrase(tester, harness, 2);

      expect(
        naLinha('regravada — traduzam esta frase'),
        findsOneWidget,
        reason: 'a frase regravada parecia já traduzida',
      );
      for (final n in [1, 3, 4]) {
        expect(_naLista('regravar a frase $n'), findsNothing);
      }
      expect(_naLista('regravar a frase 2'), findsOneWidget);
      expect(
        aceso(tester, 'terminei'),
        isFalse,
        reason: 'terminei abria antes de traduzirem a frase nova',
      );
      final pedidos = harness.room.calls.length;
      await tocar(tester, 'terminei');
      expect(
        harness.room.calls.skip(pedidos),
        isNot(contains('finishBackTranslation')),
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the circle translates the re-recorded frase at exactly its new '
      'span, and once that lands the frase stops waiting', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await deitarAFrase(tester, harness, 2);
    final nova = harness.room.takes.last.takeId;

    await _traduzir(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.room.replacesAsked,
      ['trecho-2@$nova:4000-7200'],
      reason: 'o círculo abria outra frase enquanto a regravada esperava',
    );
    expect(naLinha('regravada — traduzam esta frase'), findsNothing);
    expect(container.read(salaSessionProvider).btFraseQueAguarda, isNull);
    expect(harness.room.calls, contains('finishBackTranslation'));
    closeTheRoom(container);
  });

  test('the session read hands over the frase whose sentence awaits its '
      'translation, and none when nothing awaits', () {
    expect(
      BackTranslationProgress.fromJson({
        'segments': const [],
        'awaiting_segment_id': 'trecho-3',
      }).awaitingSegmentId,
      'trecho-3',
      reason: 'a frase que esperava a tradução se perdia ao recarregar',
    );
    expect(
      BackTranslationProgress.fromJson({
        'segments': const [],
      }).awaitingSegmentId,
      isNull,
    );
  });

  testWidgets('coming back to a frase that awaits its translation, the voice '
      'says so and that frase opens', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-3',
    );
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      contains(('N5', 'pt')),
      reason: 'a equipe voltava e ninguém lembrava da frase regravada',
    );
    expect(harness.playback.ranges.last, '0-4000');
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btFraseQueAguarda, 'trecho-3');
    expect(aqui.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-3');
    expect(naLinha('regravada — traduzam esta frase'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('the new sentence played in its place counts as heard on the '
      'new take, and the check is told so', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await deitarAFrase(tester, harness, 2);
    final nova = harness.room.takes.last.takeId;

    await _traduzir(tester);
    await _passo(tester);
    await _passo(tester);

    final relato = harness.room.playedByTakeSent.last;
    expect(
      [
        for (final parte in relato)
          if (parte['take_id'] == nova)
            '${parte['played_ranges']} em ${parte['clip_duration_ms']}',
      ],
      ['[[2500, 8700]] em 10000'],
      reason:
          'a frase nova tocada no lugar não contava como ouvida, e a sala '
          'recusava o terminei',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence the room refuses because another frase awaits stays '
      'on the tablet, and the voice opens the frase that awaits', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room
      ..awaitingSegmentId = 'trecho-1'
      ..sentenceAnswersFirst.add(const Refused('ANOTHER_SENTENCE_AWAITS'));
    harness.voice.fixedLines.clear();

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('N5', 'pt')],
      reason: 'a sala recusava a frase e a equipe não sabia qual faltava',
    );
    expect(harness.playback.ranges.last, '0-4000');
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btFraseQueAguarda, 'trecho-1');
    expect(aqui.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-1');
    expect(guardada(harness), isTrue);
    expect(aqui.btFraseGuardada, 3);
    closeTheRoom(container);
  });

  testWidgets('a «terminei» the room refuses because a frase awaits marks '
      'that frase as re-recorded and takes «regravar» off the others', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    harness.room
      ..verdictRefusal = CheckRefusal.fraseAwaiting
      ..verdictFixedLine = 'N5'
      ..verdictUntoldSegmentId = 'trecho-1'
      ..awaitingSegmentId = 'trecho-1';

    await tocar(tester, 'terminei');
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
    await _passo(tester);

    expect(
      naLinha('regravada — traduzam esta frase'),
      findsOneWidget,
      reason: 'a frase que outro aparelho regravou parecia já traduzida',
    );
    expect(_naLista('regravar a frase 2'), findsNothing);
    closeTheRoom(container);
  });

  for (final code in [
    'STRETCH_NO_LONGER_COUNTS',
    'PART_NOT_WAV',
    'SENTENCE_ID_REUSED',
  ]) {
    testWidgets('a sentence the room refuses as $code can never be laid in: '
        'it is dropped and the stretches are read again', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrases(tester, harness);
      await gravarAFrase(tester, harness, 3);
      harness.room.sentenceAnswersFirst.add(Refused(code));

      await tester.tap(naLinha('usar esta'));
      await _passo(tester);
      await _passo(tester);

      expect(
        guardada(harness),
        isFalse,
        reason: 'uma frase que a sala nunca vai aceitar ficava para sempre',
      );
      final aqui = container.read(salaSessionProvider);
      expect((aqui.btFraseGuardada, aqui.btRegravacao), (null, null));
      final chamadas = harness.room.calls;
      expect(
        chamadas.sublist(chamadas.lastIndexOf('reRecordTheSentence')),
        contains('fetchState'),
      );
      closeTheRoom(container);
    });
  }

  testWidgets('at conferida the frase whose nuance the verdict named starts '
      'its re-record, and the circle records it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    harness.room
      ..verdictChecked = true
      ..verdictNamedNuance = const BtFinding(
        kind: BtFindingKind.nuance,
        frase: 3,
        segmentId: 'trecho-3',
      );
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    await _passo(tester);

    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);

    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.gravando,
      reason: 'na tradução conferida o círculo não atendia a regravação',
    );
    expect(harness.recorder.lastOwner, MicOwner.rehearsal);
    final circulo = tester.widget<FacilitatorCircle>(_circulo());
    expect(
      (circulo.answersATouch, circulo.voice, circulo.tongue),
      (true, VoiceState.listening, Tongue.motherTongue),
      reason:
          'o círculo gravava a frase parecendo parado, ou na cor da '
          'tradução em português',
    );
    expect(circulo.semanticLabel, 'gravem a frase inteira');
    closeTheRoom(container);
  });
}
