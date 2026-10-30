import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
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
    show cabeca, entrarNaTraducao, parte, passaDoCursor, tocar, tocarNoCirculo;
import 'the_pause_snaps_to_silence_test.dart'
    show
        entrarComAFala,
        ouvirAPausa,
        pausarAos,
        s,
        tocarOCirculo,
        traduzirEConfirmar,
        umaLacunaAos3;

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
  await holdTheSession(
    harness,
    ResumePoint(
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
    ),
    language: lingua,
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await intoTheBackTranslation(
    container.read(salaSessionProvider.notifier),
    () => container.read(salaSessionProvider),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await waitFor(
    'o conferir voltar com as frases que a sala guardou',
    () =>
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
    texto.textSpan?.toPlainText() ?? texto.data ?? '',
];

Color? _corDaMarca(WidgetTester tester) {
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(PartStrips), matching: find.byType(Text)),
  )) {
    if (texto.textSpan case TextSpan(:final children?)) {
      for (final pedaco in children) {
        if (pedaco case TextSpan(text: ' ·', :final style)) return style?.color;
      }
    }
  }
  return null;
}

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

List<double?> _ondeOTocadorEsta(WidgetTester tester) => [
  for (final faixa in _faixas(tester))
    switch ((tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byWidget(faixa),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as SceneStripPainter)
        .drawing
        .playhead) {
      final x? => x / faixa.width,
      null => null,
    },
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

  testWidgets('a take paused partway keeps the player on its strip where it '
      'stopped, and the other part draws none', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = const Duration(seconds: 3);
    await tester.pump(passaDoCursor);

    await tocar(tester, 'Pausar');

    expect(container.read(salaSessionProvider).channel, isA<Paused>());
    expect(
      _ondeOTocadorEsta(tester),
      [closeTo(0.3, 1e-9), null],
      reason:
          'a gravação pausada apagava a linha do tocador, e a equipe não via '
          'onde tinha parado',
    );
    closeTheRoom(container);
  });

  testWidgets('the player stays where the take stopped while «ouvir a pausa» '
      'plays over it, not on the clock of the moment played', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    await tocar(tester, ouvirAPausa);

    expect(container.read(salaSessionProvider).channel, isA<StretchPlaying>());
    expect(
      _ondeOTocadorEsta(tester),
      [closeTo(0.42, 1e-9)],
      reason:
          'ouvir a pausa apagava a linha do tocador do lugar onde a gravação '
          'tinha parado',
    );
    closeTheRoom(container);
  });

  testWidgets('the player stays where the take stopped when the team pauses '
      '«ouvir a pausa» partway', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));
    await tocar(tester, ouvirAPausa);

    await tocar(tester, 'Pausar');

    expect(
      container.read(salaSessionProvider).channel,
      isA<Paused>().having(
        (parada) => parada.what,
        'what',
        isA<StretchSound>(),
      ),
    );
    expect(
      _ondeOTocadorEsta(tester),
      [closeTo(0.42, 1e-9)],
      reason:
          'pausar o «ouvir a pausa» apagava a linha do tocador do lugar onde '
          'a gravação tinha parado',
    );
    closeTheRoom(container);
  });

  testWidgets('the player stays where the take stopped while the team tells '
      'the frase into the microphone', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    await tocarOCirculo(tester);

    expect(container.read(salaSessionProvider).channel, isA<Microphone>());
    expect(
      _ondeOTocadorEsta(tester),
      [closeTo(0.42, 1e-9)],
      reason:
          'o microfone aberto apagava a linha do tocador, e a equipe perdia '
          'onde a gravação tinha parado',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase of another part replayed over the paused take takes the '
      'player off the paused strip', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 5000,
            frase: 2,
          ),
        ],
      ),
    );
    final notifier = container.read(salaSessionProvider.notifier);
    harness.playback.at = const Duration(seconds: 6);
    await tester.pump(passaDoCursor);
    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_ondeOTocadorEsta(tester), [closeTo(0.6, 1e-9), null]);

    notifier.ouvirOTrechoContado(1);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).channel, isA<StretchPlaying>());
    expect(
      _ondeOTocadorEsta(tester),
      [null, null],
      reason:
          'a frase da parte 2 tocava e a linha do tocador seguia parada na '
          'parte 1, como se fosse ela que soasse',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase of another part paused over the paused take still '
      'keeps the player off the paused strip', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 5000,
            frase: 2,
          ),
        ],
      ),
    );
    final notifier = container.read(salaSessionProvider.notifier);
    harness.playback.at = const Duration(seconds: 6);
    await tester.pump(passaDoCursor);
    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.ouvirOTrechoContado(1);
    await tester.pump(const Duration(milliseconds: 300));

    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).channel,
      isA<Paused>().having(
        (parada) => parada.what,
        'what',
        isA<StretchSound>(),
      ),
    );
    expect(
      _ondeOTocadorEsta(tester),
      [null, null],
      reason:
          'a frase da parte 2 pausada devolvia a linha do tocador à parte 1, '
          'que não tinha voltado a soar',
    );
    closeTheRoom(container);
  });

  testWidgets('the team\'s own translation played over the paused take keeps '
      'the player where the take stopped', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));
    await traduzirEConfirmar(tester);
    await waitFor(
      'a frase contada pousar com a tradução da equipe',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado && trecho.retroPath != null),
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    final notifier = container.read(salaSessionProvider.notifier);
    harness.playback.at = s(6.0);
    await tester.pump(passaDoCursor);
    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 300));

    notifier.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).channel,
      isA<StretchPlaying>().having(
        (tocando) => tocando.stretch.telling,
        'telling',
        isTrue,
      ),
    );
    expect(
      _ondeOTocadorEsta(tester),
      [closeTo(0.6, 1e-9)],
      reason:
          'a tradução da equipe tocada sobre a gravação pausada apagava a '
          'linha do tocador, que não tinha saído do lugar',
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

  testWidgets('a part paused in the player, or held under the microphone, '
      'keeps its row whole instead of fading with the rest', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = const Duration(seconds: 3);
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);

    expect(container.read(salaSessionProvider).channel, isA<Paused>());
    expect(
      _brilhos(tester),
      [1.0, 0.7],
      reason:
          'a parte pausada no meio da frase apagava junto com as outras, e '
          'a equipe perdia de vista a parte em que estava',
    );

    final sala = container.read(salaSessionProvider.notifier);
    final pausada = sala.state.channel as Paused;
    sala.state = sala.state.copyWith(
      machine: sala.state.machine.copyWith(
        channel: GuideSpeaking(const Line(LineKind.guide, 1), held: pausada),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _brilhos(tester),
      [1.0, 0.7],
      reason:
          'a voz falando por cima da parte pausada apagava a fileira da '
          'parte que esperava a equipe',
    );

    sala.state = sala.state.copyWith(
      machine: sala.state.machine.copyWith(channel: pausada),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tocarNoCirculo(tester);

    expect(container.read(salaSessionProvider).channel, isA<Microphone>());
    expect(
      _brilhos(tester),
      [1.0, 0.7],
      reason:
          'com o microfone aberto sobre a parte, nenhuma fileira dizia qual '
          'parte estava sendo traduzida',
    );
    closeTheRoom(container);
  });

  testWidgets('a part the room counts unheard carries her dot after its '
      'label, and loses it once the room has heard it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.listeningUnheardTakeIds = const ['gravacao-2'];
    final container = await entrarNaTraducao(tester, harness);
    await waitFor(
      'a primeira parte tocar',
      () => container.read(salaSessionProvider).btClipRodando,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _rotulos(tester),
      ['parte 1', 'parte 2 ·'],
      reason:
          'nada na fileira dizia que a sala ainda não tinha ouvido a parte '
          '2, e a equipe não via o que faltava ouvir',
    );
    expect(_corDaMarca(tester), const Color(0xFFBE4A01));
    expect(_brilhos(tester), [1.0, 0.7]);

    harness.room.listeningUnheardTakeIds = const [];
    harness.playback.finishPlayback();
    await waitFor(
      'a sala responder que ouviu tudo',
      () => container.read(salaSessionProvider).btNaoOuvidas.isEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _rotulos(tester),
      ['parte 1', 'parte 2'],
      reason:
          'a marca ficava depois que a sala dizia que já não faltava ouvir '
          'nada',
    );
    closeTheRoom(container);
  });

  testWidgets('a part that stopped sounding keeps its row whole, '
      'not faded with the part that comes next', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    final sala = container.read(salaSessionProvider.notifier);
    sala.state = sala.state.copyWith(
      machine: sala.state.machine.copyWith(channel: const Silence()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _brilhos(tester),
      [1.0, 0.7],
      reason:
          'a parte que acabava de tocar apagava junto com as outras, e nenhuma '
          'fileira dizia onde a gravação tinha parado',
    );
    closeTheRoom(container);
  });

  testWidgets('the last part keeps its row whole after the whole recording '
      'has played', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(container.read(salaSessionProvider).btClipRodando, isFalse);
    expect(
      _brilhos(tester),
      [1.0],
      reason:
          'no fim da gravação a última parte apagava, e a tela não mostrava '
          'mais nenhuma parte como a que tocou',
    );
    closeTheRoom(container);
  });

  testWidgets('a check that comes back with its ground told to the end marks '
      'no row before anything has played', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.listeningUnheardTakeIds = const [];
    final container = await _voltaAoConferir(
      tester,
      harness,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 10000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 10000,
            frase: 2,
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(harness.playback.played, isEmpty);
    expect(
      _brilhos(tester),
      [0.7, 0.7],
      reason:
          'a volta ao conferir já contado acendia a última parte sem que nada '
          'tivesse tocado',
    );
    closeTheRoom(container);
  });

  testWidgets('a check entered again marks no row until a part plays in it, '
      'never the part that played on the last visit', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    expect(_brilhos(tester), [1.0, 0.7]);

    sala.goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.holdNextListening();
    sala.startRetro();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipRodando, isFalse);
    expect(
      _brilhos(tester),
      [0.7, 0.7],
      reason:
          'a volta ao conferir acendia a parte que tinha tocado na visita '
          'anterior, antes de qualquer parte tocar de novo',
    );
    harness.room.finishHeldListening();
    closeTheRoom(container);
  });

  testWidgets('a part landed without this tablet learning its name carries her '
      'dot, since the room has not heard it and the team is sent to hear it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room
      ..listeningUnheardTakeIds = const []
      ..failTakesWith = const NetworkFailed('sem rede')
      ..takes.addAll(const [
        TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
        TakeView(
          takeId: 'da-sala-2',
          kind: 'ensaio',
          scope: 'parte-2',
          ordinal: 2,
        ),
      ]);
    harness.playback
      ..measured = parte
      ..length = parte;
    final pasta = Directory.systemTemp.createTempSync('sala-parte-sem-nome');
    addTearDown(() => pasta.deleteSync(recursive: true));
    await holdTheSession(
      harness,
      ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: [
          for (var n = 1; n <= 2; n++)
            KeptTake(
              scopeId: KeptScope.parte(n),
              path: (File('${pasta.path}/p$n.m4a')..writeAsBytesSync([n])).path,
              takeId: n == 1 ? 'gravacao-1' : null,
            ),
        ],
      ),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await intoTheBackTranslation(
      container.read(salaSessionProvider.notifier),
      () => container.read(salaSessionProvider),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).partes[1].takeId, isNull);
    expect(
      _rotulos(tester),
      ['parte 1', 'parte 2 ·'],
      reason:
          'a parte que ainda subia era a que a sala mandava ouvir, e a '
          'fileira dela não dizia que faltava ouvi-la',
    );
    closeTheRoom(container);
  });
}
