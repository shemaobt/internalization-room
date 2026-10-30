import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/listen_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheBackTranslation,
        onTheCircle,
        pressTheApproval;
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, cabeca, entrarNaTraducao, parte, tocar;

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
  await _traduzirDeNovo(tester);
}

Future<void> _traduzirDeNovo(WidgetTester tester) async {
  await _tocarOCirculo(tester);
  await _tocarOCirculo(tester);
}

Future<ProviderContainer> quatroFrasesEmWav(
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
    await _traduzir(tester);
    harness.playback.at = parte;
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
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
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

const _renumeradas = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-2',
      takeId: 'gravacao-1',
      startsMs: 4000,
      endsMs: 10000,
      frase: 1,
    ),
    SegmentView(
      segmentId: 'trecho-3',
      takeId: 'gravacao-2',
      startsMs: 0,
      endsMs: 4000,
      frase: 2,
    ),
    SegmentView(
      segmentId: 'trecho-4',
      takeId: 'gravacao-2',
      startsMs: 4000,
      endsMs: 10000,
      frase: 3,
    ),
  ],
);

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness, {
  String? aguardando,
  List<SegmentView> regravadas = const [],
  Grain? grao,
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
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: partes,
    grain: grao,
  );
  await holdTheSession(harness, row);
  harness.room
    ..grain = grao
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
      stale: regravadas,
    );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  await intoTheBackTranslation(
    container.read(salaSessionProvider.notifier),
    () => container.read(salaSessionProvider),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await waitFor(
    'a tradução voltar com as frases que a sala guardou',
    () => container.read(salaSessionProvider).btTrechos.length == 4,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

Finder _naLista(String label) =>
    find.descendant(of: find.byType(FraseList), matching: byLabel(label));

bool _acesa(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_naLista(label)).properties.enabled ?? false;

Finder _recomecoArmado() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label ?? '').startsWith(
        'toque de novo para apagar as',
      ),
);

double _recomecoDesenhado(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: byLabel('recomeçar a tradução'),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  testWidgets('every frase of a wav recording offers its whole sentence to '
      'be recorded again, lit', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);

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

  testWidgets('«regravar a frase N» is pressed while its sentence is being '
      'recorded again, and not pressed when it is only offered', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    bool apertada(String label) => isSemantics(
      hasToggledState: true,
      isToggled: true,
    ).matches(tester.getSemantics(_naLista(label)), {});
    bool solta(String label) => isSemantics(
      hasToggledState: true,
      isToggled: false,
    ).matches(tester.getSemantics(_naLista(label)), {});

    expect(
      solta('regravar a frase 3'),
      isTrue,
      reason: 'o VoiceOver não dizia que regravar estava solto',
    );

    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      apertada('regravar a frase 3'),
      isTrue,
      reason: 'o VoiceOver não sabia que a frase 3 estava sendo regravada',
    );
    closeTheRoom(container);
  });

  testWidgets('a recording not in wav offers no sentence on any row', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness, emWav: false);

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
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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

  testWidgets('while a sentence is being recorded again another row\'s '
      '«regravar» offers VoiceOver no tap that does nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      tester.getSemantics(_naLista('regravar a frase 1')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
      reason: 'o VoiceOver oferecia um toque que não fazia nada',
    );
    closeTheRoom(container);
    semantics.dispose();
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    expect(harness.playback.ranges.skip(tocadas), ['4000-9900']);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
    for (final n in [1, 2, 4]) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason: 'regravar seguia oferecido com uma frase a caminho da sala',
      );
    }
    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('while its sentence is sent «regravar a frase N» stays on the '
      'row, pressed, and takes no tap', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.holdTheSentence = Completer<void>();

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    expect(naLinha('enviando…'), findsOneWidget);
    expect(
      _naLista('regravar a frase 3'),
      findsOneWidget,
      reason: 'o botão da frase sumia da linha enquanto ela ia para a sala',
    );
    expect(
      tester.getSemantics(_naLista('regravar a frase 3')),
      isSemantics(
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
      reason:
          'o VoiceOver não ouvia a frase apertada e desligada enquanto ela '
          'era enviada',
    );
    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    closeTheRoom(container);
    semantics.dispose();
  });

  bool guardada(SalaHarness harness) =>
      (harness.takes as FakeTakeQueue).rows.any((row) => row.kind == 'frase');

  testWidgets('a sentence over four megabytes is refused before it is sent, '
      'with her line on the row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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
      final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
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

  bool aoVivo(WidgetTester tester, Finder finder) => tester
      .getSemantics(finder)
      .getSemanticsData()
      .flagsCollection
      .isLiveRegion;

  testWidgets('«enviando…» and then «frase longa demais» are announced as '
      'they come, on the row', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room
      ..holdTheSentence = Completer<void>()
      ..sentenceAnswersFirst.add(const Refused('SENTENCE_TOO_LONG'));

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    expect(
      aoVivo(tester, naLinha('enviando…')),
      isTrue,
      reason: 'o VoiceOver não dizia que a frase estava indo',
    );

    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    await _passo(tester);

    expect(
      aoVivo(tester, naLinha('frase longa demais — regravem a cena')),
      isTrue,
      reason: 'o VoiceOver não dizia que a frase era longa demais',
    );
    closeTheRoom(container);
    semantics.dispose();
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
      scope: 'trecho-3',
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

  testWidgets('while a telling is being recorded, the held sentence rests: '
      'its line is a button that is off, and a tap on it sends nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-2067');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-1',
    );
    await _tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      _acesa(tester, falhou),
      isFalse,
      reason: 'a linha da frase guardada seguia acesa com a gravação aberta',
    );
    await tocar(tester, falhou);
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      isEmpty,
      reason: 'um toque na frase guardada a enviava no meio de uma gravação',
    );
    closeTheRoom(container);
  });

  testWidgets('under a person call the held sentence rests, and a tap on its '
      'line sends nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-2067');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);
    notifier.haltForABrokenBuild();
    await _passo(tester);
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);
    await _passo(tester);
    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      _acesa(tester, falhou),
      isFalse,
      reason: 'a linha da frase guardada seguia acesa com a pessoa chamada',
    );
    await tocar(tester, falhou);
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      isEmpty,
      reason: 'um toque na frase guardada a enviava com a pessoa chamada',
    );
    closeTheRoom(container);
  });

  testWidgets('on the first listen the held sentence rests, and a tap on its '
      'line sends nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.listeningUnheardTakeIds = const ['gravacao-1'];
    final pasta = Directory.systemTemp.createTempSync('sala-2067');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(tester, harness);
    await _passo(tester);
    await _passo(tester);
    expect(container.read(salaSessionProvider).btSoOuvir, isTrue);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      _acesa(tester, falhou),
      isFalse,
      reason: 'a linha da frase guardada seguia acesa na primeira escuta',
    );
    await tocar(tester, falhou);
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      isEmpty,
      reason: 'um toque na frase guardada a enviava na primeira escuta',
    );
    closeTheRoom(container);
  });

  testWidgets('while the sentence\'s microphone records, its «regravar» rests '
      'and a tap on it does not drop the recording', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.gravando,
    );

    expect(
      _acesa(tester, 'regravar a frase 3'),
      isFalse,
      reason: 'regravar seguia aceso com o microfone da frase aberto',
    );
    await tocar(tester, 'regravar a frase 3');
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.gravando,
      reason: 'um toque em regravar largava a gravação da frase no meio',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence held from a gone session is offered in the '
      "passage's next session and sent into that session at its tap", (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = aTempHome('sala-frase-perdida');
    final guardada = await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: null,
      passage: 'Ruth/P01/$testLanguage',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(tester, harness);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(_naLista(falhou), findsOneWidget);

    await tocar(tester, falhou);
    await _passo(tester);

    expect(harness.room.sentencesSent, [
      (sentenceId: guardada.id, segmentId: 'trecho-3'),
    ]);
    expect(harness.room.sentenceSessions, [
      container.read(salaSessionProvider).sessionId,
    ]);
    closeTheRoom(container);
  });

  List<int?> linhasCom(WidgetTester tester, String estado) => [
    for (final linha in tester.widget<FraseList>(find.byType(FraseList)).rows)
      if (linha.estado == estado) linha.n,
  ];

  testWidgets('a sentence held on the tablet and picked back up after the '
      'room renumbered the frases shows on its own stretch and is sent to '
      'it, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    harness.room
      ..retroSoFar = _renumeradas
      ..segments.clear()
      ..segments.addAll(_renumeradas.segments);

    container.read(salaSessionProvider.notifier).leaveThePassage();
    await waitFor(
      'a equipe sair da passagem',
      () => container.read(salaSessionProvider).stage != SalaStage.retro,
      step: () => _passo(tester),
    );
    await _passo(tester);
    unawaited(
      container
          .read(salaSessionProvider.notifier)
          .goConversa(book: 'Ruth', pericope: 'P01'),
    );
    await intoTheBackTranslation(
      container.read(salaSessionProvider.notifier),
      () => container.read(salaSessionProvider),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await waitFor(
      'a tradução voltar com as frases renumeradas',
      () =>
          container.read(salaSessionProvider).stage == SalaStage.retro &&
          container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await _passo(tester);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      linhasCom(tester, falhou),
      [2],
      reason: 'a frase guardada voltava na linha que herdou o número dela',
    );

    await tocar(tester, falhou);
    await _passo(tester);

    expect(
      harness.room.sentencesSent.last.segmentId,
      'trecho-3',
      reason: 'a frase guardada subia para o trecho que herdou o número dela',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence held on the tablet whose stretch the room no longer '
      'has is let go when the passage is picked back up, as hers', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    final semAFrase = [
      for (final (antes, trecho)
          in _daSala.where((trecho) => trecho.segmentId != 'trecho-3').indexed)
        SegmentView(
          segmentId: trecho.segmentId,
          takeId: trecho.takeId,
          startsMs: trecho.startsMs,
          endsMs: trecho.endsMs,
          frase: antes + 1,
        ),
    ];
    harness.room
      ..retroSoFar = BackTranslationProgress(segments: semAFrase)
      ..segments.clear()
      ..segments.addAll(semAFrase);

    container.read(salaSessionProvider.notifier).leaveThePassage();
    await waitFor(
      'a equipe sair da passagem',
      () => container.read(salaSessionProvider).stage != SalaStage.retro,
      step: () => _passo(tester),
    );
    await _passo(tester);
    unawaited(
      container
          .read(salaSessionProvider.notifier)
          .goConversa(book: 'Ruth', pericope: 'P01'),
    );
    await intoTheBackTranslation(
      container.read(salaSessionProvider.notifier),
      () => container.read(salaSessionProvider),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await waitFor(
      'a tradução voltar sem o trecho da frase guardada',
      () =>
          container.read(salaSessionProvider).stage == SalaStage.retro &&
          container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await _passo(tester);

    expect(
      guardada(harness),
      isFalse,
      reason: 'a frase de um trecho que a sala não tem mais voltava guardada',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravar != null) linha.n,
      ],
      [1, 2, 3],
      reason: 'a frase guardada sem linha tirava o regravar de todas',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence held while the room renumbers the frases keeps its '
      'own row, its «regravar» and its armed resend, and is sent to its own '
      'stretch, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'))
      ..retroSoFar = BackTranslationProgress(
        segments: [
          for (final (antes, trecho) in harness.room.segments.skip(1).indexed)
            SegmentView(
              segmentId: trecho.segmentId,
              takeId: trecho.takeId,
              startsMs: trecho.startsMs,
              endsMs: trecho.endsMs,
              told: trecho.told,
              frase: antes + 1,
            ),
        ],
      );
    segura.complete();
    await waitFor(
      'a sala renumerar as frases',
      () => container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => _passo(tester),
    );
    await _passo(tester);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(
      linhasCom(tester, falhou),
      [2],
      reason: 'a frase guardada ficava na linha que herdou o número dela',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravar != null) linha.n,
      ],
      [2],
      reason: 'o regravar da frase guardada ia para a linha do número dela',
    );

    await tocar(tester, falhou);
    const armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
    expect(
      linhasCom(tester, armado),
      [2],
      reason: 'o toque armado acendia na linha que herdou o número dela',
    );
    await tester.pump(const Duration(seconds: 2));
    await tocar(tester, armado);
    await waitFor(
      'a frase subir de novo',
      () => harness.room.sentencesSent.length == 2,
      step: () => _passo(tester),
    );

    expect(
      harness.room.sentencesSent.last.segmentId,
      'trecho-3',
      reason: 'a frase guardada subia para o trecho que herdou o número dela',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence held while the room no longer has its stretch is '
      'let go when the telling is read, and «regravar» comes back to every '
      'row, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'))
      ..retroSoFar = BackTranslationProgress(
        segments: [
          for (final (antes, trecho)
              in harness.room.segments
                  .where((trecho) => trecho.segmentId != 'trecho-3')
                  .indexed)
            SegmentView(
              segmentId: trecho.segmentId,
              takeId: trecho.takeId,
              startsMs: trecho.startsMs,
              endsMs: trecho.endsMs,
              told: trecho.told,
              frase: antes + 1,
            ),
        ],
      );
    segura.complete();
    await waitFor(
      'a sala ler as frases sem a da frase guardada',
      () => container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      guardada(harness),
      isFalse,
      reason: 'a frase de um trecho que a sala não tem mais ficava guardada',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravar != null) linha.n,
      ],
      [1, 2, 3],
      reason: 'a frase guardada sem linha tirava o regravar de todas',
    );
    closeTheRoom(container);
  });

  List<SegmentView> semAPrimeira(SalaHarness harness) => [
    for (final (antes, trecho) in harness.room.segments.skip(1).indexed)
      SegmentView(
        segmentId: trecho.segmentId,
        takeId: trecho.takeId,
        startsMs: trecho.startsMs,
        endsMs: trecho.endsMs,
        told: trecho.told,
        frase: antes + 1,
      ),
  ];

  Future<void> aSalaRenumera(
    WidgetTester tester,
    SalaHarness harness,
    ProviderContainer container,
  ) async {
    harness.room.retroSoFar = BackTranslationProgress(
      segments: semAPrimeira(harness),
    );
    await waitFor(
      'a sala renumerar as frases',
      () => container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => _passo(tester),
    );
    await _passo(tester);
  }

  List<int?> linhasEmRevisao(WidgetTester tester) => [
    for (final linha in tester.widget<FraseList>(find.byType(FraseList)).rows)
      if (linha.revisao != null) linha.n,
  ];

  testWidgets('a sentence under review while the room renumbers the frases '
      'keeps its review on its own row, and «usar esta» sends it to its own '
      'stretch, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await aSalaRenumera(tester, harness, container);

    expect(
      linhasEmRevisao(tester),
      [2],
      reason: 'a revisão da frase ia para a linha que herdou o número dela',
    );

    await tester.tap(naLinha('usar esta'));
    await waitFor(
      'a frase subir',
      () => harness.room.sentencesSent.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.sentencesSent.last.segmentId,
      'trecho-3',
      reason: 'a frase regravada subia para o trecho que herdou o número dela',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence in the air while the room renumbers the frases keeps '
      '«enviando…» and its pressed «regravar» on its own row, as hers', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.holdTheSentence = Completer<void>();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);

    await aSalaRenumera(tester, harness, container);

    expect(
      linhasCom(tester, 'enviando…'),
      [2],
      reason: '«enviando…» ia para a linha que herdou o número da frase',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravando) linha.n,
      ],
      [2],
      reason:
          'o regravar apertado ia para a linha que herdou o número da frase',
    );
    expect(_naLista('regravar a frase 2'), findsOneWidget);
    for (final n in [1, 3]) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason: 'regravar seguia oferecido com uma frase a caminho da sala',
      );
    }
    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('a sentence waiting for its microphone while the room renumbers '
      'the frases is recorded onto its own stretch and reviewed on its own '
      'row, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await regravarAte(tester, harness, 3);

    await aSalaRenumera(tester, harness, container);
    await _tocarOCirculo(tester);
    harness.recorder.rehearsalSpeaks = aSpokenWav(
      length: const Duration(seconds: 2),
    );
    await _tocarOCirculo(tester);
    await _passo(tester);

    final guardada = (harness.takes as FakeTakeQueue).rows.singleWhere(
      (row) => row.kind == 'frase',
    );
    expect(
      guardada.scope,
      'trecho-3',
      reason: 'a gravação era guardada no trecho que herdou o número da frase',
    );
    expect(
      linhasEmRevisao(tester),
      [2],
      reason: 'a revisão da frase ia para a linha que herdou o número dela',
    );
    closeTheRoom(container);
  });

  testWidgets('over an approved draft, the armed «regravar a frase 3» keeps '
      'its armed text on its own row while the room renumbers the frases, and '
      'the second tap there opens its own stretch, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    await waitFor(
      'o rascunho aprovado chegar',
      () => container.read(salaSessionProvider).overAnApprovedDraft,
      step: () => _passo(tester),
    );
    await tocar(tester, 'regravar a frase 3');
    const armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
    expect(_naLista(armado), findsOneWidget);

    await aSalaRenumera(tester, harness, container);

    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravarArmado) linha.n,
      ],
      [2],
      reason: 'o toque armado acendia na linha que herdou o número da frase',
    );
    await tester.pump(const Duration(seconds: 2));
    await tocar(tester, armado);
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btRegravacao?.segmentId,
      'trecho-3',
      reason:
          'o segundo toque abria a regravação no trecho que herdou o número',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravando) linha.n,
      ],
      [2],
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence too long keeps her line on its own row while the '
      'room renumbers the frases, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
    const longa = 'frase longa demais — regravem a cena';
    expect(linhasCom(tester, longa), [3]);

    await aSalaRenumera(tester, harness, container);

    expect(
      linhasCom(tester, longa),
      [2],
      reason:
          '«frase longa demais» ia para a linha que herdou o número da frase',
    );
    closeTheRoom(container);
  });

  Future<void> aSalaPerdeOTrecho(
    WidgetTester tester,
    SalaHarness harness,
    ProviderContainer container,
  ) async {
    harness.room.retroSoFar = BackTranslationProgress(
      segments: [
        for (final (antes, trecho)
            in harness.room.segments
                .where((trecho) => trecho.segmentId != 'trecho-3')
                .indexed)
          SegmentView(
            segmentId: trecho.segmentId,
            takeId: trecho.takeId,
            startsMs: trecho.startsMs,
            endsMs: trecho.endsMs,
            told: trecho.told,
            frase: antes + 1,
          ),
      ],
    );
    await waitFor(
      'a sala ler as frases sem o trecho da regravação',
      () => container.read(salaSessionProvider).btTrechos.length == 3,
      step: () => _passo(tester),
    );
    await _passo(tester);
  }

  testWidgets('a sentence under review whose stretch the room no longer has '
      'is let go when the telling is read, and «regravar» comes back to '
      'every row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await aSalaPerdeOTrecho(tester, harness, container);

    expect(
      container.read(salaSessionProvider).btRegravacao,
      isNull,
      reason:
          'a regravação de um trecho que a sala não tem mais ficava aberta '
          'sem linha nenhuma',
    );
    expect(
      guardada(harness),
      isFalse,
      reason: 'a gravação de um trecho que a sala não tem mais ficava na fila',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.onRegravar != null) linha.n,
      ],
      [1, 2, 3],
      reason: 'a regravação aberta sem linha tirava o regravar de todas',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence being recorded whose stretch the room no longer has '
      'is let go with its microphone when the telling is read, and nothing '
      'is queued', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, watchesWithoutAHalt: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);
    expect(harness.recorder.sounds.last, 'recorder:start');

    await aSalaPerdeOTrecho(tester, harness, container);

    expect(
      container.read(salaSessionProvider).btRegravacao,
      isNull,
      reason:
          'a regravação de um trecho que a sala não tem mais seguia gravando '
          'sem linha nenhuma',
    );
    expect(
      harness.recorder.sounds.last,
      'recorder:discard',
      reason: 'o microfone ficava aberto numa frase que a sala não tem mais',
    );
    expect(
      guardada(harness),
      isFalse,
      reason: 'a gravação de um trecho que a sala não tem mais ia para a fila',
    );
    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.onRegravar != null) linha.n,
      ],
      [1, 2, 3],
      reason: 'a regravação aberta sem linha tirava o regravar de todas',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase the room told back without a name offers no '
      '«regravar», so no sentence is recorded that could not be kept', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await quatroFrasesEmWav(tester, harness);
    final semNome = [
      for (final trecho in container.read(salaSessionProvider).btTrechos)
        if (trecho.segmentId == null) trecho.frase,
    ];
    expect(semNome, isNotEmpty, reason: 'o cenário precisa de frases sem nome');

    expect(
      [
        for (final linha
            in tester.widget<FraseList>(find.byType(FraseList)).rows)
          if (linha.regravar != null && semNome.contains(linha.n)) linha.n,
      ],
      isEmpty,
      reason:
          'a frase sem nome oferecia regravar e a gravação era apagada ao '
          'fechar o microfone',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence held on a stretch the room reads with no length '
      'still goes up at the tap of its «tentar de novo»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    final semExtensao = BackTranslationProgress(
      segments: [
        for (final (antes, trecho) in harness.room.segments.indexed)
          SegmentView(
            segmentId: trecho.segmentId,
            takeId: trecho.takeId,
            startsMs: trecho.startsMs,
            endsMs: trecho.segmentId == 'trecho-3'
                ? trecho.startsMs
                : trecho.endsMs,
            told: trecho.told,
            frase: antes + 1,
          ),
      ],
    );
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..sentenceAnswersFirst.add(const Refused('DRAFT_APPROVED'))
      ..retroSoFar = semExtensao;
    segura.complete();
    await waitFor(
      'a sala ler o trecho da frase guardada sem extensão',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.segmentId == 'trecho-3')
              .single
              .to ==
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.segmentId == 'trecho-3')
              .single
              .from,
      step: () => _passo(tester),
    );
    await _passo(tester);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    const armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
    expect(linhasCom(tester, falhou), [3]);
    await tocar(tester, falhou);
    await tester.pump(const Duration(seconds: 2));
    await tocar(tester, armado);
    await waitFor(
      'a frase subir de novo',
      () => harness.room.sentencesSent.length == 2,
      step: () => _passo(tester),
    );

    expect(
      harness.room.sentencesSent.last.segmentId,
      'trecho-3',
      reason:
          'o toque lia a sala, não achava o trecho e guardava a frase de '
          'novo, sem nunca enviar',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence laid in is announced in her words and plays in its '
      'place on the new take, with a second and a half around it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(harness.playback.ranges.last, '0-4700');
    closeTheRoom(container);
  });

  testWidgets('a new last sentence plays to the end of its take, never past '
      'it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.sentenceLaysInAs = const Duration(seconds: 6);
    await gravarAFrase(tester, harness, 4);

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.playback.ranges.last,
      '2500-10000',
      reason: 'a última frase nova tocava até 11500 numa gravação de 10 s',
    );
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
      final container = await quatroFrasesEmWav(tester, harness);
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

  testWidgets('a re-recorded frase that awaits its translation offers no way '
      'to keep the translation it had before', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);

    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');
    expect(
      find.text('manter a tradução de antes'),
      findsNothing,
      reason:
          'a frase regravada oferecia ficar com a tradução da frase que '
          'já não existe',
    );
    expect(
      find.text('traduzindo de novo a frase 2 — toquem no círculo'),
      findsNothing,
    );
    container.read(salaSessionProvider.notifier).manterATraducaoDeAntes();
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-2',
    );
    closeTheRoom(container);
  });

  testWidgets('the circle translates the re-recorded frase at exactly its new '
      'span, and once that lands the frase stops waiting', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    final nova = harness.room.takes.last.takeId;

    await _traduzirDeNovo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.room.replacesAsked,
      ['trecho-2@$nova:4000-7200'],
      reason: 'o círculo abria outra frase enquanto a regravada esperava',
    );
    expect(naLinha('regravada — traduzam esta frase'), findsNothing);
    expect(container.read(salaSessionProvider).btFraseQueAguarda, isNull);
    expect(
      aceso(tester, 'terminei'),
      isTrue,
      reason: 'terminei seguia fechado depois de traduzirem a frase nova',
    );
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

  testWidgets('a held sentence over a stretch no longer listed is let go on '
      'entering, and the frase that awaits stays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-1964-frase');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-regravado',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-3',
    );
    await waitFor(
      'a frase guardada fora da lista sair da fila',
      () async => await harness.takes.sentenceHeldIn('sessao-antiga') == null,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btFraseQueAguarda,
      'trecho-3',
      reason:
          'deixar a frase guardada de um trecho que saiu da lista apagava '
          'também a frase que aguarda',
    );
    closeTheRoom(container);
  });

  Future<(ProviderContainer, PendingTake)> comAFraseGuardadaDeVolta(
    WidgetTester tester,
    SalaHarness harness,
  ) async {
    final pasta = Directory.systemTemp.createTempSync('sala-1964-guardada');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final guardada = await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(tester, harness);
    await waitFor(
      'a frase guardada voltar',
      () => container.read(salaSessionProvider).btFraseGuardada == 'trecho-3',
      step: () => _passo(tester),
    );
    return (container, guardada);
  }

  Future<void> deNovoNaTraducao(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    await waitFor(
      'a casa abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );
    notifier.startRetro();
    await waitFor(
      'a tradução abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
      step: () => _passo(tester),
    );
    await _passo(tester);
  }

  final semOTrecho3 = [
    for (final trecho in _daSala)
      if (trecho.segmentId != 'trecho-3') trecho,
  ];
  final oTrecho3 = _daSala.firstWhere(
    (trecho) => trecho.segmentId == 'trecho-3',
  );

  testWidgets('a held sentence the room no longer offers is let go on '
      'entering, and its line goes with it, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (container, _) = await comAFraseGuardadaDeVolta(tester, harness);
    harness.room.retroSoFar = BackTranslationProgress(
      segments: semOTrecho3,
      stale: [oTrecho3],
    );

    await deNovoNaTraducao(tester, container);
    await waitFor(
      'a frase superada sair da fila',
      () async => await harness.takes.sentenceHeldIn('sessao-antiga') == null,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btFraseGuardada,
      isNull,
      reason:
          'a frase largada do tablet ficava acesa em tentar de novo sobre '
          'uma cópia apagada',
    );
    expect(
      _naLista('não deu para guardar a frase — tentar de novo'),
      findsNothing,
    );
    closeTheRoom(container);
  });

  testWidgets('a held sentence over a frase recorded again that awaits its '
      'translation is kept on entering: the team decides, as hers', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (container, guardada) = await comAFraseGuardadaDeVolta(
      tester,
      harness,
    );
    harness.room.retroSoFar = BackTranslationProgress(
      segments: semOTrecho3,
      stale: [oTrecho3],
      awaitingSegmentId: 'trecho-3',
    );

    await deNovoNaTraducao(tester, container);
    await waitFor(
      'a leitura da entrada dizer que o trecho 3 aguarda',
      () => container.read(salaSessionProvider).btFraseQueAguarda == 'trecho-3',
      step: () => _passo(tester),
    );
    await _passo(tester);
    await _passo(tester);

    expect(
      (await harness.takes.sentenceHeldIn('sessao-antiga'))?.id,
      guardada.id,
      reason: 'a frase guardada sobre a frase que aguarda era largada',
    );
    closeTheRoom(container);
  });

  testWidgets('the read of a telling-back the team already left lands on '
      'nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    await waitFor(
      'a casa abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );
    harness.room
      ..retroSoFar = const BackTranslationProgress(
        segments: _daSala,
        awaitingSegmentId: 'trecho-3',
      )
      ..holdNextState();
    notifier.startRetro();
    await _passo(tester);
    notifier.goEnsaio();
    await waitFor(
      'a casa abrir de novo',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );

    harness.room.finishHeldState();
    await _passo(tester);
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btFraseQueAguarda,
      isNull,
      reason:
          'a leitura da tradução deixada pousava a frase que aguarda sobre a '
          'casa',
    );
    closeTheRoom(container);
  });

  testWidgets('a held sentence over a frase of the whole set aside, which the '
      'room still offers, is kept on entering a checked telling-back', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-1964-de-lado');
    addTearDown(() => pasta.deleteSync(recursive: true));
    const doInteiro = SegmentView(
      segmentId: 'trecho-do-inteiro',
      takeId: 'gravacao-inteira-velha',
      startsMs: 0,
      endsMs: 4000,
    );
    final guardada = await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: doInteiro.segmentId,
    );
    await holdTheSession(
      harness,
      ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          for (final n in [1, 2])
            KeptTake(
              scopeId: KeptScope.parte(n),
              path: (File(
                '${pasta.path}/p$n.wav',
              )..writeAsBytesSync(aSpokenWav(length: parte))).path,
              takeId: 'gravacao-$n',
            ),
        ],
        wholeHeldByTheRoom: const ['gravacao-inteira-velha'],
      ),
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      segments: [..._daSala, doInteiro],
      checked: true,
    );
    final container = harness.container();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await _passo(tester);
    await intoTheBackTranslation(
      container.read(salaSessionProvider.notifier),
      () => container.read(salaSessionProvider),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await _passo(tester);
    await _passo(tester);

    expect(
      (await harness.takes.sentenceHeldIn('sessao-antiga'))?.id,
      guardada.id,
      reason:
          'a frase guardada sobre o inteiro posto de lado era largada, embora '
          'a sala ainda a oferecesse',
    );
    closeTheRoom(container);
  });

  testWidgets('entering the telling-back on a read that fails lets go of no '
      'held sentence, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final pasta = Directory.systemTemp.createTempSync('sala-1964-lida');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-fora-da-memoria',
    );
    notifier.goEnsaio();
    await waitFor(
      'a casa abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');
    notifier.startRetro();
    await waitFor(
      'a leitura da entrada falhar',
      () => harness.room.failStateOnceWith == null,
      step: () => _passo(tester),
    );
    await _passo(tester);
    await _passo(tester);

    expect(
      await harness.takes.sentenceHeldIn('sessao-antiga'),
      isNotNull,
      reason:
          'a leitura que falhou largava a frase guardada, julgada contra os '
          'trechos em memória',
    );
    closeTheRoom(container);
  });

  testWidgets('a relaunch with a frase awaiting and another take unheard plays '
      'the listen first, not the frase', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.listeningUnheardTakeIds = const ['gravacao-1'];
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-3',
    );
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('P0', 'pt')],
      reason:
          'a retomada abria a frase que espera sem ouvir a parte que '
          'ninguém ouviu',
    );
    final aqui = container.read(salaSessionProvider);
    expect(harness.playback.played, [aqui.partes[0].path]);
    expect(aqui.btSoOuvir, isTrue);
    expect(aqui.btTrechoTraduzidoDeNovo, isNull);
    closeTheRoom(container);
  });

  testWidgets('a relaunch where only the awaiting frase\'s take is unheard '
      'says the frase awaits and plays the sentence with what surrounds it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.listeningUnheardTakeIds = const ['gravacao-2'];
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-3',
    );
    await _passo(tester);
    await _passo(tester);

    expect(harness.voice.fixedLines, [('N5', 'pt')]);
    expect(
      harness.playback.ranges.last,
      '0-5500',
      reason:
          'a retomada tocava só a frase, sem o que vem em volta, e a sala '
          'não a contava como ouvida',
    );
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btSoOuvir, isFalse);
    expect(aqui.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-3');
    closeTheRoom(container);
  });

  testWidgets('picking a telling back up with every part heard and nothing '
      'awaiting plays nothing and says nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.listeningUnheardTakeIds = const [];
    final container = await _voltaATraducao(tester, harness);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.playback.played,
      isEmpty,
      reason: 'a gravação voltava a tocar debaixo da equipe na retomada',
    );
    expect(harness.voice.fixedLines, isEmpty);
    closeTheRoom(container);
  });

  Future<void> deVoltaDoEnsaio(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final sala = container.read(salaSessionProvider.notifier);
    sala.goEnsaio();
    await _passo(tester);
    sala.startRetro();
    await waitFor('a tradução voltar', () {
      final agora = container.read(salaSessionProvider);
      return agora.stage == SalaStage.retro && !agora.awaitingTheGuide;
    }, step: () => _passo(tester));
    await _passo(tester);
    await _passo(tester);
  }

  testWidgets('coming back from the rehearsal to a frase that awaits its '
      'translation, every part heard, the voice says so and that frase opens '
      'at its own span', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    harness.room.listeningUnheardTakeIds = const [];
    harness.voice.fixedLines.clear();

    await deVoltaDoEnsaio(tester, container);

    expect(
      harness.voice.fixedLines,
      [('N5', 'pt')],
      reason:
          'a equipe voltava do ensaio e ninguém lembrava da frase regravada',
    );
    expect(harness.playback.ranges.last, '4000-7200');
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btFraseQueAguarda, 'trecho-2');
    expect(aqui.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-2');
    closeTheRoom(container);
  });

  testWidgets('coming back from the rehearsal to a frase that awaits its '
      'translation, with no answer from the room, still opens that frase', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    harness.room.listeningUnheardTakeIds = null;
    harness.voice.fixedLines.clear();

    await deVoltaDoEnsaio(tester, container);

    expect(
      harness.voice.fixedLines,
      [('N5', 'pt')],
      reason:
          'sem resposta da sala, a volta tocava a gravação sobre a frase que espera',
    );
    expect(harness.playback.ranges.last, '4000-7200');
    closeTheRoom(container);
  });

  testWidgets('coming back from the rehearsal when only the re-recorded '
      'sentence is unheard, the voice says the frase awaits and the sentence '
      'plays with what surrounds it, not the listen', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    harness.room.listeningUnheardTakeIds = [harness.room.takes.last.takeId];
    harness.voice.fixedLines.clear();

    await deVoltaDoEnsaio(tester, container);

    expect(
      harness.voice.fixedLines,
      [('N5', 'pt')],
      reason: 'a volta tocava a escuta em vez da frase que espera',
    );
    expect(
      harness.playback.ranges.last,
      '2500-8700',
      reason: 'a frase nova não tocava no lugar dela, com o que vem em volta',
    );
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btSoOuvir, isFalse);
    expect(aqui.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-2');
    closeTheRoom(container);
  });

  testWidgets('a sentence laid in asks the room what is left, so a return out '
      'of its reach plays the sentence with what surrounds it, as the room '
      'counts it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 2);
    final nova = 'gravacao-${harness.room.takeIds.length + 1}';
    harness.room.listeningUnheardTakeIds = [nova];

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);
    expect(harness.room.takes.last.takeId, nova);
    harness.room.reachable = false;
    harness.playback.finishPlayback();
    await _passo(tester);
    harness.voice.fixedLines.clear();

    await deVoltaDoEnsaio(tester, container);

    expect(harness.voice.fixedLines, [('N5', 'pt')]);
    expect(
      harness.playback.ranges.last,
      '2500-8700',
      reason:
          'a frase regravada não perguntava nada à sala, e a volta sem rede '
          'abria só a frase, sem o que vem em volta',
    );
    closeTheRoom(container);
  });

  testWidgets('the new sentence played in its place counts as heard on the '
      'new take, and the check is told so', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    final nova = harness.room.takes.last.takeId;

    await _traduzirDeNovo(tester);
    await _passo(tester);
    await _passo(tester);
    await tocar(tester, 'terminei');
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

  testWidgets('a new last sentence heard in its place is reported up to the '
      'end of its take, never past it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.sentenceLaysInAs = const Duration(seconds: 6);
    await deitarAFrase(tester, harness, 4);
    final nova = harness.room.takes.last.takeId;

    await _traduzirDeNovo(tester);
    await _passo(tester);
    await _passo(tester);
    await tocar(tester, 'terminei');
    await _passo(tester);

    final relato = harness.room.playedByTakeSent.last;
    expect(
      [
        for (final parte in relato)
          if (parte['take_id'] == nova)
            '${parte['played_ranges']} em ${parte['clip_duration_ms']}',
      ],
      ['[[2500, 10000]] em 10000'],
      reason: 'a sala recebia 2500-11500 ouvidos numa gravação de 10 s',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence the room refuses because another frase awaits stays '
      'on the tablet, and the voice opens the frase that awaits', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
    expect(aqui.btFraseGuardada, 'trecho-3');
    closeTheRoom(container);
  });

  Future<ProviderContainer> comAFraseGuardadaSobreAQueAguarda(
    WidgetTester tester,
    SalaHarness harness, {
    bool aprovado = false,
  }) async {
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 2);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    harness.room.awaitingSegmentId = 'trecho-2';
    if (aprovado) {
      harness.room.approvedDraft = const ApprovedDraft(version: 1);
    }
    await deNovoNaTraducao(tester, container);
    await waitFor(
      'a leitura dizer que a frase 2 aguarda, com a frase guardada de volta',
      () {
        final aqui = container.read(salaSessionProvider);
        return aqui.btFraseQueAguarda == 'trecho-2' &&
            aqui.btFraseGuardada == 'trecho-2' &&
            aqui.theFraseListIsIdle;
      },
      step: () => _passo(tester),
    );
    await _passo(tester);
    return container;
  }

  const falhou = 'não deu para guardar a frase — tentar de novo';

  testWidgets('«tentar de novo» on a held sentence whose frase now awaits '
      'another computer\'s sentence opens its review and sends nothing, as '
      'hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await comAFraseGuardadaSobreAQueAguarda(tester, harness);

    await tocar(tester, falhou);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      hasLength(1),
      reason:
          'a frase guardada subia por cima da frase do outro computador sem '
          'ninguém ouvir nenhuma das duas',
    );
    expect(
      naLinha('usar esta'),
      findsOneWidget,
      reason: 'a equipe não tinha como ouvir a gravação e decidir',
    );
    expect(naLinha('gravar de novo'), findsOneWidget);
    expect(_naLista('Ouvir — 2'), findsOneWidget);
    expect(_naLista(falhou), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('the review a held sentence opens on its awaiting frase sends '
      'that same recording on «usar esta», laid in once', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await comAFraseGuardadaSobreAQueAguarda(tester, harness);
    await tocar(tester, falhou);
    await _passo(tester);

    await tester.tap(naLinha('usar esta'));
    await waitFor(
      'a frase guardada subir da revisão',
      () => harness.room.sentencesSent.length == 2,
      step: () => _passo(tester),
    );
    await _passo(tester);

    final enviadas = harness.room.sentencesSent;
    expect(
      enviadas.last,
      enviadas.first,
      reason: 'a revisão mandava outra gravação, não a frase guardada',
    );
    expect(harness.room.sentencesLaid, [enviadas.first.sentenceId]);
    expect(naLinha('usar esta'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('the review a held sentence opens on its awaiting frase takes '
      'the held recording off the tablet on «gravar de novo», and the circle '
      'records over it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await comAFraseGuardadaSobreAQueAguarda(tester, harness);
    await tocar(tester, falhou);
    await _passo(tester);

    await tester.tap(naLinha('gravar de novo'));
    await _passo(tester);

    expect(
      guardada(harness),
      isFalse,
      reason: 'a gravação que a equipe largou seguia guardada na fila',
    );
    expect(harness.room.sentencesSent, hasLength(1));
    expect(naLinha('usar esta'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsOneWidget,
      reason: 'o círculo não se oferecia para gravar a frase de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the held sentence\'s «tentar de novo» '
      'still arms, the confirmed tap opens the review instead of sending, and '
      'its «usar esta» goes up reopening the draft', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await comAFraseGuardadaSobreAQueAguarda(
      tester,
      harness,
      aprovado: true,
    );

    await tocar(tester, falhou);
    const armado = 'toquem de novo: isto abre de novo o rascunho aprovado';
    expect(
      linhasCom(tester, armado),
      [2],
      reason: 'o toque sobre um rascunho aprovado abria a revisão sem armar',
    );
    await tester.pump(const Duration(seconds: 2));
    await tocar(tester, armado);
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      hasLength(1),
      reason: 'o toque confirmado subia por cima da frase que aguarda',
    );
    expect(naLinha('usar esta'), findsOneWidget);

    await tester.tap(naLinha('usar esta'));
    await waitFor(
      'a frase guardada subir da revisão',
      () => harness.room.sentencesSent.length == 2,
      step: () => _passo(tester),
    );

    expect(
      harness.room.sentencesSentReopening,
      [harness.room.sentencesSent.first.sentenceId],
      reason:
          'a revisão aberta pelo toque armado mandava a frase sem reabrir o '
          'rascunho aprovado',
    );
    closeTheRoom(container);
  });

  testWidgets('a «terminei» the room refuses because a frase awaits marks '
      'that frase as re-recorded and takes «regravar» off the others', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
      final container = await quatroFrasesEmWav(tester, harness);
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
      'its re-record, the circle records it, and the screen still asks for '
      'the whole sentence', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
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
      circulo.voice,
      VoiceState.listening,
      reason: 'o círculo gravava a frase parecendo parado',
    );
    expect(circulo.semanticLabel, 'gravem a frase inteira');
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsOneWidget,
      reason: 'na tradução conferida a regravação perdia a pista escrita',
    );
    closeTheRoom(container);
  });

  testWidgets('a missing element placed after frase 2 leads to the frase\'s '
      'retelling and to «regravar» on every row, the two paths of her voice', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictFindingSegmentId = 'trecho-3'
      ..verdictFindings = const [
        BtFinding(kind: BtFindingKind.missing, frase: 2, segmentId: 'trecho-3'),
      ];

    await tocar(tester, 'terminei');
    await waitFor(
      'o achado chegar',
      () =>
          container.read(salaSessionProvider).btPhase == BtPhase.playing &&
          container.read(salaSessionProvider).btVeredito,
      step: () => _passo(tester),
    );
    await _passo(tester);

    final apontada = container.read(salaSessionProvider).btFindingTrecho!;
    expect(
      _acesa(
        tester,
        'Ouvir esta frase de novo e traduzir de novo — ${apontada.frase}',
      ),
      isTrue,
      reason: 'o caminho de traduzir de novo, se X está no áudio, sumia',
    );
    for (var n = 1; n <= 4; n++) {
      expect(
        _acesa(tester, 'regravar a frase $n'),
        isTrue,
        reason:
            'o caminho de regravar inteira a frase onde X cabe não estava '
            'na linha',
      );
    }
    expect(find.text('Continuar o ensaio'), findsNothing);
    closeTheRoom(container);
  });

  int frasesGuardadas(SalaHarness harness) => (harness.takes as FakeTakeQueue)
      .rows
      .where((row) => row.kind == 'frase')
      .length;

  testWidgets('«gravar de novo» takes the dropped recording off the tablet', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await tester.tap(naLinha('gravar de novo'));
    await _passo(tester);

    expect(
      frasesGuardadas(harness),
      0,
      reason: 'a gravação que a equipe largou voltava como frase guardada',
    );
    closeTheRoom(container);
  });

  Finder oGlifo(ListenGlyph glifo) => find.descendant(
    of: _naLista('Ouvir — 3'),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter is ListenGlyphPainter &&
          (widget.painter! as ListenGlyphPainter).glyph == glifo,
    ),
  );

  bool apertado(WidgetTester tester) => isSemantics(
    hasToggledState: true,
    isToggled: true,
  ).matches(tester.getSemantics(_naLista('Ouvir — 3')), {});

  testWidgets('the sentence just recorded shows a stop and is pressed while '
      'it plays, still named «Ouvir — N»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    expect(oGlifo(ListenGlyph.play), findsOneWidget);
    expect(apertado(tester), isFalse);

    await tocar(tester, 'Ouvir — 3');

    expect(
      oGlifo(ListenGlyph.stop),
      findsOneWidget,
      reason: 'o botão desenhava o play com a frase tocando',
    );
    expect(
      apertado(tester),
      isTrue,
      reason: 'o VoiceOver não sabia que a frase estava tocando',
    );
    expect(oGlifo(ListenGlyph.play), findsNothing);

    harness.playback.finishPlayback();
    await _passo(tester);

    expect(oGlifo(ListenGlyph.play), findsOneWidget);
    expect(apertado(tester), isFalse);
    closeTheRoom(container);
  });

  testWidgets('a tap on the sentence while it plays stops it, and the next '
      'tap plays it from the start instead of going on', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    final gravada = harness.recorder.lastPath;
    await tocar(tester, 'Ouvir — 3');
    final tocadas = harness.playback.played.length;
    final paradas = harness.playback.stops;

    await tocar(tester, 'Ouvir — 3');

    expect(
      harness.playback.played.length,
      tocadas,
      reason: 'o segundo toque recomeçava a frase em vez de parar',
    );
    expect(harness.playback.stops, greaterThan(paradas));
    expect(oGlifo(ListenGlyph.play), findsOneWidget);
    expect(apertado(tester), isFalse);

    await tocar(tester, 'Ouvir — 3');

    expect(harness.playback.played.length, tocadas + 1);
    expect(harness.playback.played.last, gravada);
    expect(harness.playback.playedFrom.last, Duration.zero);
    expect(oGlifo(ListenGlyph.stop), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('the sentence just recorded plays on its own button, never '
      'lighting or pausing the main listen', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    await tocar(tester, 'Ouvir — 3');
    final paradas = harness.playback.stops;
    final sons = harness.playback.sounds.length;

    expect(
      byLabel('Pausar'),
      findsNothing,
      reason: 'o ouvir principal virava pausar com a frase da revisão tocando',
    );
    expect(
      aceso(tester, 'Ouvir'),
      isFalse,
      reason: 'o ouvir principal acendia para a frase da revisão',
    );

    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await _passo(tester);

    expect(
      harness.playback.sounds.skip(sons),
      isNot(contains('playback:pause')),
      reason: 'o ouvir principal pausava a frase da revisão',
    );
    expect(harness.playback.stops, paradas);
    expect(apertado(tester), isTrue);

    await tocar(tester, 'Ouvir — 3');

    expect(apertado(tester), isFalse);
    expect(harness.playback.stops, greaterThan(paradas));
    closeTheRoom(container);
  });

  testWidgets('under review, before and while it plays, the circle is named '
      '«gravem a frase inteira», as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    expect(onTheCircle('gravem a frase inteira'), findsOneWidget);

    await tocar(tester, 'Ouvir — 3');

    expect(apertado(tester), isTrue);
    expect(
      onTheCircle('gravem a frase inteira'),
      findsOneWidget,
      reason:
          'o VoiceOver lia no círculo um estado da gravação com a frase da '
          'revisão tocando',
    );
    closeTheRoom(container);
  });

  testWidgets('while the sentence just recorded plays, the circle does not '
      'speak and no «ouvindo» stands by the main listen', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await tocar(tester, 'Ouvir — 3');

    expect(apertado(tester), isTrue);
    expect(
      tester.widget<FacilitatorCircle>(_circulo()).voice,
      isNot(VoiceState.speaking),
      reason: 'o círculo falava na língua materna com a frase da revisão',
    );
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('ouvindo a gravação de vocês…'),
      ),
      findsNothing,
      reason: 'o ouvindo da gravação aparecia para a frase da revisão',
    );
    closeTheRoom(container);
  });

  testWidgets('the sentence just recorded is offered as her filled triangle, '
      'not a lucide outline', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    expect(
      find.descendant(of: _naLista('Ouvir — 3'), matching: find.byType(Icon)),
      findsNothing,
      reason: 'o botão desenhava o play vazado do Lucide',
    );
    expect(
      oGlifo(ListenGlyph.play),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [Offset(10, 12), Offset(9, 7), Offset(9, 17)],
        excludes: const [Offset(7, 12), Offset(16, 8), Offset(16, 16)],
      ),
      reason:
          'o play dela é «M8 6l10 6-10 6z» cheio na caixa de 24 '
          '(SentenceRerecord.tsx:21)',
    );
    closeTheRoom(container);
  });

  testWidgets('the sentence playing is stopped by her filled square with its '
      'rounded corners, not a lucide outline', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    await tocar(tester, 'Ouvir — 3');

    expect(
      oGlifo(ListenGlyph.stop),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [Offset(12, 12), Offset(7, 7), Offset(17, 17)],
        excludes: const [
          Offset(5, 12),
          Offset(19, 12),
          Offset(6.3, 6.3),
          Offset(17.7, 17.7),
        ],
      ),
      reason:
          'o stop dela é um quadrado cheio de 6 a 18 com rx 2 na caixa de 24 '
          '(SentenceRerecord.tsx:22)',
    );
    closeTheRoom(container);
  });

  testWidgets('the review glyph is drawn in her verde, in the light and in '
      'the dark, not in the cord that fades into its card', (tester) async {
    for (final (theme, verde) in [
      (AppTheme.light, const Color(0xFF3F3E20)),
      (AppTheme.dark, const Color(0xFFECEADC)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Scaffold(
            body: FraseList(
              language: 'pt',
              rows: [
                FraseRow(
                  n: 3,
                  parte: 1,
                  share: 0.5,
                  onHear: null,
                  revisao: FraseRevisao(
                    ouvir: 'Ouvir — 3',
                    tocando: false,
                    onOuvir: () {},
                    gravarDeNovo: 'gravar de novo',
                    onGravarDeNovo: () {},
                    usarEsta: 'usar esta',
                    onUsarEsta: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        oGlifo(ListenGlyph.play),
        paints..path(color: verde),
        reason:
            '${theme.brightness.name}: o glifo dela é --verde no .ctl '
            '(globals.css:331); o nosso era o cord, quase da cor do cartão',
      );
    }
  });

  testWidgets(
    'a new recording of a held sentence takes the held one\'s place',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await quatroFrasesEmWav(tester, harness);
      await gravarAFrase(tester, harness, 3);
      harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
      await tester.tap(naLinha('usar esta'));
      await _passo(tester);
      await _passo(tester);

      await gravarAFrase(tester, harness, 3);

      expect(frasesGuardadas(harness), 1);
      closeTheRoom(container);
    },
  );

  testWidgets('closing a re-record in its review keeps the recording held, '
      'with its line on the row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);

    await tocar(tester, 'regravar a frase 3');

    expect(
      _naLista('não deu para guardar a frase — tentar de novo'),
      findsOneWidget,
    );
    expect(frasesGuardadas(harness), 1);
    closeTheRoom(container);
  });

  testWidgets('a new take the tablet cannot keep still leaves the frase '
      'waiting, and plays nothing in its place', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 2);
    harness.recorder.keepBytesFails = true;
    harness.voice.fixedLines.clear();
    final tocadas = harness.playback.ranges.length;

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      isEmpty,
      reason: 'a voz dizia que a frase nova estava no lugar sem a parte nova',
    );
    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');
    expect(
      harness.playback.ranges.skip(tocadas),
      isEmpty,
      reason: 'a parte velha tocava no lugar da frase nova',
    );
    closeTheRoom(container);
  });

  testWidgets('a new part the room will not hand over says nothing and plays '
      'nothing, instead of announcing a sentence that is not there', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 2);
    harness.room.failClipOf['gravacao-${harness.room.takeIds.length + 1}'] =
        const NetworkFailed('sem rede');
    harness.voice.fixedLines.clear();
    final tocadas = harness.playback.ranges.length;

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      isEmpty,
      reason: 'a voz dizia «a frase nova já está no lugar» e nada tocava',
    );
    expect(harness.playback.ranges.skip(tocadas), isEmpty);
    closeTheRoom(container);
  });

  testWidgets('an answer that does not name the new sentence says nothing, '
      'plays nothing and leaves the list quiet', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 2);
    harness.room.sentenceAnswersFirst.add(const Answered(TellingAgain()));
    harness.voice.fixedLines.clear();
    final tocadas = harness.playback.ranges.length;

    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      isEmpty,
      reason: 'a voz dizia «a frase nova já está no lugar» e nada tocava',
    );
    expect(harness.playback.ranges.skip(tocadas), isEmpty);
    expect(
      _naLista('não deu para guardar a frase — tentar de novo'),
      findsNothing,
    );
    closeTheRoom(container);
  });

  Future<String> deitarSemAParte(
    WidgetTester tester,
    SalaHarness harness,
    int n,
  ) async {
    await gravarAFrase(tester, harness, n);
    final nova = 'gravacao-${harness.room.takeIds.length + 1}';
    harness.room.failClipOf[nova] = const NetworkFailed('sem rede');
    harness.voice.fixedLines.clear();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);
    return nova;
  }

  testWidgets('a new part the room will not hand over leaves its row offering '
      'to try again, not a row with nothing to tap', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);

    await deitarSemAParte(tester, harness, 2);

    expect(
      _naLista('não deu para guardar a frase — tentar de novo'),
      findsOneWidget,
      reason: 'a frase ficava sem parte e a linha não oferecia nada',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on that row fetches the new part again, then announces '
      'the sentence and plays it in its place', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    await tocar(tester, falhou);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('N4', 'pt')],
      reason: 'o toque na linha não buscava a parte nova de novo',
    );
    expect(harness.playback.ranges.last, '2500-8700');
    expect(_naLista(falhou), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while the new part is fetched again its row says «enviando…», '
      'not a line with nothing on it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    harness.room.holdNextClip();

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);

    expect(
      naLinha('enviando…'),
      findsOneWidget,
      reason: 'a parte voltava a ser buscada sem a linha dizer nada',
    );
    harness.room.finishHeldClip();
    await _passo(tester);
    await _passo(tester);
    expect(naLinha('enviando…'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while the new part is fetched again no row offers «regravar», '
      'not even the row it is fetched for', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    harness.room.holdNextClip();

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);

    expect(naLinha('enviando…'), findsOneWidget);
    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason:
            'a frase $n oferecia regravar enquanto a parte nova era buscada '
            'de novo',
      );
    }
    harness.room.finishHeldClip();
    await _passo(tester);
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('a new part that fails again says nothing and gives the row its '
      'retry back, instead of leaving it on «enviando…»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);

    const falhou = 'não deu para guardar a frase — tentar de novo';
    await tocar(tester, falhou);
    await _passo(tester);
    await _passo(tester);

    expect(harness.voice.fixedLines, isEmpty);
    expect(
      _naLista(falhou),
      findsOneWidget,
      reason: 'a segunda falha deixava a linha presa em «enviando…»',
    );
    closeTheRoom(container);
  });

  testWidgets('the new part is asked for twice before the sentence is left '
      'owed, not given up on after one failed read', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);

    final nova = await deitarSemAParte(tester, harness, 2);

    expect(
      harness.room.clipsFetched.where(
        (url) => url.endsWith('/takes/$nova/audio'),
      ),
      hasLength(2),
      reason: 'uma leitura só que falhava já deixava a frase sem a parte',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on the owed row reads the stretches back before it asks '
      'for the new part, not the name it was left with', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    final pedidas = harness.room.clipsFetched.length;
    harness.room.holdNextState();

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.room.clipsFetched.length,
      pedidas,
      reason:
          'a parte nova era buscada pelo nome de antes, sem ler as frases '
          'de novo',
    );
    harness.room.finishHeldState();
    await _passo(tester);
    await _passo(tester);
    await _passo(tester);
    expect(harness.room.clipsFetched.skip(pedidas), [
      endsWith('/takes/$nova/audio'),
    ]);
    expect(harness.voice.fixedLines, [('N4', 'pt')]);
    closeTheRoom(container);
  });

  testWidgets('while the owed part is fetched again «recomeçar a tradução» '
      'rests, instead of standing lit over the fetch', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    harness.room.holdNextClip();
    bool recomecoAceso() =>
        tester
            .widget<Semantics>(byLabel('recomeçar a tradução'))
            .properties
            .enabled ??
        false;
    expect(recomecoAceso(), isTrue);

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.enviando,
    );
    expect(
      recomecoAceso(),
      isFalse,
      reason: 'o recomeço ficava aceso enquanto a frase ainda era buscada',
    );
    harness.room.finishHeldClip();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('while the owed part is fetched again the way back to the '
      'recording is not taken, so the fetch is not dropped', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    harness.room.holdNextClip();
    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);

    await tester.tap(byLabel('Voltar para a gravação'));
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.retro,
      reason:
          'a volta para a gravação largava a busca e a frase perdia a '
          'linha que a guardava',
    );
    harness.room.finishHeldClip();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('while the owed part is fetched again the way back is drawn '
      'away, not lit over a tap it no longer takes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    harness.room.holdNextClip();
    double volta() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: byLabel('Voltar para a gravação'),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(volta(), 1);

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);

    expect(
      volta(),
      0,
      reason: 'a seta de voltar ficava acesa e o toque nela não fazia nada',
    );
    harness.room.finishHeldClip();
    await _passo(tester);
    await _passo(tester);
    expect(volta(), 1);
    closeTheRoom(container);
  });

  testWidgets('while a new part is owed no row offers «regravar», not even '
      'the row of the sentence that waits for it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);

    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason:
            'a frase $n oferecia regravar por cima de uma frase que ainda '
            'não chegou',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('back from the rehearsal while a new part is owed, the room '
      'says nothing and plays nothing, and the row still waits for the part', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);
    final tocadas = harness.playback.played.length;

    await deVoltaDoEnsaio(tester, container);

    expect(
      harness.voice.fixedLines,
      isEmpty,
      reason: 'a volta dizia que a frase esperava a tradução sem a frase nova',
    );
    expect(
      harness.playback.played.skip(tocadas),
      isEmpty,
      reason: 'a volta tocava a parte velha no lugar da frase nova',
    );
    expect(
      _naLista('não deu para guardar a frase — tentar de novo'),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  testWidgets('a trip to the rehearsal and back over an owed part never '
      'plays the old take, and no row offers «regravar» on the way back', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);
    final velha = container
        .read(salaSessionProvider)
        .partes[container
            .read(salaSessionProvider)
            .trechoChamado('trecho-2')!
            .parte]
        .path;
    final tocadas = harness.playback.played.length;

    await deVoltaDoEnsaio(tester, container);

    expect(
      harness.playback.played.skip(tocadas).where((path) => path == velha),
      isEmpty,
      reason: 'a volta tocava a gravação velha onde a frase nova esperava',
    );
    for (var n = 1; n <= 4; n++) {
      expect(_naLista('regravar a frase $n'), findsNothing);
    }
    closeTheRoom(container);
  });

  Finder naCasa(String texto) =>
      find.descendant(of: find.byType(EnsaioView), matching: find.text(texto));

  testWidgets('on the home, a new part still owed is written under the '
      'title, not left for the telling alone to say', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);

    container.read(salaSessionProvider.notifier).goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);

    expect(
      naCasa('não deu para guardar a frase — tentar de novo'),
      findsOneWidget,
      reason: 'a casa calava a frase que não foi guardada',
    );
    closeTheRoom(container);
  });

  testWidgets('once the new part is fetched again the home stops saying it '
      'could not be saved', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    final nova = await deitarSemAParte(tester, harness, 2);
    harness.room.failClipOf.remove(nova);
    const falhou = 'não deu para guardar a frase — tentar de novo';
    await tocar(tester, falhou);
    await _passo(tester);
    await _passo(tester);

    container.read(salaSessionProvider.notifier).goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);

    expect(
      naCasa(falhou),
      findsNothing,
      reason:
          'a casa seguia dizendo que a frase não foi guardada depois que '
          'ela chegou',
    );
    closeTheRoom(container);
  });

  testWidgets('a re-record left for the rehearsal does not stand when the team '
      'comes back to the telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictFindingSegmentId = 'trecho-2'
      ..verdictFindings = const [
        BtFinding(
          kind: BtFindingKind.addition,
          frase: 2,
          segmentId: 'trecho-2',
        ),
      ];
    await tocar(tester, 'terminei');
    await waitFor(
      'o achado chegar',
      () =>
          container.read(salaSessionProvider).btPhase == BtPhase.playing &&
          container.read(salaSessionProvider).btVeredito,
      step: () => _passo(tester),
    );
    await _passo(tester);
    await regravarAte(tester, harness, 2);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.leaveTheBackTranslation();
    await _passo(tester);
    notifier.startRetro();
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btRegravacao,
      isNull,
      reason:
          'a volta à tradução abria o microfone da frase, não o da tradução',
    );
    expect(pista(), findsNothing);
    closeTheRoom(container);
  });

  Future<void> umAchadoNaFraseDois(
    WidgetTester tester,
    SalaHarness harness,
    ProviderContainer container,
  ) async {
    harness.room
      ..verdictChecked = false
      ..verdictFindingSegmentId = 'trecho-3'
      ..verdictFindings = const [
        BtFinding(kind: BtFindingKind.missing, frase: 2, segmentId: 'trecho-3'),
      ];
    await tocar(tester, 'terminei');
    await waitFor(
      'o achado chegar',
      () =>
          container.read(salaSessionProvider).btPhase == BtPhase.playing &&
          container.read(salaSessionProvider).btVeredito,
      step: () => _passo(tester),
    );
    await _passo(tester);
  }

  String aBarra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

  testWidgets('while a frase is being re-recorded, a tap on another row or on '
      'its dimmed «regravar» opens nothing to tell again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await umAchadoNaFraseDois(tester, harness, container);
    expect(container.read(salaSessionProvider).canRetellAFrase, isTrue);
    await regravarAte(tester, harness, 3);

    await tester.tap(_naLista('regravar a frase 1'));
    await _passo(tester);
    await tocar(tester, aBarra(2));
    await _passo(tester);

    final aqui = container.read(salaSessionProvider);
    expect(
      aqui.btTrechoTraduzidoDeNovo,
      isNull,
      reason: 'a linha abria a tradução de novo no meio da regravação da frase',
    );
    expect(aqui.btRegravacao?.segmentId, 'trecho-3');
    closeTheRoom(container);
  });

  testWidgets('while a frase is being re-recorded, no row\'s loudspeaker '
      'plays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await umAchadoNaFraseDois(tester, harness, container);
    await regravarAte(tester, harness, 3);
    expect(
      container.read(salaSessionProvider).btRegravacao?.segmentId,
      'trecho-3',
    );

    for (var n = 1; n <= 4; n++) {
      expect(
        _acesa(tester, 'ouvir a minha tradução da frase $n'),
        isFalse,
        reason:
            'a frase $n tocava a tradução velha por cima da regravação da '
            'frase 3',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('while a re-recorded frase awaits its translation, every '
      'row\'s loudspeaker stays lit, as hers does', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await umAchadoNaFraseDois(tester, harness, container);
    await deitarAFrase(tester, harness, 3);
    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-3');

    for (var n = 1; n <= 4; n++) {
      expect(
        _acesa(tester, 'ouvir a minha tradução da frase $n'),
        isTrue,
        reason:
            'a frase $n ficava muda enquanto a frase 3 esperava a tradução, '
            'e a lista dela segue tocando',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('while a re-recorded frase awaits its translation, a tap on '
      'another row leaves the circle on the frase that awaits', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await umAchadoNaFraseDois(tester, harness, container);
    await deitarAFrase(tester, harness, 3);
    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-3');

    await tocar(tester, aBarra(1));
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-3',
      reason: 'outra frase tomava o círculo da frase que esperava a tradução',
    );
    closeTheRoom(container);
  });

  testWidgets('while a told frase is open to be told again, no row offers '
      '«regravar»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await umAchadoNaFraseDois(tester, harness, container);
    expect(_naLista('regravar a frase 1'), findsOneWidget);

    await tocar(tester, aBarra(2));
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-2',
    );
    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason: 'a regravação da frase começava no meio da tradução de novo',
      );
    }
    closeTheRoom(container);
  });

  Future<void> recomecar(WidgetTester tester) async {
    await tocar(tester, 'recomeçar a tradução');
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('with the sentence\'s microphone open, «recomeçar a tradução» '
      'is not taken', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await regravarAte(tester, harness, 3);
    await _tocarOCirculo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.gravando,
    );

    await recomecar(tester);

    expect(
      _recomecoArmado(),
      findsNothing,
      reason: 'o recomeço se armava com a frase sendo gravada',
    );
    expect(harness.room.restartsAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('with the sentence on its way, «recomeçar a tradução» is not '
      'taken', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    final segura = harness.room.holdTheSentence = Completer<void>();
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.enviando,
    );

    await recomecar(tester);

    expect(
      _recomecoArmado(),
      findsNothing,
      reason: 'o recomeço se armava com a frase a caminho da sala',
    );
    segura.complete();
    await _passo(tester);
    expect(harness.room.restartsAsked, isEmpty);
    closeTheRoom(container);
  });

  Future<void> recomecarDeVez(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await recomecar(tester);
    await tocar(tester, 'toque de novo para apagar as 4 frases traduzidas');
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);
  }

  testWidgets('a translation started over while a new part is owed lets the '
      'home stop saying the sentence could not be saved', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarSemAParte(tester, harness, 2);

    await recomecarDeVez(tester, container);
    container.read(salaSessionProvider.notifier).goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);

    expect(
      naCasa('não deu para guardar a frase — tentar de novo'),
      findsNothing,
      reason:
          'a casa seguia esperando uma frase de uma tradução que já foi '
          'apagada',
    );
    closeTheRoom(container);
  });

  testWidgets('a translation started over leaves no frase awaiting its '
      'translation', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await deitarAFrase(tester, harness, 2);
    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');

    await recomecarDeVez(tester, container);

    final aqui = container.read(salaSessionProvider);
    expect(
      aqui.btFraseQueAguarda,
      isNull,
      reason:
          'a frase regravada seguia esperando uma tradução que a sala já '
          'tinha arquivado',
    );
    expect(aqui.btTrechoTraduzidoDeNovo, isNull);
    closeTheRoom(container);
  });

  testWidgets('with the sentence under review, «recomeçar a tradução» rests '
      'dimmed and a tap arms nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    expect(naLinha('usar esta'), findsOneWidget);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.revendo,
    );

    expect(
      _recomecoDesenhado(tester),
      0.4,
      reason: 'o recomeço ficava aceso com a revisão da frase aberta',
    );
    await recomecar(tester);

    expect(
      _recomecoArmado(),
      findsNothing,
      reason: 'o recomeço armava por cima da frase sendo revista',
    );
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.revendo,
    );
    expect(guardada(harness), isTrue);
    closeTheRoom(container);
  });

  testWidgets('a translation started over lets a sentence held on the tablet '
      'go, so it never lands on a frase told afterwards', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    expect(container.read(salaSessionProvider).btFraseGuardada, 'trecho-3');

    await recomecarDeVez(tester, container);

    expect(
      container.read(salaSessionProvider).btFraseGuardada,
      isNull,
      reason: 'a frase guardada esperava uma frase 3 que a sala arquivou',
    );
    expect(guardada(harness), isFalse);
    closeTheRoom(container);
  });

  testWidgets('while the old sentence plays, «recomeçar a tradução» rests '
      'dimmed and a tap arms nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocar(tester, 'regravar a frase 3');
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.ouvindo,
    );

    expect(
      _recomecoDesenhado(tester),
      0.4,
      reason: 'o recomeço ficava aceso com a frase antiga tocando',
    );
    await recomecar(tester);

    expect(
      _recomecoArmado(),
      findsNothing,
      reason: 'o recomeço armava por cima da regravação aberta',
    );
    expect(harness.room.restartsAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('a dimmed «regravar» takes its own tap, so the row beneath it '
      'never opens the frase to tell again', (tester) async {
    var recontadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FraseList(
            language: 'pt',
            rows: [
              FraseRow(
                n: 2,
                parte: 1,
                share: 0.5,
                onHear: null,
                onRetell: () => recontadas++,
                regravar: 'regravar a frase 2',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('regravar a frase 2'));
    await tester.pump();
    expect(
      recontadas,
      0,
      reason: 'o toque no regravar apagado abria a frase para traduzir de novo',
    );

    await tester.tap(find.text('parte 1'));
    await tester.pump();
    expect(recontadas, 1);
  });

  Future<ProviderContainer> conferidaComANuanceNaFrase3(
    WidgetTester tester,
    SalaHarness harness,
  ) async {
    final container = await quatroFrasesEmWav(tester, harness);
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
    return container;
  }

  const aprovar = 'Aprovar como rascunho final';

  testWidgets('while the voice says the verdict again, a sentence held on the '
      'tablet is not sent by a tap, and its line is live again after', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await conferidaComANuanceNaFrase3(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(_acesa(tester, falhou), isTrue);

    harness.voice.holdNextLine();
    await tocar(tester, 'ouvir a resposta de novo');
    await _passo(tester);
    expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
    await tester.tap(naLinha(falhou));
    await _passo(tester);

    expect(
      harness.room.sentencesSent,
      hasLength(1),
      reason: 'a frase guardada subia de novo com a voz falando',
    );

    harness.voice.finishHeldLine();
    await _passo(tester);
    await _passo(tester);

    expect(_acesa(tester, falhou), isTrue);
    closeTheRoom(container);
  });

  testWidgets('while the microphone takes the next frase, «regravar» on a '
      'told one takes no tap, and is live again once that frase is told', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true)
      ..recorder.rehearsalSpeaks = aSpokenWav(length: parte);
    final container = await entrarNaTraducao(tester, harness);
    int contadas() => container
        .read(salaSessionProvider)
        .btTrechos
        .where((trecho) => trecho.contado)
        .length;
    harness.playback.at = cabeca;
    await _traduzir(tester);
    await waitFor(
      'a frase 1 ficar contada',
      () => contadas() == 1,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(_acesa(tester, 'regravar a frase 1'), isTrue);

    harness.playback.at = parte;
    await _tocarOCirculo(tester);
    await _tocarOCirculo(tester);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      _acesa(tester, 'regravar a frase 1'),
      isFalse,
      reason: 'regravar seguia aceitando toque com o microfone aberto',
    );

    await _tocarOCirculo(tester);
    await waitFor(
      'a frase seguinte ficar contada',
      () => contadas() == 2,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(_acesa(tester, 'regravar a frase 1'), isTrue);
    closeTheRoom(container);
  });

  testWidgets('while the room checks the telling, no «regravar» on the list '
      'takes a tap, and each is live again when the check comes back', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.verdictChecked = false;
    for (var n = 1; n <= 4; n++) {
      expect(_acesa(tester, 'regravar a frase $n'), isTrue);
    }

    harness.room.holdNextVerdict();
    await tocar(tester, 'terminei');
    await _passo(tester);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);
    expect(
      container.read(salaSessionProvider).channel,
      isNot(isA<GuideSpeaking>()),
    );
    for (var n = 1; n <= 4; n++) {
      expect(
        _acesa(tester, 'regravar a frase $n'),
        isFalse,
        reason: 'regravar seguia aceitando toque com a conferência no ar',
      );
    }

    harness.room.finishHeldVerdict();
    await waitFor(
      'a conferência voltar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
      step: () => _passo(tester),
    );
    await _passo(tester);

    for (var n = 1; n <= 4; n++) {
      expect(_acesa(tester, 'regravar a frase $n'), isTrue);
    }
    closeTheRoom(container);
  });

  testWidgets('while the voice says the verdict again no row of the list '
      'takes a tap, and every row is live again when it ends', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await conferidaComANuanceNaFrase3(tester, harness);
    final controles = [
      for (var n = 1; n <= 4; n++) ...[
        'Ouvir esta frase de novo e traduzir de novo — $n',
        'ouvir a minha tradução da frase $n',
      ],
      'regravar a frase 3',
    ];
    for (final controle in controles) {
      expect(_acesa(tester, controle), isTrue, reason: controle);
    }

    harness.voice.holdNextLine();
    await tocar(tester, 'ouvir a resposta de novo');
    await _passo(tester);

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
    for (final controle in controles) {
      expect(
        _acesa(tester, controle),
        isFalse,
        reason: 'a lista seguia aceitando toque com a voz falando: $controle',
      );
    }

    harness.voice.finishHeldLine();
    await _passo(tester);
    await _passo(tester);

    for (final controle in controles) {
      expect(
        _acesa(tester, controle),
        isTrue,
        reason: 'a lista ficava apagada depois que a voz terminou: $controle',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('while an approval is in the air, «regravar a frase 3» is not '
      'offered and does nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await conferidaComANuanceNaFrase3(tester, harness);
    expect(_naLista('regravar a frase 3'), findsOneWidget);
    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    harness.voice.holdNextLine();
    await tocar(tester, aprovar);

    expect(_naLista('regravar a frase 3'), findsNothing);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.regravarAFrase(
      container
          .read(salaSessionProvider)
          .btTrechos
          .firstWhere((trecho) => trecho.frase == 3),
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).btRegravacao, isNull);

    harness.voice.finishHeldLine();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('while an approval is in the air, a sentence held on the tablet '
      'is not sent again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await conferidaComANuanceNaFrase3(tester, harness);
    await gravarAFrase(tester, harness, 3);
    harness.room.sentenceAnswersFirst.add(const NetworkFailed('sem rede'));
    await tester.tap(naLinha('usar esta'));
    await _passo(tester);
    await _passo(tester);
    const falhou = 'não deu para guardar a frase — tentar de novo';
    expect(_naLista(falhou), findsOneWidget);

    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    harness.voice.holdNextLine();
    await tocar(tester, aprovar);
    expect(_acesa(tester, falhou), isFalse);
    container.read(salaSessionProvider.notifier).tentarAFraseDeNovo();
    await _passo(tester);

    expect(harness.room.sentencesSent, hasLength(1));
    harness.voice.finishHeldLine();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('a sentence whose review is open leaves the approval off', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await conferidaComANuanceNaFrase3(tester, harness);
    await gravarAFrase(tester, harness, 3);
    expect(naLinha('usar esta'), findsOneWidget);

    expect(
      tester.widget<Semantics>(byLabel(aprovar)).properties.enabled,
      isFalse,
    );
    await pressTheApproval(tester, aprovar);
    await _passo(tester);
    expect(harness.room.releasesAsked, isEmpty);
    await container.read(salaSessionProvider.notifier).aprovarRascunhoFinal();
    await _passo(tester);
    expect(harness.room.releasesAsked, isEmpty);
    closeTheRoom(container);
  });

  for (final (fala, comArquivo) in [
    ('a recording', true),
    ('no recording', false),
  ]) {
    testWidgets('a re-record whose microphone still closes takes no tap on '
        'its «regravar», and the late close with $fala finds the sentence '
        'still open', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await conferidaComANuanceNaFrase3(tester, harness);
      await regravarAte(tester, harness, 3);
      await _tocarOCirculo(tester);
      if (comArquivo) {
        harness.recorder.rehearsalSpeaks = aSpokenWav(
          length: const Duration(seconds: 2),
        );
      }
      harness.recorder.holdNextStop();
      await _tocarOCirculo(tester);
      await tocar(tester, 'regravar a frase 3');

      harness.recorder.finishStop();
      await _passo(tester);
      await _passo(tester);

      expect(
        container.read(salaSessionProvider).btRegravacao?.segmentId,
        'trecho-3',
        reason: 'o toque em regravar com o microfone fechando largava a frase',
      );
      closeTheRoom(container);
    });
  }

  Future<ProviderContainer> aRefusalReadLandsAfterTheHeldSentenceWentUp(
    WidgetTester tester,
    SalaHarness harness, {
    required BackTranslationProgress theReadInTheAir,
    required BackTranslationProgress theRoomNow,
    void Function(ProviderContainer)? whileTheReplaceIsHeld,
  }) async {
    final pasta = Directory.systemTemp.createTempSync('sala-1789');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-1',
    );
    await _passo(tester);
    await _passo(tester);
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _traduzirDeNovo(tester);
    await _tocarOCirculo(tester);
    await _passo(tester);
    harness.room
      ..retroSoFar = theReadInTheAir
      ..holdTheNextRead()
      ..awaitingSegmentId = 'trecho-1'
      ..sentenceAnswersFirst.add(const Refused('ANOTHER_SENTENCE_AWAITS'));
    await _tocarOCirculo(tester);
    await waitFor(
      'a leitura da recusa sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );
    harness.room.retroSoFar = theRoomNow;

    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);
    await _passo(tester);
    harness.room.holdNextReplace();
    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);
    whileTheReplaceIsHeld?.call(container);
    harness.room.finishHeldReplace();
    await _passo(tester);
    await _passo(tester);
    return container;
  }

  testWidgets('while the room is read back after a telling whose answer was '
      'lost, the list rests no more and the held sentence can be sent', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-2067');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-1',
    );
    await _passo(tester);
    await _passo(tester);
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _traduzirDeNovo(tester);
    await _tocarOCirculo(tester);
    await _passo(tester);
    harness.room.holdTheNextRead();
    await _tocarOCirculo(tester);
    await waitFor(
      'a leitura da recusa sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      _acesa(tester, 'não deu para guardar a frase — tentar de novo'),
      isTrue,
      reason: 'a leitura da sala depois da resposta perdida prendia a lista',
    );
    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);
    closeTheRoom(container);
  });

  final successor = BackTranslationProgress(
    segments: [
      const SegmentView(
        segmentId: 'trecho-1-v1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 4000,
        frase: 1,
        told: true,
      ),
      ..._daSala.skip(1),
    ],
    awaitingSegmentId: 'trecho-1',
  );

  testWidgets('a refusal read that lands after the held sentence went up '
      'still lets the translation go on the stretch that took its place', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aRefusalReadLandsAfterTheHeldSentenceWentUp(
      tester,
      harness,
      theReadInTheAir: BackTranslationProgress(
        segments: [
          ...successor.segments.take(3),
          const SegmentView(
            segmentId: 'trecho-4',
            takeId: 'gravacao-2',
            startsMs: 4000,
            endsMs: 9000,
            frase: 4,
          ),
        ],
        awaitingSegmentId: 'trecho-1',
      ),
      theRoomNow: successor,
      whileTheReplaceIsHeld: (container) => expect(
        container.read(salaSessionProvider).btTrechos.last.to,
        const Duration(seconds: 10),
        reason: 'a leitura de antes devolvia a fileira que a sala já trocou',
      ),
    );

    expect(
      harness.room.replacesAsked.last,
      startsWith('trecho-1-v1@'),
      reason: 'a leitura velha apagava a tradução da equipe',
    );
    closeTheRoom(container);
  });

  testWidgets('a refusal read that lands after the held sentence went up '
      'never writes the stretches of an older room over the newer ones', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aRefusalReadLandsAfterTheHeldSentenceWentUp(
      tester,
      harness,
      theReadInTheAir: BackTranslationProgress(
        segments: _daSala,
        awaitingSegmentId: 'trecho-1',
      ),
      theRoomNow: successor,
    );

    expect(
      [
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          trecho.segmentId,
      ],
      ['trecho-1-v1', 'trecho-2', 'trecho-3', 'trecho-4'],
      reason: 'a leitura de antes devolvia os trechos que a sala já trocou',
    );
    closeTheRoom(container);
  });

  testWidgets('a read of the stretches in the air never takes the translation '
      'that landed after it back to the old stretch', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-1789');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-1',
    );
    await _passo(tester);
    await _passo(tester);
    harness.room
      ..holdTheNextRead()
      ..sentenceAnswersFirst.add(const Refused('ANOTHER_SENTENCE_AWAITS'));
    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await waitFor(
      'a leitura dos trechos sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );
    harness.room.holdNextReplace();
    await _traduzirDeNovo(tester);
    harness.room.finishHeldReplace();
    await _passo(tester);
    await _passo(tester);

    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);

    final aqui = container.read(salaSessionProvider);
    expect(aqui.btTrechos.first.segmentId, 'trecho-1-v1');
    expect(
      aqui.btFraseQueAguarda,
      isNull,
      reason: 'a leitura de antes da tradução devolvia a frase que já foi dita',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase the team chose while the room was read back after a '
      'lost telling stays chosen when the read lands, not the old stretch', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(tester, harness);
    await _passo(tester);
    await _passo(tester);
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 2');
    await _passo(tester);
    await _traduzirDeNovo(tester);
    await _tocarOCirculo(tester);
    await _passo(tester);
    harness.room
      ..retroSoFar = BackTranslationProgress(
        segments: [
          _daSala.first,
          const SegmentView(
            segmentId: 'trecho-2-v1',
            takeId: 'gravacao-1',
            startsMs: 4000,
            endsMs: 10000,
            frase: 2,
          ),
          ..._daSala.skip(2),
        ],
      )
      ..holdTheNextRead();
    await _tocarOCirculo(tester);
    await waitFor(
      'a leitura da recusa sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 3');
    await _passo(tester);
    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);

    final aqui = container.read(salaSessionProvider);
    expect(
      aqui.btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-3',
      reason: 'a leitura levava a equipe de volta ao trecho que ela deixou',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a telling the team began while the room was read back after a '
    'lost one keeps its microphone when the read lands, and nothing is sent',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _voltaATraducao(tester, harness);
      await _passo(tester);
      await _passo(tester);
      harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed(
        'timeout',
      );
      await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 2');
      await _passo(tester);
      await _traduzirDeNovo(tester);
      await _tocarOCirculo(tester);
      await _passo(tester);
      harness.room
        ..retroSoFar = BackTranslationProgress(
          segments: [
            _daSala.first,
            const SegmentView(
              segmentId: 'trecho-2-v1',
              takeId: 'gravacao-1',
              startsMs: 4000,
              endsMs: 10000,
              frase: 2,
            ),
            ..._daSala.skip(2),
          ],
        )
        ..holdTheNextRead();
      await _tocarOCirculo(tester);
      await waitFor(
        'a leitura da recusa sair e ficar presa',
        () => harness.room.heldReads.isNotEmpty,
        step: () => _passo(tester),
      );
      final pedidas = harness.room.replacesAsked.length;

      await _tocarOCirculo(tester);
      expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
      harness.room.answerHeldRead(0);
      await _passo(tester);
      await _passo(tester);

      expect(
        container.read(salaSessionProvider).btPhase,
        BtPhase.capturing,
        reason: 'a leitura fechava a gravação que a equipe tinha aberto',
      );
      expect(
        harness.room.replacesAsked,
        hasLength(pedidas),
        reason: 'a tradução perdida subia com o microfone da equipe aberto',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a telling the team began while the room was read back after a '
      'lost one outlives the wait the read left behind', (tester) async {
    final harness = SalaHarness(
      filaEmMemoria: true,
      busyCeiling: const Duration(seconds: 1),
    );
    final container = await _voltaATraducao(tester, harness);
    await _passo(tester);
    await _passo(tester);
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 2');
    await _passo(tester);
    await _traduzirDeNovo(tester);
    await _tocarOCirculo(tester);
    await _passo(tester);
    harness.room
      ..retroSoFar = BackTranslationProgress(
        segments: [
          _daSala.first,
          const SegmentView(
            segmentId: 'trecho-2-v1',
            takeId: 'gravacao-1',
            startsMs: 4000,
            endsMs: 10000,
            frase: 2,
          ),
          ..._daSala.skip(2),
        ],
      )
      ..holdTheNextRead();
    await _tocarOCirculo(tester);
    await waitFor(
      'a leitura da recusa sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );
    await _tocarOCirculo(tester);
    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btPhase, BtPhase.capturing);
    final geracao = aqui.machine.generation;

    await tester.pump(const Duration(milliseconds: 1500));

    expect(
      container.read(salaSessionProvider).machine.generation,
      geracao,
      reason:
          'a sala seguia esperando depois da leitura e, no teto, desistia no '
          'meio da gravação da equipe: os relógios e as respostas no ar caíam',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    closeTheRoom(container);
  });

  testWidgets('a held sentence sent while the room was read back after a lost '
      'telling is not run over by that telling when the read lands', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final pasta = Directory.systemTemp.createTempSync('sala-2067');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await harness.takes.enqueue(
      File('${pasta.path}/frase.wav')
        ..writeAsBytesSync(aSpokenWav(length: const Duration(seconds: 2))),
      sessionId: 'sessao-antiga',
      kind: 'frase',
      scope: 'trecho-3',
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-1',
    );
    await _passo(tester);
    await _passo(tester);
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _traduzirDeNovo(tester);
    await _tocarOCirculo(tester);
    await _passo(tester);
    harness.room
      ..retroSoFar = successor
      ..holdTheNextRead()
      ..awaitingSegmentId = 'trecho-1';
    await _tocarOCirculo(tester);
    await waitFor(
      'a leitura da recusa sair e ficar presa',
      () => harness.room.heldReads.isNotEmpty,
      step: () => _passo(tester),
    );
    harness.room.holdTheSentence = Completer<void>();
    await tocar(tester, 'não deu para guardar a frase — tentar de novo');
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.enviando,
    );
    final pedidas = harness.room.replacesAsked.length;

    harness.room.answerHeldRead(0);
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.room.replacesAsked,
      hasLength(pedidas),
      reason: 'a tradução perdida subia por cima da frase que ainda subia',
    );
    harness.room.holdTheSentence!.complete();
    await _passo(tester);
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('back on the home, the scene whose only open frase awaits its '
      'new sentence says «regravada — traduzam esta frase»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-2',
    );
    container.read(salaSessionProvider.notifier).goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);

    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');
    Finder naLinha(int n) => find.descendant(
      of: byLabel('Cena $n'),
      matching: find.text('regravada — traduzam esta frase'),
    );
    expect(
      naLinha(1),
      findsOneWidget,
      reason: 'a casa não dizia que uma frase da cena espera a tradução',
    );
    expect(naLinha(2), findsNothing);
    expect(
      find.text('regravada — traduzam de novo'),
      findsNothing,
      reason: 'a frase que espera não é uma frase caducada',
    );
    closeTheRoom(container);
  });

  testWidgets('a scene with a frase that awaits and another gone stale says '
      '«regravada — traduzam de novo», as hers does', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      aguardando: 'trecho-2',
      regravadas: const [
        SegmentView(
          segmentId: 'trecho-velho',
          takeId: 'gravacao-velha-1',
          startsMs: 0,
          endsMs: 4000,
        ),
      ],
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    container.read(salaSessionProvider.notifier).goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await _passo(tester);

    expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');
    expect(
      find.descendant(
        of: byLabel('Cena 1'),
        matching: find.text('regravada — traduzam de novo'),
      ),
      findsOneWidget,
      reason:
          'a frase que espera escondia a frase caducada da mesma cena, que '
          'também precisa ser traduzida de novo',
    );
    closeTheRoom(container);
  });
}
