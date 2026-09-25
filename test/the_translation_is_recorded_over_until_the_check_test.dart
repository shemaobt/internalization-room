import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
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

const parte = Duration(seconds: 10);
const cabeca = Duration(seconds: 4);

const gravar = 'Tocar para gravar a tradução deste trecho';
const gravarDeNovo = 'Tocar para gravar a tradução de novo';
const terminar = 'Tocar ao terminar';
const ouvir = 'Ouvir';
const ouvirATraducao = 'Ouvir a tradução';
const pausar = 'Pausar';
const tesoura = 'Cortar aqui';
const confirmar = 'Confirmar a tradução e seguir';
const conferir = 'Conferir a tradução';

Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

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

List<String> contas(WidgetTester tester) => [
  for (final conta
      in tester.widget<BeadRow>(find.byType(BeadRow).first).entries)
    '${conta.fill.name}${conta.current ? ' com anel' : ''}',
];

Iterable<BoxDecoration> _pinturas(Finder dentro) => find
    .descendant(of: dentro, matching: find.byType(Container))
    .evaluate()
    .map((element) => (element.widget as Container).decoration)
    .whereType<BoxDecoration>();

String _cor(Gradient? tinta) {
  if (tinta == BeadStyles.wood) return 'wood';
  if (tinta == BeadStyles.azul) return 'azul';
  if (tinta == BeadStyles.telha(SalaColors.light)) return 'telha';
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

Future<void> tocar(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
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
  await notifier.goConversa(pericope: pericope);
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var gravada = 0; gravada < 2; gravada++) {
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<String> gravarATraducao(
  WidgetTester tester,
  SalaHarness harness, {
  String circulo = gravar,
}) async {
  await tocar(tester, circulo);
  await tocar(tester, terminar);
  return harness.recorder.lastPath!;
}

class DoisContados {
  final ProviderContainer container;
  final String primeira;
  final String pendente;

  DoisContados(this.container, this.primeira, this.pendente);
}

Future<DoisContados> doisContadosEOTerceiroPendente(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness);
  harness.playback.at = cabeca;
  await tocar(tester, tesoura);
  final primeira = await gravarATraducao(tester, harness);
  await tocar(tester, confirmar);
  harness.playback.at = const Duration(seconds: 8);
  await tocar(tester, tesoura);
  await gravarATraducao(tester, harness);
  await tocar(tester, confirmar);
  harness.playback.at = const Duration(seconds: 9);
  await tocar(tester, tesoura);
  final pendente = await gravarATraducao(tester, harness);
  expect(contas(tester), [
    'solid',
    'solid',
    'translucent com anel',
    'translucent',
  ]);
  return DoisContados(container, primeira, pendente);
}

void main() {
  testWidgets('R1 — a tradução pendente é regravada no círculo até o V', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, pausar);
    await tocar(tester, gravar);

    expect(await olhar(tester), 'azul ouvindo');
    expect(aceso(tester, ouvir), isFalse);
    expect(aceso(tester, tesoura), isFalse);
    expect(aceso(tester, confirmar), isFalse);
    expect(aceso(tester, conferir), isFalse);

    await tocar(tester, terminar);
    final primeira = harness.recorder.lastPath;
    expect(harness.room.chunksSent, 0, reason: 'nada vai antes do V');
    expect(aceso(tester, confirmar), isTrue);
    expect(aceso(tester, ouvirATraducao), isTrue);
    await tocar(tester, ouvirATraducao);
    expect(harness.playback.played.last, primeira);
    expect(harness.playback.sounding, isTrue);

    await tocar(tester, pausar);
    final segunda = await gravarATraducao(
      tester,
      harness,
      circulo: gravarDeNovo,
    );
    expect(segunda, isNot(primeira));
    expect(harness.recorder.deleted, contains(primeira));
    expect(harness.recorder.deleted, isNot(contains(segunda)));
    expect(harness.room.chunksSent, 0, reason: 'regravar não manda nada');
    await tocar(tester, ouvirATraducao);
    expect(harness.playback.played.last, segunda);
    await tocar(tester, pausar);

    await tocar(tester, confirmar);

    expect(harness.room.chunkFiles, [segunda]);
    expect(harness.room.chunkSpans, ['0-4000']);
    closeTheRoom(container);
  });

  testWidgets('R1b — uma regravação que não abre o microfone guarda a '
      'tradução de antes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    final primeira = await gravarATraducao(tester, harness);

    harness.recorder.startThrows = true;
    await tocar(tester, gravarDeNovo);
    harness.recorder.startThrows = false;

    expect(byLabel(gravarDeNovo), findsOneWidget);
    expect(await olhar(tester), 'telha parado');
    expect(harness.recorder.deleted, isNot(contains(primeira)));
    expect(aceso(tester, confirmar), isTrue);
    await tocar(tester, confirmar);

    expect(harness.room.chunkFiles, [primeira]);
    expect(harness.room.chunkSpans, ['0-4000']);
    closeTheRoom(container);
  });

  testWidgets('R1b — uma regravação que fecha sem arquivo guarda a tradução '
      'de antes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    final primeira = await gravarATraducao(tester, harness);

    harness.recorder.returnsNothing = true;
    await tocar(tester, gravarDeNovo);
    await tocar(tester, terminar);
    harness.recorder.returnsNothing = false;

    expect(byLabel(gravarDeNovo), findsOneWidget);
    expect(await olhar(tester), 'telha parado');
    expect(harness.recorder.deleted, isNot(contains(primeira)));
    expect(aceso(tester, confirmar), isTrue);
    await tocar(tester, confirmar);

    expect(harness.room.chunkFiles, [primeira]);
    closeTheRoom(container);
  });

  testWidgets('R2 — o círculo veste a voz que soa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(await olhar(tester), 'wood soando', reason: 'a língua materna toca');

    harness.playback.at = cabeca;
    await tocar(tester, pausar);
    expect(await olhar(tester), 'telha parado');

    await tocar(tester, gravar);
    expect(await olhar(tester), 'azul ouvindo');

    await tocar(tester, terminar);
    expect(await olhar(tester), 'telha parado');

    await tocar(tester, ouvirATraducao);
    expect(
      await olhar(tester),
      'azul soando',
      reason: 'a tradução pendente toca',
    );
    closeTheRoom(container);
  });

  testWidgets('R3 — a conta tocada toca o seu trecho e devolve o anel ao '
      'pendente', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final contados = await doisContadosEOTerceiroPendente(tester, harness);

    await tocar(tester, 'Trecho 1');

    expect(harness.playback.played.last, contados.primeira);
    expect(harness.playback.sounding, isTrue);
    expect(contas(tester), [
      'solid com anel',
      'solid',
      'translucent',
      'translucent',
    ]);
    expect(aceso(tester, tesoura), isFalse);
    expect(aceso(tester, confirmar), isFalse);
    expect(aceso(tester, pausar), isTrue);
    expect(await olhar(tester), 'azul soando');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(contas(tester), [
      'solid',
      'solid',
      'translucent com anel',
      'translucent',
    ]);
    expect(aceso(tester, confirmar), isTrue);
    expect(aceso(tester, tesoura), isFalse);

    await tocar(tester, 'Trecho 1');
    expect(harness.playback.sounding, isTrue);
    expect(contas(tester).first, 'solid com anel');
    await tocar(tester, 'Trecho 3');

    expect(harness.playback.sounding, isFalse);
    expect(contas(tester), [
      'solid',
      'solid',
      'translucent com anel',
      'translucent',
    ]);
    expect(aceso(tester, confirmar), isTrue);

    await tocar(tester, confirmar);

    expect(
      harness.room.chunkSpans.last,
      '8000-9000',
      reason: 'o cursor e o corte não andaram',
    );
    expect(
      harness.room.chunkFiles.last,
      contados.pendente,
      reason: 'a tradução pendente é a mesma',
    );
    closeTheRoom(contados.container);
  });

  testWidgets('R3 — com o clipe pausado no meio, a conta tocada não move a '
      'cabeça', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester, harness);
    await tocar(tester, confirmar);
    harness.playback.at = const Duration(seconds: 7);
    await tocar(tester, pausar);

    expect(aceso(tester, tesoura), isTrue);
    await tocar(tester, 'Trecho 1');
    expect(aceso(tester, tesoura), isFalse);
    expect(aceso(tester, pausar), isTrue);
    harness.playback.at = const Duration(seconds: 2);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(aceso(tester, tesoura), isTrue);
    await tocar(tester, ouvir);
    expect(harness.playback.played.last, harness.playback.played.first);
    expect(harness.playback.playedFrom.last, const Duration(seconds: 7));
    await tocar(tester, pausar);

    await tocar(tester, 'Trecho 1');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, gravar);
    await tocar(tester, terminar);
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000', '4000-7000']);
    closeTheRoom(container);
  });

  testWidgets('R3 — uma conta sem tradução no tablet toca a sua língua '
      'materna', (tester) async {
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-1117').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..measured = parte
      ..length = parte;
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
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
    await tester.runAsync(() => notifier.goConversa(pericope: 'P01'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(contas(tester), ['solid', 'translucent com anel']);

    await tocar(tester, 'Trecho 1');

    expect(harness.playback.played.lastOrNull, gravada.path);
    expect(harness.playback.ranges.lastOrNull, '0-4000');
    expect(contas(tester), ['solid com anel', 'translucent']);
    expect(await olhar(tester), 'wood soando');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(contas(tester), ['solid', 'translucent com anel']);
    expect(await olhar(tester), 'telha parado');
    closeTheRoom(container);
  });

  testWidgets('R3b — ouvir uma conta não conta como ouvir a parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester, harness);
    await tocar(tester, confirmar);
    harness.playback.at = const Duration(seconds: 7);

    await tocar(tester, 'Trecho 1');
    harness.playback.at = const Duration(seconds: 3);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);

    for (var vez = 0; vez < 2; vez++) {
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      await gravarATraducao(tester, harness);
      await tocar(tester, confirmar);
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

  testWidgets('R4 — gravar, regravar e confirmar fica na tradução e conta o '
      'trecho uma vez', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, pericope: 'P01');
    final linha = harness.emAberto.rows.values.single;

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester, harness);
    final regravada = await gravarATraducao(
      tester,
      harness,
      circulo: gravarDeNovo,
    );
    expect(harness.room.chunksSent, 0, reason: 'regravar não manda nada');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.sessionIds, [linha.sessionId]);
    expect(harness.emAberto.rows.values.single.sessionId, linha.sessionId);
    expect(harness.emAberto.rows.values.single.stage, SalaStage.retro);
    expect(harness.room.chunkFiles, [regravada]);
    expect(contas(tester), ['solid', 'translucent com anel']);
    expect(byLabel(conferir), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('R5 — os rótulos novos falam a língua da sala', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, 'Cut here');
    await tocar(tester, "Tap to record this stretch's translation");
    await tocar(tester, 'Tap when you finish');

    expect(byLabel('Tap to record the translation again'), findsOneWidget);
    expect(byLabel('Listen to the translation'), findsOneWidget);
    closeTheRoom(container);
  });
}
