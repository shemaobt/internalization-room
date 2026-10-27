import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show contarAteOFimDaParte, pausadaNoToque, tocarNoCirculo;

const parte = Duration(seconds: 10);
const cabeca = Duration(seconds: 4);

const pausado = 'pausado — toque no círculo para marcar onde a frase acaba';
const fimDaGravacao = 'fim da gravação';
const gravar = 'Tocar para gravar a tradução deste trecho';
const gravarDeNovo = 'Tocar para gravar a tradução de novo';
const terminar = 'Tocar ao terminar';
const ouvir = 'Ouvir';
const ouvirATraducao = 'Ouvir a tradução';
const pausar = 'Pausar';
const tesoura = 'Pausar onde a frase acaba';
const confirmar = 'Confirmar a tradução e seguir';
const conferir = 'terminei';

bool aceso(WidgetTester tester, String label) {
  final semantics = tester.widget<Semantics>(byLabel(label));
  final opacity = tester
      .widget<AnimatedOpacity>(
        find
            .descendant(
              of: byLabel(label),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;
  final enabled = semantics.properties.enabled ?? true;
  expect(
    enabled,
    opacity == 1,
    reason: 'o que a equipe vê aceso é o que o botão aceita: $label',
  );
  return enabled;
}

Iterable<BoxDecoration> _pinturas(Finder dentro) => find
    .descendant(of: dentro, matching: find.byType(Container))
    .evaluate()
    .map((element) => (element.widget as Container).decoration)
    .whereType<BoxDecoration>();

String _cor(Gradient? tinta) {
  if (tinta == BeadStyles.wood) return 'wood';
  if (tinta == BeadStyles.azul) return 'azul';
  if (tinta == BeadStyles.telha(SalaColors.light)) return 'telha';
  if (tinta == BeadStyles.clay(SalaColors.light)) return 'clay';
  return '$tinta';
}

Finder _circulo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

double? _escalaDaOnda(WidgetTester tester) {
  final ondas = find.descendant(of: _circulo(), matching: find.byType(Ripple));
  if (ondas.evaluate().isEmpty) return null;
  return tester
      .widgetList<Transform>(
        find.descendant(of: ondas.first, matching: find.byType(Transform)),
      )
      .first
      .transform
      .getMaxScaleOnAxis();
}

bool _circuloApagado(WidgetTester tester) =>
    tester
        .widget<AnimatedOpacity>(
          find
              .descendant(
                of: _circulo(),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity ==
    0;

Future<String> olhar(WidgetTester tester) async {
  final circulo = _circulo();
  final tinta = _pinturas(
    circulo,
  ).map((pintura) => pintura.gradient).whereType<Gradient>().first;
  final anel = _pinturas(
    circulo,
  ).any((pintura) => pintura.boxShadow != null && pintura.border != null);
  final antes = _escalaDaOnda(tester);
  await tester.pump(const Duration(milliseconds: 120));
  final depois = _escalaDaOnda(tester);
  final String movimento;
  if (antes == null || depois == null) {
    movimento = 'parado';
  } else if (anel && depois < antes) {
    movimento = 'ouvindo';
  } else if (!anel && depois > antes) {
    movimento = 'soando';
  } else {
    movimento = 'anel $anel, ondas de $antes para $depois';
  }
  return '${_cor(tinta)} $movimento';
}

Future<void> tocarAConta(WidgetTester tester, int lugar) async {
  final conta = find
      .descendant(
        of: find.descendant(
          of: find.byType(RetroView),
          matching: find.byType(BeadRow),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.button == true,
        ),
      )
      .at(lugar);
  await tester.ensureVisible(conta);
  await tester.tap(conta);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(offTheRows(label));
  await tester.tap(offTheRows(label));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<ProviderContainer> entrarNaTraducao(
  WidgetTester tester,
  SalaHarness harness, {
  String? pericope,
}) async {
  harness.playback
    ..measured = parte
    ..length = parte;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth', pericope: pericope);
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var gravada = 0; gravada < 2; gravada++) {
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: gravada + 1);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<String> gravarATraducao(
  WidgetTester tester,
  SalaHarness harness, {
  String circulo = pausadaNoToque,
}) async {
  await tocar(tester, circulo);
  await tocar(tester, terminar);
  return harness.recorder.lastPath!;
}

Future<ProviderContainer> doisContadosEOTerceiroPendente(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester, harness);
  harness.playback.at = const Duration(seconds: 8);
  await tocarNoCirculo(tester);
  await gravarATraducao(tester, harness);
  harness.playback.at = const Duration(seconds: 9);
  await tocarNoCirculo(tester);
  expect(contas(tester), [
    'solid',
    'solid',
    'translucent com anel',
    'translucent',
  ]);
  return container;
}

void main() {
  testWidgets('R2 — o círculo veste a voz que soa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(await olhar(tester), 'wood soando', reason: 'a língua materna toca');

    harness.playback.at = cabeca;
    await tocar(tester, pausar);
    expect(await olhar(tester), 'telha parado');

    await tocar(tester, pausado);
    await tocarNoCirculo(tester);
    expect(await olhar(tester), 'azul ouvindo');

    await tocar(tester, terminar);
    expect(await olhar(tester), 'wood soando');
    closeTheRoom(container);
  });

  testWidgets('R3 — a conta tocada toca o seu trecho e devolve o anel ao '
      'pendente', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await doisContadosEOTerceiroPendente(tester, harness);

    await tocarAConta(tester, 0);

    expect(
      harness.playback.played.last,
      container.read(salaSessionProvider).partes.first.path,
    );
    expect(harness.playback.sounding, isTrue);
    expect(contas(tester), [
      'solid com anel',
      'solid',
      'translucent',
      'translucent',
    ]);
    expect(aceso(tester, pausar), isTrue);
    expect(await olhar(tester), 'wood soando');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(contas(tester), [
      'solid',
      'solid',
      'translucent com anel',
      'translucent',
    ]);

    await tocarAConta(tester, 0);
    expect(harness.playback.sounding, isTrue);
    expect(contas(tester).first, 'solid com anel');
    await tocarAConta(tester, 2);

    expect(harness.playback.sounding, isFalse);
    expect(contas(tester), [
      'solid',
      'solid',
      'translucent com anel',
      'translucent',
    ]);

    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);

    expect(
      harness.room.chunkSpans.last,
      '8000-9000',
      reason: 'o cursor e o corte não andaram',
    );
    closeTheRoom(container);
  });

  testWidgets('a bead tapped before any verdict opens its frase to be told '
      'again and plays it out of the recording, not its translation', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await doisContadosEOTerceiroPendente(tester, harness);
    final gravacao = container.read(salaSessionProvider).partes.first.path;
    final tocadas = harness.playback.played.length;
    final trechos = harness.playback.ranges.length;

    container.read(salaSessionProvider.notifier).ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.playback.played.skip(tocadas),
      [gravacao],
      reason: 'a conta tocava a tradução da frase, e a dela toca a gravação',
    );
    expect(harness.playback.ranges.skip(trechos), ['0-4000']);
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-1',
      reason:
          'antes do veredito a conta só tocava a frase, e a barra dela já a '
          'abre para traduzir de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('R3 — com o clipe pausado no meio, a conta tocada não move a '
      'cabeça', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    harness.playback.at = const Duration(seconds: 7);
    await tocar(tester, pausar);

    await tocarAConta(tester, 0);
    expect(aceso(tester, pausar), isTrue);
    harness.playback.at = const Duration(seconds: 2);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await tocar(tester, ouvir);
    expect(harness.playback.played.last, harness.playback.played.first);
    expect(harness.playback.playedFrom.last, const Duration(seconds: 7));
    await tocar(tester, pausar);

    await tocarAConta(tester, 0);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, pausado);
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);

    expect(harness.room.chunkSpans, ['0-4000', '4000-7000']);
    closeTheRoom(container);
  });

  testWidgets('R3 — uma conta sem tradução no tablet, antes do veredito, abre '
      'a frase e toca a sua língua materna', (tester) async {
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-1117').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..measured = parte
      ..length = parte;
    harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 4000,
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(notifier.abrirEscolha);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a tradução retomada pôr a parte no ar',
        () => harness.playback.sounding,
      );
    });
    await tester.pump(const Duration(milliseconds: 600));
    expect(contas(tester), ['solid', 'translucent com anel']);

    await tocarAConta(tester, 0);

    expect(harness.playback.played.lastOrNull, gravada.path);
    expect(harness.playback.ranges.lastOrNull, '0-4000');
    expect(contas(tester), ['solid com anel']);
    expect(await olhar(tester), 'wood soando');
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-1',
      reason:
          'antes do veredito a conta só tocava a frase, e a barra dela já a '
          'abre para traduzir de novo',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(contas(tester), ['solid com anel']);
    expect(await olhar(tester), 'telha parado');
    closeTheRoom(container);
  });

  testWidgets('R3 — a conta pendente, sem conta escolhida, toca o trecho '
      'pendente como o play', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.takeLandsAfter = const Duration(seconds: 1);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    expect(harness.playback.sounding, isFalse);
    await tocarAConta(tester, 0);

    expect(harness.playback.ranges.last, '0-4000');
    expect(harness.playback.sounding, isTrue);
    expect(contas(tester), ['translucent com anel', 'translucent']);
    closeTheRoom(container);
  });

  testWidgets('R3b — ouvir uma conta não conta como ouvir a parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    harness.playback.at = const Duration(seconds: 7);

    await tocarAConta(tester, 0);
    harness.playback.at = const Duration(seconds: 3);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);

    for (var vez = 0; vez < 2; vez++) {
      await contarAteOFimDaParte(tester, harness);
    }
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      [
        for (final parte in harness.room.playedByTakeSent.single)
          [parte['played_ranges'], parte['clip_duration_ms']],
      ],
      [
        for (var vez = 0; vez < 2; vez++)
          [
            [
              [0, 10000],
            ],
            10000,
          ],
      ],
      reason: 'cada parte foi ouvida inteira uma vez, com ou sem a conta',
    );
    closeTheRoom(container);
  });

  testWidgets('R3 — uma conta tocada com a parte ainda abrindo não deixa a '
      'cabeça atrás do cursor', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.playback.at = Duration.zero;
    harness.playback.holdNextOpening();
    await tocar(tester, terminar);
    await tocar(tester, pausar);
    harness.playback.finishHeldOpening();
    await tester.pump(const Duration(milliseconds: 300));

    await tocarAConta(tester, 0);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);

    expect(harness.playback.playedFrom.last, cabeca);
    closeTheRoom(container);
  });

  testWidgets('R3 — com o clipe pausado no meio, a conta de uma frase com '
      'nome a abre de novo, e manter a tradução de antes devolve a cabeça '
      'onde estava', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    harness.playback.at = const Duration(seconds: 7);
    await tocar(tester, pausar);

    await tocarAConta(tester, 0);
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-1',
    );
    expect(harness.playback.ranges.last, '0-4000');
    expect(contas(tester), ['solid com anel']);
    harness.playback.at = cabeca;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await tocar(tester, 'manter a tradução de antes');
    expect(contas(tester), ['solid', 'translucent com anel']);
    await tocar(tester, ouvir);
    expect(harness.playback.played.last, harness.playback.played.first);
    expect(
      harness.playback.playedFrom.last,
      const Duration(seconds: 7),
      reason: 'a conta que abriu a frase de novo deixava a cabeça no fim dela',
    );
    await tocar(tester, pausar);
    await tocar(tester, pausado);
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);

    expect(harness.room.chunkSpans, ['0-4000', '4000-7000']);
    closeTheRoom(container);
  });

  testWidgets('R3 — a tesoura depois de uma conta tocada corta na cabeça de '
      'antes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    harness.playback.at = const Duration(seconds: 7);
    await tocar(tester, pausar);

    await tocarAConta(tester, 0);
    harness.playback.at = const Duration(seconds: 2);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);
    await tocar(tester, ouvir);

    expect(harness.playback.ranges.last, '4000-7000');
    closeTheRoom(container);
  });

  testWidgets('R3 — o disco de avanço se apaga enquanto uma conta toca', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.chunksAnswerWithNoName = true;
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    for (var vez = 0; vez < 2; vez++) {
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
    }
    expect(aceso(tester, conferir), isTrue);

    await tocarAConta(tester, 0);
    expect(aceso(tester, conferir), isFalse);

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(aceso(tester, conferir), isTrue);
    closeTheRoom(container);
  });

  testWidgets('R3 — o disco de avanço se apaga enquanto a conta de uma frase '
      'com nome a abre de novo, e acende com manter a tradução de antes', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    for (var vez = 0; vez < 2; vez++) {
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
    }
    expect(aceso(tester, conferir), isTrue);

    await tocarAConta(tester, 0);
    expect(aceso(tester, conferir), isFalse);

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      aceso(tester, conferir),
      isFalse,
      reason: 'o terminei acendia com uma frase aberta para traduzir de novo',
    );

    await tocar(tester, 'manter a tradução de antes');
    expect(aceso(tester, conferir), isTrue);
    closeTheRoom(container);
  });

  Future<ProviderContainer> retomarComAviso(
    WidgetTester tester,
    SalaHarness harness,
  ) async {
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-1117').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.playback
      ..measured = parte
      ..length = parte;
    harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    harness.room
      ..serverHalt = HaltKind.warning
      ..retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(notifier.abrirEscolha);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  Future<void> esperarAParada(WidgetTester tester) async {
    await waitFor(
      'a tela da parada aparecer',
      () => byLabel('Um momento para uma pessoa').evaluate().isNotEmpty,
      limit: const Duration(seconds: 3),
      step: () async {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      },
    );
  }

  Future<void> pararPorUmaPessoa(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await esperarAParada(tester);
  }

  testWidgets(
    'waiting for the halt screen fails at its deadline when the room never '
    'stops, not in silence',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await expectLater(
        () => esperarAParada(tester),
        throwsA(isA<TimeoutException>()),
        reason:
            'a espera devolvia depois de trinta segundos sem a parada ter '
            'aparecido, e o caso seguia como se ela tivesse aparecido',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('R2 — uma parada com o clipe tocando vence a madeira', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await retomarComAviso(tester, harness);

    await pararPorUmaPessoa(tester, container);

    expect(byLabel('Um momento para uma pessoa'), findsOneWidget);
    expect(_circuloApagado(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('R2 — uma parada com uma tradução tocando vence o azul', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await retomarComAviso(tester, harness);
    await tester.runAsync(() => theClipOpens(harness));
    harness.playback.at = const Duration(seconds: 7);
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
    await tocar(tester, pausar);
    await tocarAConta(tester, 1);
    expect(harness.playback.sounding, isTrue);

    await pararPorUmaPessoa(tester, container);

    expect(byLabel('Um momento para uma pessoa'), findsOneWidget);
    expect(_circuloApagado(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('R2b — the warning mark speaks the rooms language', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await retomarComAviso(tester, harness);
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.bySemanticsLabel('A warning is asking someone to come watch'),
      findsOneWidget,
      reason:
          'a marca existe ao lado do círculo, mas o que ela diz a um leitor '
          'de tela em inglês precisa vir do mapa, não do português fixo',
    );
    handle.dispose();
    closeTheRoom(container);
  });

  testWidgets('R5 — os rótulos novos falam a língua da sala', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(
      tester,
      'the pause is at your tap — tap the circle to translate',
    );
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocar(tester, 'Tap when you finish');
    await waitFor(
      'a sala recusar a frase',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(byLabel('Tap to record the translation again'), findsOneWidget);
    expect(byLabel('Listen to the translation'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('R6 — a halt in the back-translation speaks the rooms language', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, retroLabelFor('pauseAtTheTap', 'en'));
    await tocar(tester, retroLabelFor('recording', 'en'));
    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel(circleLabelFor('needsPerson', 'en')), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets(
    'R8 — the circle thinking in the back-translation speaks the rooms '
    'language',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
      final container = await entrarNaTraducao(tester, harness);

      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await tocar(tester, retroLabelFor('pauseAtTheTap', 'en'));
      harness.room.holdNextChunk();
      await tocar(tester, retroLabelFor('recording', 'en'));

      expect(
        tester.widget<FacilitatorCircle>(_circulo()).semanticLabel,
        retroLabelFor('thinking', 'en'),
      );

      harness.room.finishHeldChunk();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(container);
    },
  );

  testWidgets('R9 — a checked passage in the back-translation speaks the rooms '
      'language', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    harness.room
      ..verdictChecked = true
      ..takeLandsAfter = const Duration(seconds: 2);
    harness.playback
      ..measured = parte
      ..length = parte;
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));

    harness.playback.at = const Duration(seconds: 10);
    notifier.retroTap();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<FacilitatorCircle>(_circulo()).semanticLabel,
      retroLabelFor('translated', 'en'),
    );
    closeTheRoom(container);
  });
}
