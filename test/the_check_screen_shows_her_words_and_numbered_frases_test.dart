import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/dashed_edge.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show contrastOf;
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheBackTranslation,
        intoTheRecordingHome,
        linhaDoEnsaio,
        traduzirOApontadoDeNovo;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        contarAteOFimDaParte,
        entrarNaTraducao,
        fimDaGravacao,
        parte,
        tocar,
        tocarNoCirculo;

const _quatroFrases = [
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
  SegmentView(
    segmentId: 'trecho-3',
    takeId: 'gravacao-2',
    startsMs: 0,
    endsMs: 6000,
    frase: 3,
  ),
  SegmentView(
    segmentId: 'trecho-4',
    takeId: 'gravacao-2',
    startsMs: 6000,
    endsMs: 8000,
    frase: 4,
  ),
];

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

final _apagando = find.byWidgetPredicate(
  (widget) => switch (widget) {
    Opacity(:final opacity) || AnimatedOpacity(:final opacity) => opacity < 1,
    FadeTransition(:final opacity) => opacity.value < 1,
    _ => false,
  },
);

double _veu(WidgetTester tester, Finder alvo, {Type tela = RetroView}) => tester
    .widgetList(
      find.ancestor(
        of: alvo,
        matching: find.descendant(
          of: find.byType(tela),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity || widget is FadeTransition,
          ),
        ),
      ),
    )
    .fold(
      1.0,
      (veu, widget) =>
          veu *
          switch (widget) {
            Opacity(:final opacity) => opacity,
            FadeTransition(:final opacity) => opacity.value,
            _ => 1.0,
          },
    );

double piorContraste(
  WidgetTester tester,
  String rotulo, {
  Type tela = RetroView,
  Finder? control,
}) {
  final botao = control ?? byLabel(rotulo);
  final texto = find.descendant(of: botao, matching: find.text(rotulo));
  final disco = find.descendant(
    of: botao,
    matching: find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    ),
  );
  final papel = Theme.of(tester.element(botao)).scaffoldBackgroundColor;
  final tinta = tester.widget<Text>(texto).style!.color!;
  final pintura = tester.widget<Container>(disco).decoration! as BoxDecoration;
  final paradas = pintura.gradient?.colors ?? [pintura.color!];
  final veuDoDisco = _veu(tester, disco, tela: tela);
  final veuDaTinta = _veu(tester, texto, tela: tela);
  return paradas
      .map((parada) {
        final fundo = Color.alphaBlend(
          parada.withValues(alpha: veuDoDisco),
          papel,
        );
        final letra = Color.alphaBlend(
          tinta.withValues(alpha: veuDaTinta),
          fundo,
        );
        return contrastOf(letra, fundo);
      })
      .reduce((um, outro) => um < outro ? um : outro);
}

const _rem = 16.0;

Future<ProviderContainer> _comOTermineiAceso(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await contarAteOFimDaParte(tester, harness);
  await waitFor(
    'o terminei acender',
    () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
    step: () => _passo(tester),
  );
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void _pilulaTelha(
  WidgetTester tester,
  String rotulo,
  Color telha, {
  required double veu,
}) {
  final botao = byLabel(rotulo);
  final fundo = find.descendant(
    of: botao,
    matching: find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    ),
  );
  final decoracao =
      tester.widget<Container>(fundo).decoration! as BoxDecoration;
  expect(
    decoracao.color,
    telha,
    reason: 'o terminei era um disco de madeira, não a pílula telha dela',
  );
  expect(decoracao.borderRadius, BorderRadius.circular(999));
  expect(decoracao.boxShadow, isNull, reason: 'a pílula dela não tem sombra');
  final pilula = tester.getRect(botao);
  final letra = tester.getRect(
    find.descendant(of: botao, matching: find.text(rotulo)),
  );
  expect(letra.left - pilula.left, closeTo(2.2 * _rem, 0.01));
  expect(pilula.right - letra.right, closeTo(2.2 * _rem, 0.01));
  expect(letra.top - pilula.top, closeTo(0.8 * _rem, 0.01));
  expect(pilula.bottom - letra.bottom, closeTo(0.8 * _rem, 0.01));
  final estilo = tester
      .widget<Text>(find.descendant(of: botao, matching: find.text(rotulo)))
      .style!;
  expect(estilo.fontSize, 1 * _rem);
  expect(estilo.fontWeight, FontWeight.w600);
  expect(_veu(tester, fundo), closeTo(veu, 0.001));
}

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  BackTranslationProgress contado, {
  SalaStage parouEm = SalaStage.retro,
  String lingua = testLanguage,
  bool juntada = false,
  bool inteira = false,
  bool comACena1 = false,
}) async {
  _telaAlta(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1205');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final partes = [
    if (inteira)
      KeptTake(
        scopeId: KeptScope.whole,
        path: (File(
          '${pasta.path}/inteira.m4a',
        )..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-inteira',
      )
    else
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
          origin: juntada ? 'ensaio-da-cena-$n' : null,
        ),
    if (comACena1)
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${pasta.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-1',
      ),
  ];
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: partes,
  );
  await holdTheSession(harness, row, language: lingua);
  harness.room.retroSoFar = contado;
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  await (parouEm == SalaStage.retro
      ? intoTheBackTranslation
      : intoTheRecordingHome)(
    container.read(salaSessionProvider.notifier),
    () => container.read(salaSessionProvider),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _subTell =
    'Toquem no círculo para pausar onde a frase acaba; toquem de novo para '
    'traduzir só o que aquela frase diz, e de novo para a gravação seguir.';

const _subVerdict =
    'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar uma '
    'parte; ou toquem em terminei para conferir de novo.';

Finder _cabecalho(String texto) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.header == true &&
      widget.properties.label == texto,
);

Future<ProviderContainer> _quatroFrasesConferidas(
  WidgetTester tester,
  SalaHarness harness,
  List<BtFinding> achados,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness);
  for (var parte = 1; parte <= 2; parte++) {
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    await waitFor(
      'a parte $parte ficar contada em duas frases',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          parte * 2,
      step: () => _passo(tester),
    );
  }
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 1
    ..verdictFindings = achados;
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar com os achados',
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

const _achadosDaDoisEDaQuatro = [
  BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
  BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
];

Future<void> _traduzirAFraseApontadaDeNovo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  traduzirOApontadoDeNovo(container);
  await _passo(tester);
  await tocar(tester, 'ouvindo a gravação de vocês…');
  await tocar(tester, 'Tocar ao terminar');
  await _passo(tester);
  await waitFor(
    'a frase traduzida de novo pousar',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

Future<void> _gravarDeNovoNaLinhaUm(WidgetTester tester) async {
  for (final controle in ['Gravar de novo', 'Parar']) {
    final daLinhaUm = find.descendant(
      of: linhaDoEnsaio(1),
      matching: byLabel(controle),
    );
    await tester.ensureVisible(daLinhaUm);
    await tester.tap(daLinhaUm);
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tocar(tester, 'Enviar a gravação');
}

Future<void> _aVozNoCanal(
  WidgetTester tester,
  ProviderContainer container,
  Channel channel,
) async {
  final sala = container.read(salaSessionProvider.notifier);
  sala.state = sala.state.copyWith(
    machine: sala.state.machine.copyWith(channel: channel),
  );
  await _passo(tester);
}

Future<ProviderContainer> _aParteUmRegravada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _quatroFrasesConferidas(tester, harness, const [
    BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
  ]);
  await tocar(tester, 'voltar e regravar uma parte');
  await waitFor(
    'a casa abrir',
    () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
    step: () => _passo(tester),
  );
  await _gravarDeNovoNaLinhaUm(tester);
  await waitFor(
    'a parte 1 regravada ficar no lugar',
    () => container
        .read(salaSessionProvider)
        .btTrechos
        .every((trecho) => trecho.parte != 0),
    step: () => _passo(tester),
  );
  await untilTheAdvanceDiscLights(
    container.read(salaSessionProvider.notifier),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  container.read(salaSessionProvider.notifier).startRetro();
  await waitFor(
    'a volta à tradução',
    () => container.read(salaSessionProvider).stage == SalaStage.retro,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _comUmaFraseRegravada(
  WidgetTester tester,
  SalaHarness harness, {
  int fresca = 2,
  List<BtFinding> achados = const [],
}) async {
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
    _umaParteRegravada(fresca: fresca, regravada: 1, achados: achados),
  );
  await waitFor(
    'a frase regravada achar a sua parte',
    () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

BackTranslationProgress _umaParteRegravada({
  required int fresca,
  required int? regravada,
  List<BtFinding> achados = const [],
}) => BackTranslationProgress(
  findings: achados,
  segments: [
    SegmentView(
      segmentId: 'trecho-3',
      takeId: 'gravacao-2',
      startsMs: 0,
      endsMs: 6000,
      frase: fresca,
    ),
  ],
  stale: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-velha-1',
      startsMs: 0,
      endsMs: 4000,
      frase: regravada,
    ),
  ],
);

Future<ProviderContainer> _relidaPelaSala(
  WidgetTester tester,
  SalaHarness harness, {
  required ({int fresca, int? regravada}) antes,
  required ({int fresca, int? regravada}) depois,
  List<BtFinding> achados = const [],
}) async {
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
    juntada: true,
    _umaParteRegravada(
      fresca: antes.fresca,
      regravada: antes.regravada,
      achados: achados,
    ),
  );
  await waitFor(
    'a frase regravada achar a sua parte',
    () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
    step: () => _passo(tester),
  );
  harness.room.retroSoFar = _umaParteRegravada(
    fresca: depois.fresca,
    regravada: depois.regravada,
  );
  final sala = container.read(salaSessionProvider.notifier);
  sala.goEnsaio();
  await tester.pump(const Duration(milliseconds: 300));
  sala.startRetro();
  await waitFor(
    'a sala reler as frases',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.single.frase ==
            depois.fresca &&
        container.read(salaSessionProvider).btTrechosRegravados.single.frase ==
            depois.regravada,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

BackTranslationProgress _frescasAposARegravada(
  List<(String, int)> frescas, {
  required int? regravada,
  List<BtFinding> achados = const [],
}) => BackTranslationProgress(
  findings: achados,
  segments: [
    for (final (onde, (nome, frase)) in frescas.indexed)
      SegmentView(
        segmentId: nome,
        takeId: 'gravacao-2',
        startsMs: onde * 3000,
        endsMs: (onde + 1) * 3000,
        frase: frase,
      ),
  ],
  stale: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-velha-1',
      startsMs: 0,
      endsMs: 4000,
      frase: regravada,
    ),
  ],
);

Future<ProviderContainer> _renumeradaPelaSala(
  WidgetTester tester,
  SalaHarness harness, {
  required BackTranslationProgress antes,
  required BackTranslationProgress depois,
}) async {
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
    juntada: true,
    antes,
  );
  await waitFor(
    'a frase regravada achar a sua parte',
    () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
    step: () => _passo(tester),
  );
  harness.room.retroSoFar = depois;
  final sala = container.read(salaSessionProvider.notifier);
  sala.goEnsaio();
  await tester.pump(const Duration(milliseconds: 300));
  sala.startRetro();
  await waitFor(
    'a sala renumerar as frases',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        listEquals(
          [
            for (final trecho in container.read(salaSessionProvider).btTrechos)
              (trecho.segmentId, trecho.frase),
          ],
          [
            for (final segment in depois.segments)
              (segment.segmentId, segment.frase),
          ],
        ),
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

List<Rect> _tracos(
  WidgetTester tester,
  Finder onde,
  Color cor, {
  Symbol como = #drawPath,
}) {
  final tracos = <Rect>[];
  expect(
    tester.renderObject(onde),
    paints..everything((metodo, argumentos) {
      if (metodo != como) return true;
      final tinta = (argumentos.last as Paint).color.toARGB32();
      if (tinta & 0xFFFFFF == cor.toARGB32() & 0xFFFFFF &&
          ((tinta >> 24) - (cor.toARGB32() >> 24)).abs() <= 1) {
        tracos.add(switch (argumentos[0]) {
          final Path path => path.getBounds(),
          final Rect rect => rect,
          _ => Rect.zero,
        });
      }
      return true;
    }),
  );
  return tracos;
}

Finder _oCartao(Finder dentro) => find.ancestor(
  of: dentro,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(16),
  ),
);

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

Future<ProviderContainer> _aFraseTresContada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  harness.room.fraseDaProximaFrase = 3;
  await tocarNoCirculo(tester);
  await waitFor(
    'a frase contada pousar',
    () => container
        .read(salaSessionProvider)
        .btTrechos
        .any((trecho) => trecho.contado),
    step: () => _passo(tester),
  );
  return container;
}

Future<void> _naTelaDeUmAparelho(
  WidgetTester tester, {
  required double largura,
  required double barra,
}) async {
  tester.view
    ..physicalSize = Size(largura, 844)
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: barra)
    ..viewPadding = FakeViewPadding(top: barra);
  addTearDown(tester.view.reset);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('four frases the room numbered are listed one to four, each '
      'under its parte, below her heading', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'a tela não tinha número nenhum: a voz dizia «na frase 3» e não '
          'havia nada para apontar',
    );
    closeTheRoom(container);
  });

  testWidgets('a passage recorded whole lists its frases by number alone, '
      'never under a parte the team did not make', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-inteira',
            startsMs: 4000,
            endsMs: 9000,
            frase: 2,
          ),
        ],
      ),
      inteira: true,
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', '2'],
      reason:
          'gravada a passagem de uma vez, cada frase dizia «parte 1», uma '
          'parte que a equipe nunca fez',
    );
    closeTheRoom(container);
  });

  testWidgets('a session picked back up lists the stale frases the room '
      'serves, on the part their recording answered for', (tester) async {
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
      const BackTranslationProgress(
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
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 2',
      ],
      reason:
          'reaberta a sessão, a sala servia a frase regravada e a lista não a '
          'mostrava',
    );
    expect(container.read(salaSessionProvider).btTrechos, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('a passage recorded whole and picked back up lists the stale '
      'frase of its old recording after the current one, under no parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-inteira-velha',
        scope: KeptScope.whole,
        kind: 'ensaio',
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira-velha',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      inteira: true,
    );
    await waitFor(
      'a frase regravada voltar',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', '2', 'regravada — traduzam de novo'],
      reason:
          'reaberta, a passagem gravada inteira perdia a frase regravada: a '
          'gravação velha não tinha número e a frase não achava lugar',
    );
    closeTheRoom(container);
  });

  testWidgets('a whole set aside behind scene 1 and picked back up lists its '
      'stale frase first, never under the parte that replaced it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-inteira-velha',
        scope: KeptScope.whole,
        kind: 'ensaio',
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira-velha',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      inteira: true,
      comACena1: true,
    );
    await waitFor(
      'a frase regravada voltar',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'regravada — traduzam de novo',
        '2',
        'parte 1',
      ],
      reason:
          'posto de lado o inteiro, a frase regravada dele sumia, e no índice '
          'da cena 1 diria «parte 1», uma parte em que nunca foi contada',
    );
    closeTheRoom(container);
  });

  testWidgets('a passage recorded whole and picked back up on the rehearsal '
      'marks its one row as re-recorded', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-inteira-velha',
        scope: KeptScope.whole,
        kind: 'ensaio',
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira-velha',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      parouEm: SalaStage.ensaio,
      inteira: true,
    );
    await waitFor(
      'a frase regravada voltar',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.descendant(
        of: byLabel('A passagem inteira'),
        matching: find.text('regravada — traduzam de novo'),
      ),
      findsOneWidget,
      reason:
          'reaberta no ensaio, a passagem gravada inteira não dizia que a '
          'tradução caducou',
    );
    closeTheRoom(container);
  });

  testWidgets('a session picked back up on the rehearsal still lists its '
      'stale frases when the team comes to the check', (tester) async {
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
      const BackTranslationProgress(
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
      parouEm: SalaStage.ensaio,
    );
    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a ida à tradução',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
      step: () => _passo(tester),
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 2',
      ],
      reason:
          'reaberta no ensaio, a sessão perdia as frases regravadas que a sala '
          'servia',
    );
    closeTheRoom(container);
  });

  testWidgets('a session picked back up on the rehearsal marks the scene whose '
      'frases the room serves as stale, and only that one', (tester) async {
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
      const BackTranslationProgress(
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
      parouEm: SalaStage.ensaio,
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    Finder naLinha(int n) => find.descendant(
      of: byLabel('Cena $n'),
      matching: find.text('regravada — traduzam de novo'),
    );
    expect(
      naLinha(1),
      findsOneWidget,
      reason: 'reaberta no ensaio, a casa não dizia que a cena foi regravada',
    );
    expect(naLinha(2), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('starting the translation over clears the stale frases too', (
    tester,
  ) async {
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
      const BackTranslationProgress(
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
      step: () => _passo(tester),
    );

    await tocar(tester, 'recomeçar a tradução');
    await tester.pump(const Duration(milliseconds: 700));
    await tocar(tester, 'toque de novo para apagar as 2 frases traduzidas');
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      isEmpty,
      reason:
          'recomeçada a tradução, as frases regravadas ficavam na lista de uma '
          'tradução que já não existia',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('with every part recorded again and only its stale frases '
      'listed, the team can still start the translation over', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.addAll(const [
      TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
      TakeView(
        takeId: 'gravacao-velha-2',
        scope: 'parte-2',
        kind: 'ensaio',
        ordinal: 2,
      ),
    ]);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-2',
            startsMs: 0,
            endsMs: 6000,
          ),
        ],
      ),
    );
    await waitFor(
      'as frases regravadas acharem as suas partes',
      () => container.read(salaSessionProvider).btTrechosRegravados.length == 2,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      byLabel('recomeçar a tradução'),
      findsOneWidget,
      reason:
          'com todas as partes regravadas a lista só tinha frases regravadas '
          'e não havia como recomeçar a tradução',
    );
    expect(find.text('recomeçar a tradução'), findsOneWidget);

    await tocar(tester, 'recomeçar a tradução');
    await tester.pump(const Duration(milliseconds: 700));
    await tocar(tester, 'toque de novo para apagar as 2 frases traduzidas');
    await waitFor(
      'a tradução recomeçar',
      () =>
          harness.room.restartsAsked.isNotEmpty &&
          container.read(salaSessionProvider).btTrechosRegravados.isEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.restartsAsked,
      hasLength(1),
      reason: 'o segundo toque não recomeçava uma tradução sem frase contada',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('armed, «start the translation over» counts the stale frases '
      'it discards with the told ones', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
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
      const BackTranslationProgress(
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
      lingua: 'en',
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );

    await tocar(tester, 'start the translation over');

    expect(
      find.text('tap again to discard the 2 translated sentences'),
      findsOneWidget,
      reason:
          'armado, o botão contava só as frases contadas e não as regravadas '
          'que o segundo toque também apaga',
    );
    expect(
      byLabel('tap again to discard the 2 translated sentences'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('armed on a joined recording, the restart counts the stale '
      'frases among the translations that leave the screen', (tester) async {
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
      const BackTranslationProgress(
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
      juntada: true,
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    expect(container.read(salaSessionProvider).joined, isTrue);

    await tocar(tester, 'recomeçar a tradução');

    expect(
      find.text(
        'toquem de novo: as 2 traduções saem da tela e vocês traduzem a '
        'passagem inteira de novo',
      ),
      findsOneWidget,
      reason:
          'numa gravação juntada o botão armado contava só as frases contadas',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('during the First listen «recomeçar a tradução» stays hidden, '
      'even with stale frases listed', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room
      ..listeningUnheardTakeIds = const ['gravacao-1', 'gravacao-2']
      ..takes.add(
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
      const BackTranslationProgress(
        segments: [],
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
      'a primeira escuta começar com a frase regravada na lista',
      () =>
          container.read(salaSessionProvider).btSoOuvir &&
          container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      byLabel('recomeçar a tradução'),
      findsNothing,
      reason: 'na primeira escuta não há tradução para recomeçar',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase just told is numbered at once by its place in the '
      'list, as hers, before the session is read again', (tester) async {
    _telaAlta(tester);
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
      step: () => _passo(tester),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', 'parte 1'],
      reason:
          'a frase recém-contada entrava sem número até a próxima leitura da '
          'sessão',
    );
    closeTheRoom(container);
  });

  testWidgets('a told stretch the room gave no number is still numbered by '
      'its place in the list, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      BackTranslationProgress(
        segments: [
          _quatroFrases[0],
          const SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-1',
            startsMs: 4000,
            endsMs: 9000,
          ),
          _quatroFrases[2],
        ],
      ),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', 'parte 1', '2', 'parte 1', '3', 'parte 2'],
      reason:
          'uma frase que a sala ainda não numerara ficava sem número, e a '
          'dela numera toda frase pelo lugar na lista',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'of it, named by its place in the list', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.fraseDaProximaFrase = 3;
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );
    final contada = harness.room.chunkFiles.last;
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 1');

    expect(
      harness.playback.played.last,
      contada,
      reason: 'a lista não tinha como ouvir a tradução de uma frase',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'while the verdict is on the screen, as it does before one', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    final terceira = harness.room.chunkFiles[2];
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      terceira,
      reason:
          'depois do veredito o alto-falante da linha ficava apagado, e a '
          'equipe não ouvia o que contou justo quando queria',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'on a conferida passage too', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const [];
    await _traduzirAFraseApontadaDeNovo(tester, container);
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    final terceira = harness.room.chunkFiles[2];
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      terceira,
      reason:
          'na passagem conferida o alto-falante da linha ficava apagado, e a '
          'equipe não ouvia o que contou',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase is dimmed while the microphone is '
      'open for the next one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, fimDaGravacao);
    await tocar(tester, fimDaGravacao);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      aceso(tester, 'ouvir a minha tradução da frase 1'),
      isFalse,
      reason:
          'o alto-falante seguia aceso com o microfone aberto, e o toque '
          'não fazia nada',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase is dimmed while the check runs', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.room.fraseDaProximaFrase = 4;
    await contarAteOFimDaParte(tester, harness);
    harness.room.holdNextVerdict();
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência começar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 1'),
      isFalse,
      reason:
          'o alto-falante seguia aceso enquanto a sala conferia, e o toque '
          'não fazia nada',
    );
    harness.room.finishHeldVerdict();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase stays lit when the check falls on '
      'the network', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.room.fraseDaProximaFrase = 4;
    await contarAteOFimDaParte(tester, harness);
    harness.room.reachable = false;
    var conferiu = false;
    harness.room
      ..failFinishWith = const NetworkFailed('timeout')
      ..duranteOVeredito = () => conferiu = true;
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência cair na rede',
      () => conferiu,
      step: () => _passo(tester),
    );
    for (var passo = 0; passo < 5; passo++) {
      await _passo(tester);
    }

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 1'),
      isTrue,
      reason: 'uma rede que cai fora de uma entrada não muda nada',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the loudspeaker of a frase still plays after a halt raised there, as hers',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _aFraseTresContada(tester, harness);
      harness.room.fraseDaProximaFrase = 4;
      await contarAteOFimDaParte(tester, harness);
      container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      await _passo(tester);
      expect(container.read(salaSessionProvider).needsPerson, isFalse);

      final antes = harness.playback.played.length;

      container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
      await _passo(tester);

      expect(container.read(salaSessionProvider).canHearAFrase, isTrue);
      expect(
        harness.playback.played.length,
        greaterThan(antes),
        reason: 'a parada calava o alto-falante da linha, e o dela toca',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the check screen is headed with her words, «Traduzir a '
      'gravação», not left without a title', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      find.descendant(
        of: _cabecalho('Traduzir a gravação'),
        matching: find.text('Traduzir a gravação'),
      ),
      findsOneWidget,
      reason: 'a tela da tradução não dizia o que era',
    );
    closeTheRoom(container);
  });

  testWidgets('the sub-line tells the team to pause and translate before a '
      'verdict, and to tap a frase or terminei after one', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    expect(
      find.text(_subTell),
      findsOneWidget,
      reason: 'nada na tela dizia à equipe o que fazer',
    );

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictFindingPlace = 0;
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'o veredito chegar com um achado',
      () =>
          container.read(salaSessionProvider).btPhase == BtPhase.playing &&
          container.read(salaSessionProvider).btVeredito,
      step: () => _passo(tester),
    );

    expect(
      find.text(_subVerdict),
      findsOneWidget,
      reason: 'depois do veredito a linha seguia dizendo para pausar',
    );
    expect(find.text(_subTell), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('on a phone as narrow as the iPhone SE the line before a '
      'verdict keeps the margin the frase rows keep, not the screen edge', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );
    tester.view.physicalSize = const Size(375, 2400);
    await _passo(tester);

    final linha = tester.getRect(find.text(_subTell));
    expect(
      linha.left,
      16,
      reason: 'a linha antes do veredito encostava na borda esquerda',
    );
    expect(
      linha.right,
      375 - 16,
      reason: 'a linha antes do veredito encostava na borda direita',
    );
    closeTheRoom(container);
  });

  testWidgets('every frase the check named carries its word, and a frase it '
      'did not name carries none', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
      BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'só o achado que liderava marcava alguma coisa, e os outros não '
          'apareciam como pista',
    );
    closeTheRoom(container);
  });

  testWidgets('a missing element is marked on the frase the check named, '
      'never on the stretch after it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.missing, frase: 3, segmentId: 'trecho-4'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        'faltou depois desta',
        '4',
        'parte 2',
      ],
      reason:
          'a falta depois da frase 3 aponta o trecho da frase 4; marcada pelo '
          'trecho, a palavra cairia na frase errada',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase two findings name carries the word of the first, not '
      'the second', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.unclear, frase: 2, segmentId: 'trecho-2'),
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'não ficou claro',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'uma frase leva uma palavra só, a do primeiro achado que a nomeia',
    );
    closeTheRoom(container);
  });

  testWidgets('a finding of a kind this tablet does not know marks nothing, '
      'and the others are still marked', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: null, frase: 1, segmentId: 'trecho-1'),
      BtFinding(kind: BtFindingKind.addition, frase: 3, segmentId: 'trecho-3'),
    ]);

    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 2',
      'acrescentado',
      '4',
      'parte 2',
    ], reason: 'uma nuance não leva palavra nenhuma');
    closeTheRoom(container);
  });

  testWidgets('a frase translated again loses its mark at once, and the '
      'other frases keep theirs', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room.failFinishWith = const NetworkFailed('timeout');

    await _traduzirAFraseApontadaDeNovo(tester, container);

    expect(harness.room.replacesAsked, hasLength(1));
    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'a frase traduzida de novo seguia marcada como se o achado ainda '
          'valesse',
    );
    closeTheRoom(container);
  });

  testWidgets('a check that comes back clean takes every mark away', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const [];

    await _traduzirAFraseApontadaDeNovo(tester, container);
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );

    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 2',
      '4',
      'parte 2',
    ], reason: 'a última conferência não nomeou frase nenhuma');
    closeTheRoom(container);
  });

  testWidgets('a part recorded again and kept loses the marks on its frases, '
      'and the other part keeps its own', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );

    await tocar(tester, 'voltar e regravar uma parte');
    await waitFor(
      'a casa abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );
    await _gravarDeNovoNaLinhaUm(tester);
    await waitFor(
      'a parte 1 regravada ficar no lugar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .every((trecho) => trecho.parte != 0),
      step: () => _passo(tester),
    );

    expect(
      [
        for (final achado in container.read(salaSessionProvider).btFindings)
          achado.frase,
      ],
      [4],
      reason:
          'a marca da frase 2 ficava de pé e caía na frase 2 nova, que o '
          'veredito nunca ouviu',
    );
    closeTheRoom(container);
  });

  testWidgets('a part recorded again keeps its frases listed in its place, '
      'marked «regravada — traduzam de novo», with their numbers and out of '
      'the check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 1',
        'regravada — traduzam de novo',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'as frases da parte gravada de novo sumiam da lista, e a equipe '
          'perdia de vista o que tinha traduzido dela',
    );
    expect(
      {
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          trecho.parte,
      },
      {1},
      reason: 'uma frase regravada fica fora da conferência',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» card lines up with the other frase cards, on '
      'the iPhone SE as on the iPad', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);

    for (final largura in [820.0, 375.0]) {
      tester.view.physicalSize = Size(largura, 2400);
      await _passo(tester);
      final regravada = tester.getRect(
        _oCartao(find.text('regravada — traduzam de novo')).first,
      );
      final fresca = tester.getRect(_oCartao(find.text('3')).first);
      expect(
        [regravada.left, regravada.width],
        [fresca.left, fresca.width],
        reason:
            'o cartão regravado ficava uns 50 px à direita no iPad e na '
            'largura toda no SE',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a «regravada» frase plays the translation '
      'the team told of it before the part was recorded again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);
    final primeira = harness.room.chunkFiles.first;
    harness.playback.finishPlayback();
    await _passo(tester);

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 1'),
      isTrue,
      reason: 'a frase regravada não tinha alto-falante',
    );
    await tocar(tester, 'ouvir a minha tradução da frase 1');

    expect(
      harness.playback.played.last,
      primeira,
      reason: 'a tradução de antes da frase regravada não se ouvia mais',
    );
    closeTheRoom(container);
  });

  testWidgets('while the voice speaks, the loudspeaker of a «regravada» frase '
      'takes no tap either, and is live again when the voice stops', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);
    harness.playback.finishPlayback();
    await _passo(tester);
    const regravada = 'ouvir a minha tradução da frase 1';
    expect(container.read(salaSessionProvider).btTrechosRegravados, isNotEmpty);
    expect(aceso(tester, regravada), isTrue);

    await _aVozNoCanal(
      tester,
      container,
      const GuideSpeaking(Line(LineKind.guide, 1)),
    );

    expect(
      aceso(tester, regravada),
      isFalse,
      reason: 'a frase regravada seguia aceitando toque com a voz falando',
    );

    await _aVozNoCanal(tester, container, const Silence());

    expect(aceso(tester, regravada), isTrue);
    closeTheRoom(container);
  });

  testWidgets('while the voice speaks, the bar of a «regravada» frase takes no '
      'tap either, and is live again when the voice stops', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _comUmaFraseRegravada(tester, harness);
    harness.playback.finishPlayback();
    await _passo(tester);
    const barra = 'Ouvir esta frase de novo e traduzir de novo — 1';
    bool viva() =>
        tester.widget<Semantics>(byLabel(barra)).properties.enabled ?? false;
    expect(container.read(salaSessionProvider).btTrechosRegravados, isNotEmpty);
    expect(viva(), isTrue);

    await _aVozNoCanal(
      tester,
      container,
      const GuideSpeaking(Line(LineKind.guide, 1)),
    );

    expect(
      viva(),
      isFalse,
      reason:
          'a barra da frase regravada seguia aceitando toque com a voz '
          'falando',
    );

    await _aVozNoCanal(tester, container, const Silence());

    expect(viva(), isTrue);
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase is told again over the part as it stands '
      'now, at the place it had', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _comUmaFraseRegravada(tester, harness);
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
    expect(
      [harness.playback.played.last, harness.playback.ranges.lastOrNull],
      [container.read(salaSessionProvider).partes.first.path, '0-4000'],
      reason: 'a barra da frase regravada não tocava nada',
    );
    await tocar(tester, 'ouvindo a gravação de vocês…');
    await tocar(tester, 'Tocar ao terminar');
    await waitFor(
      'a frase regravada traduzida de novo subir',
      () => harness.room.replacesAsked.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-1@gravacao-1:0-4000'],
      reason:
          'a frase regravada não se traduzia de novo, e a equipe só podia '
          'recomeçar a tradução inteira',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase told again leaves the stale list and is '
      'listed once, with the telling just recorded', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.segments.add(
      const SegmentView(
        segmentId: 'trecho-3',
        takeId: 'gravacao-2',
        startsMs: 0,
        endsMs: 6000,
        frase: 2,
      ),
    );
    final container = await _comUmaFraseRegravada(tester, harness);
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
    await tocar(tester, 'ouvindo a gravação de vocês…');
    await tocar(tester, 'Tocar ao terminar');
    await waitFor(
      'a frase regravada traduzida de novo pousar',
      () => harness.room.replacesAsked.isNotEmpty,
      step: () => _passo(tester),
    );
    await waitFor(
      'a resposta da sala chegar à lista',
      () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      isNot(contains('regravada — traduzam de novo')),
      reason:
          'traduzida de novo, a frase seguia marcada como regravada ao lado '
          'da nova',
    );
    expect(
      [
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          if (trecho.takeId == 'gravacao-1')
            '${trecho.lugarFrom.inMilliseconds}-'
                '${trecho.lugarTo.inMilliseconds}:${trecho.retroPath}',
      ],
      ['0-4000:${harness.room.replacesComArquivo.single}'],
      reason:
          'a frase traduzida de novo voltava sem a tradução que a equipe '
          'acabou de gravar',
    );
    closeTheRoom(container);
  });

  testWidgets('after the room reads the frases back, every row is numbered by '
      'its place as hers, and the «regravada» one keeps its loudspeaker and '
      'its retell', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _relidaPelaSala(
      tester,
      harness,
      antes: (fresca: 2, regravada: 1),
      depois: (fresca: 1, regravada: null),
    );
    harness.playback.finishPlayback();
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 2',
      ],
      reason:
          'relidas as frases, a regravada ficava com o 1 de antes ao lado da '
          'frase 1 da sala, ou sem número nenhum',
    );
    expect(
      [
        for (final rotulo in [
          'ouvir a minha tradução da frase 1',
          'Ouvir esta frase de novo e traduzir de novo — 1',
          'ouvir a minha tradução da frase 2',
          'Ouvir esta frase de novo e traduzir de novo — 2',
        ])
          byLabel(rotulo).evaluate().length,
      ],
      [1, 1, 1, 1],
      reason:
          'sem número, a frase regravada perdia o alto-falante e a barra de '
          'traduzir de novo',
    );
    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
    expect(
      find.textContaining('traduzindo de novo a frase 1 —'),
      findsOneWidget,
      reason:
          'a linha de traduzir de novo não dizia o número que a tela mostra',
    );
    closeTheRoom(container);
  });

  testWidgets('a finding stays on the frase the room named after a read, not '
      'on the row the screen now numbers with that number', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _relidaPelaSala(
      tester,
      harness,
      antes: (fresca: 1, regravada: 3),
      depois: (fresca: 1, regravada: null),
      achados: const [
        BtFinding(kind: BtFindingKind.unclear, frase: 1, segmentId: 'trecho-3'),
      ],
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'o achado da frase 1 da sala caía na linha que a tela numera 1, a '
          'regravada, e não na frase que a sala ouviu',
    );
    closeTheRoom(container);
  });

  testWidgets('after the room renumbers frases 2 and 3 as 1 and 2, each '
      'finding stays on its own frase, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _renumeradaPelaSala(
      tester,
      harness,
      antes: _frescasAposARegravada(
        [('trecho-3', 2), ('trecho-4', 3)],
        regravada: 1,
        achados: const [
          BtFinding(
            kind: BtFindingKind.addition,
            frase: 2,
            segmentId: 'trecho-3',
          ),
          BtFinding(
            kind: BtFindingKind.unclear,
            frase: 3,
            segmentId: 'trecho-4',
          ),
        ],
      ),
      depois: _frescasAposARegravada([
        ('trecho-3', 1),
        ('trecho-4', 2),
      ], regravada: null),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 2',
        'acrescentado',
        '3',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'renumeradas as frases, os achados ficavam com os números velhos: o '
          'da frase 2 caía na frase seguinte e o da frase 3 sumia',
    );
    closeTheRoom(container);
  });

  testWidgets('after the room renumbers the frases, the nuance the verdict '
      'named keeps its colour on its own frase, not on none', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _renumeradaPelaSala(
      tester,
      harness,
      antes: _frescasAposARegravada(
        [('trecho-3', 2), ('trecho-4', 3)],
        regravada: 1,
        achados: const [
          BtFinding(
            kind: BtFindingKind.nuance,
            frase: 3,
            segmentId: 'trecho-4',
          ),
        ],
      ),
      depois: _frescasAposARegravada([
        ('trecho-3', 1),
        ('trecho-4', 2),
      ], regravada: null),
    );
    Color borda(int n) =>
        ((tester
                            .widget<Container>(
                              _oCartao(
                                find.descendant(
                                  of: find.byType(FraseList),
                                  matching: find.text('$n'),
                                ),
                              ).first,
                            )
                            .decoration
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;

    expect(
      borda(3),
      ShemaBrand.azul,
      reason:
          'renumeradas as frases, a nuance ficava no número velho e nenhuma '
          'frase levava a cor dela',
    );
    expect(borda(2), isNot(ShemaBrand.azul));
    closeTheRoom(container);
  });

  testWidgets(
    'a finding on a stretch the room no longer counts marks no frase, '
    'never the one that took its number',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _renumeradaPelaSala(
        tester,
        harness,
        antes: _frescasAposARegravada(
          [('trecho-3', 2), ('trecho-4', 3)],
          regravada: 1,
          achados: const [
            BtFinding(
              kind: BtFindingKind.unclear,
              frase: 3,
              segmentId: 'trecho-4',
            ),
          ],
        ),
        depois: _frescasAposARegravada([
          ('trecho-3', 2),
          ('trecho-5', 3),
        ], regravada: 1),
      );

      expect(
        _naLista(tester),
        [
          'FRASES TRADUZIDAS',
          '1',
          'parte 1',
          'regravada — traduzam de novo',
          '2',
          'parte 2',
          '3',
          'parte 2',
        ],
        reason:
            'o achado de um trecho que a sala já não conta caía na frase que '
            'ficou com o número dele, uma frase que a conferência nunca ouviu',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a «regravada» frase is not offered to be told again where a '
      'frase of the new recording already stands, only beside one', (
    tester,
  ) async {
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
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-5',
            takeId: 'gravacao-1',
            startsMs: 3000,
            endsMs: 7000,
            frase: 3,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-1',
            startsMs: 7000,
            endsMs: 9000,
            frase: 2,
          ),
        ],
      ),
    );
    await waitFor(
      'as frases regravadas acharem a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.length == 2,
      step: () => _passo(tester),
    );
    harness.playback.finishPlayback();
    await _passo(tester);

    expect(
      [
        for (final n in [2, 3])
          tester
              .widget<Semantics>(
                byLabel('Ouvir esta frase de novo e traduzir de novo — $n'),
              )
              .properties
              .enabled,
      ],
      [false, true],
      reason:
          'a barra oferecia traduzir de novo onde a sala recusa, e a equipe '
          'ficava com uma falha sem palavra',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase past the end of a part recorded again '
      'shorter is still offered and told again at its place, as hers', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback.measured = const Duration(seconds: 5);
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
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 4000,
            frase: 2,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 7000,
            endsMs: 9000,
            frase: 1,
          ),
        ],
      ),
    );
    await waitFor(
      'a frase regravada achar a sua parte e a parte 1 ser medida',
      () =>
          container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty &&
          container.read(salaSessionProvider).btFimDasPartesMs.isNotEmpty,
      step: () => _passo(tester),
    );
    expect(container.read(salaSessionProvider).btFimDasPartesMs.first, 5000);
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
    await tocar(tester, 'ouvindo a gravação de vocês…');
    await tocar(tester, 'Tocar ao terminar');
    await waitFor(
      'a frase regravada traduzida de novo subir',
      () => harness.room.replacesAsked.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-1@gravacao-1:7000-9000'],
      reason:
          'a dela oferece a barra de toda frase regravada e manda o mesmo '
          'lugar; a nossa não pode calar uma frase que a dela deixa traduzir',
    );
    closeTheRoom(container);
  });

  testWidgets('a team that comes back to the check sees the marks its last '
      'check left', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: _quatroFrases,
        findings: _achadosDaDoisEDaQuatro,
      ),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason: 'a equipe que voltava perdia as marcas da última conferência',
    );
    closeTheRoom(container);
  });

  testWidgets('a team that comes back to the rehearsal finds the marks again '
      'when it reaches the check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: _quatroFrases,
        findings: _achadosDaDoisEDaQuatro,
      ),
      parouEm: SalaStage.ensaio,
    );

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a tradução abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason: 'voltando pelo ensaio, as marcas da última conferência sumiam',
    );
    closeTheRoom(container);
  });

  testWidgets('while a mark still stands the sub-line stays the verdict\'s, '
      'even with the recording playing again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room.failFinishWith = const NetworkFailed('timeout');

    await _traduzirAFraseApontadaDeNovo(tester, container);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(
      find.text(_subVerdict),
      findsOneWidget,
      reason:
          'com a frase 4 ainda marcada a linha voltava a mandar pausar, como '
          'se não houvesse veredito',
    );
    closeTheRoom(container);
  });

  testWidgets('a screen reader on the done button reads «terminei», and the '
      'button shows it, never «Conferir a tradução»', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    expect(
      find.descendant(of: byLabel('terminei'), matching: find.text('terminei')),
      findsOneWidget,
      reason: 'o botão de terminar era um disco mudo chamado de outra coisa',
    );
    expect(byLabel('Conferir a tradução'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while the check runs the done button reads «conferindo…», and '
      'a frase being sent never makes it say so', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.holdNextChunk();
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase seguir para a sala',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      byLabel('conferindo…'),
      findsNothing,
      reason: 'mandar uma frase não é conferir',
    );
    expect(byLabel('terminei'), findsOneWidget);

    harness.room.finishHeldChunk();
    await waitFor(
      'a frase pousar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
      step: () => _passo(tester),
    );
    await contarAteOFimDaParte(tester, harness);
    harness.room.holdNextVerdict();
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência começar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      find.descendant(
        of: byLabel('conferindo…'),
        matching: find.text('conferindo…'),
      ),
      findsOneWidget,
      reason: 'a equipe apertava terminei e nada na tela dizia que conferia',
    );
    harness.room.finishHeldVerdict();
    await _passo(tester);
    closeTheRoom(container);
  });

  for (final (look, ink) in [
    (Brightness.light, const Color(0xFF0A0703)),
    (Brightness.dark, const Color(0xFFF2EDE1)),
  ]) {
    testWidgets(
      'in the ${look.name} look a dimmed «terminei» is written in ink at full '
      'strength, not in white fading with its pill',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _telaAlta(tester);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        await tester.pump(const Duration(seconds: 1));

        expect(aceso(tester, 'terminei'), isFalse);
        final rotulo = find.descendant(
          of: byLabel('terminei'),
          matching: find.text('terminei'),
        );
        expect(
          piorContraste(tester, 'terminei'),
          greaterThanOrEqualTo(4.5),
          reason: 'o rótulo apagado ficava abaixo de 4,5:1 no disco apagado',
        );
        expect(
          tester.widget<Text>(rotulo).style!.color,
          ink,
          reason: 'o terminei apagado escrevia branco num disco claro',
        );
        expect(
          find.ancestor(
            of: rotulo,
            matching: find.descendant(
              of: find.byType(RetroView),
              matching: _apagando,
            ),
          ),
          findsNothing,
          reason: 'a tinta esmaecia junto com o disco, a 35%',
        );
        closeTheRoom(container);
      },
    );
    testWidgets(
      'in the ${look.name} look «conferindo…» on the dimmed pill is written in '
      'ink at full strength, as the dimmed «terminei», not in white',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _telaAlta(tester);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        harness.playback.at = cabeca;
        await tocarNoCirculo(tester);
        await tocarNoCirculo(tester);
        await tocarNoCirculo(tester);
        await contarAteOFimDaParte(tester, harness);
        harness.room.holdNextVerdict();
        await tocar(tester, 'terminei');
        await waitFor(
          'a conferência começar',
          () => container.read(salaSessionProvider).btConferindo,
          step: () => _passo(tester),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(aceso(tester, 'conferindo…'), isFalse);
        final rotulo = find.descendant(
          of: byLabel('conferindo…'),
          matching: find.text('conferindo…'),
        );
        expect(
          piorContraste(tester, 'conferindo…'),
          greaterThanOrEqualTo(4.5),
          reason: 'o conferindo… ficava abaixo de 4,5:1 no disco apagado',
        );
        expect(
          tester.widget<Text>(rotulo).style!.color,
          ink,
          reason: 'o conferindo… escrevia branco no disco apagado',
        );
        expect(
          find.ancestor(
            of: rotulo,
            matching: find.descendant(
              of: find.byType(RetroView),
              matching: _apagando,
            ),
          ),
          findsNothing,
        );
        harness.room.finishHeldVerdict();
        await _passo(tester);
        closeTheRoom(container);
      },
    );
  }

  for (final (look, telha, papel) in [
    (Brightness.light, const Color(0xFFBE4A01), const Color(0xFFF6F5EB)),
    (Brightness.dark, const Color(0xFFD6612A), const Color(0xFF1A150E)),
  ]) {
    testWidgets(
      'in the ${look.name} look a lit «terminei» writes the paper on her telha '
      'at 4.6:1 or better, not white on a light disc',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _telaAlta(tester);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _comOTermineiAceso(tester, harness);

        expect(aceso(tester, 'terminei'), isTrue);
        expect(
          piorContraste(tester, 'terminei'),
          greaterThanOrEqualTo(4.6),
          reason:
              'o terminei aceso escrevia branco no disco de madeira, a 1,58:1',
        );
        final rotulo = find.descendant(
          of: byLabel('terminei'),
          matching: find.text('terminei'),
        );
        expect(tester.widget<Text>(rotulo).style!.color, papel);
        expect(
          find.ancestor(
            of: rotulo,
            matching: find.descendant(
              of: find.byType(RetroView),
              matching: _apagando,
            ),
          ),
          findsNothing,
        );
        closeTheRoom(container);
      },
    );
    testWidgets(
      'in the ${look.name} look a dimmed «terminei» is her telha pill faded to '
      'a third, not a wood disc',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _telaAlta(tester);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        await tester.pump(const Duration(seconds: 1));

        expect(aceso(tester, 'terminei'), isFalse);
        _pilulaTelha(tester, 'terminei', telha, veu: 0.35);
        closeTheRoom(container);
      },
    );
    testWidgets(
      'in the ${look.name} look a lit «terminei» is her telha pill at full '
      'strength, still and without a halo, not a beckoning wood disc',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _telaAlta(tester);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _comOTermineiAceso(tester, harness);

        expect(aceso(tester, 'terminei'), isTrue);
        for (var quadro = 0; quadro < 4; quadro++) {
          _pilulaTelha(tester, 'terminei', telha, veu: 1);
          await tester.pump(const Duration(milliseconds: 600));
        }
        closeTheRoom(container);
      },
    );
  }

  testWidgets('a check that cannot run says so in her words, and «terminei» '
      'is there again to try once more', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room.failFinishWith = const NetworkFailed('HTTP 502');

    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência cair',
      () =>
          container.read(salaSessionProvider).btRecusa ==
          CheckRefusal.checkUnavailable,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
      reason:
          'a conferência que não rodou não dizia nada na tela além do sem '
          'conexão',
    );
    expect(
      byLabel('terminei'),
      findsOneWidget,
      reason: 'terminei é o jeito de tentar de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told with nothing understood shows her line on the '
      'screen, not only to a screen reader', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.failChunkWith = const Refused(RefusalCode.wordlessTelling);
    await tocarNoCirculo(tester);
    await waitFor(
      'a sala não entender a frase',
      () => container.read(salaSessionProvider).wordlessTelling,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('não entendi — traduzam de novo esse pedaço'),
      findsOneWidget,
      reason: 'a frase sem palavras não dizia nada na tela',
    );
    closeTheRoom(container);
  });

  testWidgets('a clean check writes no «✓ traduzida e conferida» on the check '
      'screen, only the circle names it', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);

    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('✓ traduzida e conferida'),
      findsNothing,
      reason:
          'a tela da checagem escrevia a linha que a dela só escreve na casa',
    );
    expect(
      tester
          .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
          .semanticLabel,
      'traduzida e conferida',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'after a verdict the way back is «voltar e regravar uma parte», never '
    '«achado»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrasesConferidas(
        tester,
        harness,
        _achadosDaDoisEDaQuatro,
      );

      expect(
        byLabel('voltar e regravar uma parte'),
        findsOneWidget,
        reason: '«achado» é palavra da mecânica, não dela',
      );
      expect(byLabel('Gravar a parte de novo na língua materna'), findsNothing);
      closeTheRoom(container);
    },
  );

  for (final (largura, barra) in [(390.0, 59.0), (768.0, 0.0)]) {
    testWidgets(
      'the check screen starts below the status bar and scrolls from there, '
      'not from under it, on a ${largura.toInt()} px screen',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _voltaATraducao(
          tester,
          harness,
          const BackTranslationProgress(segments: _quatroFrases),
        );
        await _naTelaDeUmAparelho(tester, largura: largura, barra: barra);

        final tela = find.byType(RetroView);
        expect(
          tester
              .getTopLeft(
                find.descendant(of: tela, matching: find.byType(Scrollable)),
              )
              .dy,
          greaterThanOrEqualTo(barra),
          reason:
              'a lista rolava por baixo do relógio: a linha de pausa passava '
              'sobre o sinal e a hora',
        );
        expect(
          tester.getTopLeft(_cabecalho('Traduzir a gravação')).dy,
          greaterThanOrEqualTo(barra),
          reason: 'o título ficava debaixo da barra de estado',
        );
        closeTheRoom(container);
      },
    );
  }

  for (final (largura, barra) in [(390.0, 59.0), (768.0, 0.0)]) {
    testWidgets(
      'the corner button covers no line of the check screen, at rest or '
      'scrolled, on a ${largura.toInt()} px screen',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _voltaATraducao(
          tester,
          harness,
          const BackTranslationProgress(segments: _quatroFrases),
        );
        await _naTelaDeUmAparelho(tester, largura: largura, barra: barra);

        final tela = find.byType(RetroView);
        final rolagem = find.descendant(
          of: tela,
          matching: find.byType(Scrollable),
        );
        final posicao = tester.state<ScrollableState>(rolagem).position;
        final janela = tester.getRect(rolagem);
        final botao = byLabel('Voltar para a gravação');
        expect(botao, findsOneWidget);
        expect(posicao.maxScrollExtent, greaterThan(0));

        for (final onde in [
          0.0,
          posicao.maxScrollExtent / 2,
          posicao.maxScrollExtent,
        ]) {
          posicao.jumpTo(onde);
          await _passo(tester);
          final area = tester.getRect(botao);
          final cobertas = [
            for (final texto in tester.widgetList<Text>(
              find.descendant(of: tela, matching: find.byType(Text)),
            ))
              if (tester
                      .getRect(find.byWidget(texto))
                      .intersect(janela)
                      .overlaps(area) &&
                  tester.getRect(find.byWidget(texto)).overlaps(area))
                texto.data,
          ];
          expect(
            cobertas,
            isEmpty,
            reason:
                'o botão do canto ficava parado sobre a tela que rolava e '
                'cobria a linha que passasse por baixo, rolado em $onde',
          );
        }
        closeTheRoom(container);
      },
    );
  }

  for (final (look, areia) in [
    (Brightness.light, const Color(0xFFC5C29F)),
    (Brightness.dark, const Color(0xFF6E6A57)),
  ]) {
    testWidgets('in the ${look.name} look a «regravada» card is edged in '
        'dashed sand, not a solid terracotta line', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = look;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _comUmaFraseRegravada(tester, harness);
      final cartao = _oCartao(find.text('regravada — traduzam de novo')).first;

      expect(
        (tester.widget<Container>(cartao).decoration as BoxDecoration).border,
        isNull,
        reason: 'o cartão regravado tinha a borda cheia em telha',
      );
      expect(
        (tester.widget<Container>(cartao).foregroundDecoration as DashedEdge?)
            ?.color,
        areia,
        reason: 'a borda tracejada dela é de areia',
      );
      final emCima =
          _tracos(
              tester,
              cartao,
              areia,
            ).where((traco) => traco.bottom < 1).toList()
            ..sort((um, outro) => um.left.compareTo(outro.left));
      expect(emCima.length, greaterThan(1));
      expect(
        emCima[1].left - emCima[0].right,
        greaterThanOrEqualTo(2),
        reason: 'a borda era uma linha só, não tracejada',
      );
      closeTheRoom(container);
    });
  }

  for (final (look, areia, verdeClaro) in [
    (Brightness.light, const Color(0xFFC5C29F), const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFF6E6A57), const Color(0xFFAAB07E)),
  ]) {
    testWidgets('in the ${look.name} look a «regravada» frase numbers itself '
        'in a hollow dashed ring, not on a filled disc', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = look;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _comUmaFraseRegravada(tester, harness);
      final cartao = _oCartao(find.text('regravada — traduzam de novo')).first;
      final numero = find.descendant(of: cartao, matching: find.text('1'));
      final disco = tester.widget<DecoratedBox>(
        find.ancestor(of: numero, matching: find.byType(DecoratedBox)).first,
      );

      expect(
        disco.decoration,
        isA<DashedEdge>().having((anel) => anel.color, 'color', areia),
        reason: 'o disco regravado era cheio, não o anel tracejado de areia',
      );
      expect(
        tester.widget<Text>(numero).style?.color,
        verdeClaro,
        reason: 'no anel vazio o número dela é verde-claro',
      );
      closeTheRoom(container);
    });
  }

  for (final (look, areia) in [
    (Brightness.light, const Color(0xFFC5C29F)),
    (Brightness.dark, const Color(0xFF6E6A57)),
  ]) {
    testWidgets('in the ${look.name} look a «regravada» bar is striped in '
        'sand, not filled terracotta', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = look;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _comUmaFraseRegravada(tester, harness);
      final barra = find
          .descendant(
            of: _oCartao(find.text('regravada — traduzam de novo')).first,
            matching: find.byType(FractionallySizedBox),
          )
          .first;

      expect(
        _tracos(
          tester,
          barra,
          areia.withValues(alpha: .9),
          como: #drawRect,
        ).take(2),
        [const Rect.fromLTWH(0, 0, 3, 10), const Rect.fromLTWH(6, 0, 3, 10)],
        reason: 'a barra regravada enchia de telha, não das listras de areia',
      );
      closeTheRoom(container);
    });
  }

  for (final (look, telha) in [
    (Brightness.light, const Color(0xFFBE4A01)),
    (Brightness.dark, const Color(0xFFD6612A)),
  ]) {
    testWidgets('in the ${look.name} look «regravada — traduzam de novo» is '
        'written in terracotta, not boxed in a terracotta pill', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = look;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _comUmaFraseRegravada(tester, harness);
      final palavra = find.text('regravada — traduzam de novo');

      expect(tester.widget<Text>(palavra).style?.color, telha);
      expect(
        (tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: palavra,
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?)
            ?.borderRadius,
        BorderRadius.circular(16),
        reason: 'a palavra regravada vinha numa pílula com borda telha',
      );
      closeTheRoom(container);
    });
  }

  for (final (look, azul, telha) in [
    (Brightness.light, const Color(0xFF89AAA3), const Color(0xFFBE4A01)),
    (Brightness.dark, const Color(0xFF8FB1A9), const Color(0xFFD6612A)),
  ]) {
    for (final (kind, cor) in [
      (BtFindingKind.unclear, azul),
      (BtFindingKind.addition, telha),
    ]) {
      testWidgets('in the ${look.name} look a «regravada» frase the last '
          'check found ${kind.name} keeps its finding colour, dashed', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _comUmaFraseRegravada(
          tester,
          harness,
          achados: [BtFinding(kind: kind, frase: 1, segmentId: 'trecho-1')],
        );
        final palavra = find.text('regravada — traduzam de novo');
        final cartao = _oCartao(palavra).first;
        final barra = find
            .descendant(
              of: find
                  .descendant(
                    of: cartao,
                    matching: find.byType(FractionallySizedBox),
                  )
                  .first,
              matching: find.byType(Container),
            )
            .first;

        expect(
          (tester.widget<Container>(cartao).foregroundDecoration as DashedEdge?)
              ?.color,
          cor,
          reason:
              'a frase regravada perdia a classe do achado, e a borda ficava '
              'de areia',
        );
        expect(
          (tester.widget<Container>(barra).decoration as BoxDecoration).color,
          cor,
          reason: 'a barra do achado virava listras de areia',
        );
        expect(tester.widget<Text>(palavra).style?.color, telha);
        closeTheRoom(container);
      });
    }
  }

  testWidgets('a finding on the fresh frase that took the stale one\'s number '
      'leaves the «regravada» card in sand', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _comUmaFraseRegravada(
      tester,
      harness,
      fresca: 1,
      achados: const [
        BtFinding(kind: BtFindingKind.unclear, frase: 1, segmentId: 'trecho-3'),
      ],
    );
    final cartao = _oCartao(find.text('regravada — traduzam de novo')).first;

    expect(
      (tester.widget<Container>(cartao).foregroundDecoration as DashedEdge?)
          ?.color,
      const Color(0xFFC5C29F),
      reason:
          'o número da frase muda quando a parte é regravada; achar o achado '
          'pelo número pintava a regravada com o achado da frase nova',
    );
    closeTheRoom(container);
  });
}
