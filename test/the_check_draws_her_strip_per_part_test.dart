import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'resto_da_historia_test.dart' show aHistoriaSemOFim;
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show cabeca, entrarNaTraducao, passaDoCursor, tocarNoCirculo;

const _duasFrasesNaParteUm = [
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
    endsMs: 9000,
    frase: 2,
  ),
];

Future<ProviderContainer> _voltaAoConferir(
  WidgetTester tester,
  SalaHarness harness, {
  BackTranslationProgress contado = const BackTranslationProgress(
    segments: _duasFrasesNaParteUm,
  ),
  String lingua = testLanguage,
  bool inteira = false,
  Uint8List? fala,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1882');
  addTearDown(() => pasta.deleteSync(recursive: true));
  String arquivo(String nome) => (File(
    '${pasta.path}/$nome',
  )..writeAsBytesSync(fala ?? Uint8List.fromList([1, 2, 3]))).path;
  harness.playback.measured = const Duration(seconds: 10);
  harness.emAberto.rows['Ruth/P01/$lingua'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      if (inteira)
        KeptTake(
          scopeId: KeptScope.whole,
          path: arquivo('inteira.wav'),
          takeId: 'gravacao-inteira',
        )
      else
        for (final n in [1, 2])
          KeptTake(
            scopeId: KeptScope.parte(n),
            path: arquivo('p$n.wav'),
            takeId: 'gravacao-$n',
          ),
    ],
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'o conferir voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length ==
            contado.segments.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

List<String> _rotulos(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(PartStrips), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

List<double> _brilhos(WidgetTester tester) => [
  for (final linha in tester.widgetList<Opacity>(
    find.descendant(
      of: find.byType(PartStrips),
      matching: find.byType(Opacity),
    ),
  ))
    linha.opacity,
];

List<SceneStrip> _faixas(WidgetTester tester) => [
  ...tester.widgetList<SceneStrip>(
    find.descendant(
      of: find.byType(PartStrips),
      matching: find.byType(SceneStrip),
    ),
  ),
];

void main() {
  testWidgets('the check writes parte N beside each part of the recording, '
      'in the order the team recorded them', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(tester, harness);

    expect(
      _rotulos(tester),
      ['parte 1', 'parte 2'],
      reason:
          'o conferir mostrava uma fileira de contas sem nada escrito, e a '
          'equipe não sabia de que parte era cada uma',
    );
    closeTheRoom(container);
  });

  testWidgets('a recording of the whole passage is written as the whole '
      'passage, never as a part the team did not make', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _voltaAoConferir(
      tester,
      harness,
      lingua: 'en',
      inteira: true,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
      ),
    );

    expect(_rotulos(tester), [
      'The whole passage',
    ], reason: 'a gravação inteira aparecia como «part 1»');
    closeTheRoom(container);
  });

  testWidgets('a recording of the whole passage writes its place beside play '
      'as her clock alone, never as a part the team did not make', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      inteira: true,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
      ),
    );
    harness.playback.length = const Duration(seconds: 10);

    harness.playback.at = const Duration(seconds: 5);
    await tester.pump(passaDoCursor);

    expect(
      find.text('ouvindo a gravação de vocês… — 0:05 / 0:10'),
      findsOneWidget,
      reason: 'a gravação inteira tocava como «parte 1»',
    );
    closeTheRoom(container);
  });

  testWidgets('each part strip draws the loudness of its own take, so a '
      'silence reads as a valley', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      fala: aSpokenWav(
        gaps: [(const Duration(seconds: 3), const Duration(seconds: 4))],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final faixas = _faixas(tester);
    expect(faixas, hasLength(2));
    for (final faixa in faixas) {
      expect(faixa.length, const Duration(seconds: 10));
      final fala = faixa.envelope!.loudness;
      expect(
        fala[175],
        0,
        reason: 'o silêncio dos 3 aos 4 segundos não aparecia na tela',
      );
      expect(fala[50], greaterThan(0));
    }
    closeTheRoom(container);
  });

  testWidgets('a checked passage picked back up draws each part with its own '
      'loudness, not the word alone', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: _duasFrasesNaParteUm,
        checked: true,
      ),
      fala: aSpokenWav(
        gaps: [(const Duration(seconds: 3), const Duration(seconds: 4))],
      ),
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    await waitFor(
      'as duas partes terem a sua fala lida',
      () => container.read(salaSessionProvider).partLoudness.length == 2,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final faixas = _faixas(tester);
    expect(
      faixas,
      hasLength(2),
      reason:
          'a passagem conferida reaberta mostrava «parte 1» e «parte 2» sem '
          'nenhuma faixa ao lado',
    );
    for (final faixa in faixas) {
      expect(faixa.length, const Duration(seconds: 10));
      expect(faixa.envelope!.loudness[175], 0);
      expect(faixa.envelope!.loudness[50], greaterThan(0));
    }
    closeTheRoom(container);
  });

  testWidgets('a checked passage picked back up knows where each part ends, '
      'as one checked in a single sitting does', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: _duasFrasesNaParteUm,
        checked: true,
      ),
    );
    await waitFor(
      'o fim das duas partes ficar conhecido',
      () => container.read(salaSessionProvider).btFimDasPartesMs.length == 2,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(
      container.read(salaSessionProvider).btFimDasPartesMs,
      [10000, 20000],
      reason:
          'a passagem conferida reaberta media as partes mas a régua da tela '
          'ficava vazia, e o começo de cada parte era lido de dois jeitos',
    );
    closeTheRoom(container);
  });

  testWidgets('a checked passage picked back up reads its parts one take at '
      'a time, never every take at once', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)..holdTheEnvelope();
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: _duasFrasesNaParteUm,
        checked: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    harness.giveTheEnvelope();
    await waitFor(
      'as duas partes terem a sua fala lida',
      () => container.read(salaSessionProvider).partLoudness.length == 2,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(container.read(salaSessionProvider).partLoudness, hasLength(2));
    expect(
      harness.mostEnvelopesReadAtOnce,
      1,
      reason:
          'a passagem conferida reaberta abria a leitura de todas as partes '
          'de uma vez, com cada arquivo inteiro na memória do tablet',
    );
    closeTheRoom(container);
  });

  testWidgets('a told frase is a band on the strip of its own part, and the '
      'time nobody told carries none', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: [
          ..._duasFrasesNaParteUm,
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 5000,
            told: false,
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      [
        for (final faixa in _faixas(tester))
          [for (final frase in faixa.frases) (frase.startsMs, frase.endsMs)],
      ],
      [
        [(0, 4000), (4000, 9000)],
        <(int?, int?)>[],
      ],
      reason:
          'as frases traduzidas eram contas soltas, sem o lugar de cada uma '
          'na gravação',
    );
    closeTheRoom(container);
  });

  testWidgets('the stretch a finding points at stays a band like any told '
      'one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await tester.pump(const Duration(milliseconds: 1600));
    expect(container.read(salaSessionProvider).btFindingSegmentId, 'trecho-2');

    expect(
      [for (final faixa in _faixas(tester)) faixa.frases.length],
      [1, 1, 1],
      reason:
          'a conta do achado ficava esvaziada; na tela dela o achado é '
          'marcado só na linha da frase',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told over a part recorded again is drawn faint on that '
      'part, never as a told band', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    List<List<(int?, int?)>> spans(List<SceneFrase> Function(SceneStrip) of) =>
        [
          for (final faixa in _faixas(tester))
            [for (final frase in of(faixa)) (frase.startsMs, frase.endsMs)],
        ];
    expect(
      spans((faixa) => faixa.stale),
      [
        [(0, 4000)],
        <(int?, int?)>[],
      ],
      reason: 'a frase da parte regravada sumia da gravação',
    );
    expect(spans((faixa) => faixa.frases), [
      <(int?, int?)>[],
      [(0, 6000)],
    ]);
    closeTheRoom(container);
  });

  testWidgets('the pending pausa is drawn on the strip of the part in the air, '
      'and the player rides only the part that sounds', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(
      [for (final faixa in _faixas(tester)) faixa.playing],
      [true, false],
      reason: 'nada mostrava onde a gravação estava tocando',
    );
    expect([for (final faixa in _faixas(tester)) faixa.pausa], [null, null]);

    harness.playback.at = const Duration(seconds: 3);
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);

    expect(
      [for (final faixa in _faixas(tester)) faixa.pausa],
      [const Duration(seconds: 3), null],
      reason:
          'a conta pendente era o único sinal de onde a frase acabava, e '
          'ela não dizia onde',
    );
    closeTheRoom(container);
  });

  testWidgets('the strip cannot be tapped and names nothing to VoiceOver, so '
      'the frase rows and the play control are the ways to hear', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.fraseDaProximaFrase = 7;
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(
      [
        byLabel('frase 7'),
        byLabel('parte 1'),
      ].map((rotulo) => tester.widgetList(rotulo).length),
      [0, 0],
      reason:
          'a fileira de contas se lia ao VoiceOver como botões que tocavam '
          'cada trecho',
    );

    final sons = harness.sounds.length;
    await tester.tap(find.byType(SceneStrip).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    final depois = container.read(salaSessionProvider);
    expect(harness.sounds.skip(sons), isEmpty);
    expect(depois.btContaEscolhida, isNull);
    expect(depois.btTrechoTraduzidoDeNovo, isNull);
    closeTheRoom(container);
  });

  testWidgets('the whole passage is written whole beside its strip on a '
      'phone, never cut short', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _voltaAoConferir(
      tester,
      harness,
      lingua: 'en',
      inteira: true,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
      ),
    );
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    await tester.pump(const Duration(milliseconds: 100));

    final rotulo = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(
          of: find.byType(PartStrips),
          matching: find.text('The whole passage'),
        ),
        matching: find.byType(RichText),
      ),
    );
    expect(
      rotulo.didExceedMaxLines,
      isFalse,
      reason: 'o rótulo da passagem inteira saía cortado em reticências no SE',
    );
    expect(find.byType(SceneStrip), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('the loudness of the parts is read one take at a time, never '
      'every take at once', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)..holdTheEnvelope();
    final container = await entrarNaTraducao(tester, harness);
    harness.giveTheEnvelope();
    await waitFor(
      'as duas partes terem a sua fala lida',
      () => container.read(salaSessionProvider).partLoudness.length == 2,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(container.read(salaSessionProvider).partLoudness, hasLength(2));
    expect(
      harness.mostEnvelopesReadAtOnce,
      1,
      reason:
          'cada parte abria a sua leitura ao mesmo tempo, com o arquivo '
          'inteiro de cada uma na memória do tablet',
    );
    closeTheRoom(container);
  });

  testWidgets('a loudness still being read when the team leaves the passage '
      'never lands in the next one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)..holdTheEnvelope();
    final container = await entrarNaTraducao(tester, harness);
    expect(harness.envelopesBeingRead, 1);

    container.read(salaSessionProvider.notifier).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 300));
    harness.giveTheEnvelope();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.envelopesBeingRead, 0);
    expect(
      container.read(salaSessionProvider).partLoudness,
      isEmpty,
      reason:
          'a leitura que terminava depois da saída deixava a fala de uma '
          'parte da passagem deixada no estado da próxima',
    );
    closeTheRoom(container);
  });

  testWidgets('the row of the part in the player is drawn whole, and every '
      'other row is drawn faint', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(
      _brilhos(tester),
      [1.0, 0.7],
      reason:
          'todas as fileiras ficavam iguais, e nada dizia de que parte era '
          'o que estava tocando',
    );
    closeTheRoom(container);
  });
}
