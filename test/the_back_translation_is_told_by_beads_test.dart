import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const parte = Duration(seconds: 10);
const cabeca = Duration(seconds: 4);

const gravar = 'Tocar para gravar a tradução deste trecho';
const terminar = 'Tocar ao terminar';
const ouvir = 'Ouvir';
const pausar = 'Pausar';
const tesoura = 'Cortar aqui';
const confirmar = 'Confirmar a tradução e seguir';
const conferir = 'Conferir a tradução';
const aprovar = 'Aprovar como rascunho final';

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

Finder corda() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == 'RetroCord',
);

Future<void> tocar(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<ProviderContainer> entrarNaTraducao(
  WidgetTester tester,
  SalaHarness harness, {
  int partes = 2,
  Duration? medida = parte,
}) async {
  harness.playback
    ..measured = medida
    ..length = medida;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var gravada = 0; gravada < partes; gravada++) {
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

Future<void> gravarATraducao(WidgetTester tester) async {
  await tocar(tester, gravar);
  await tocar(tester, terminar);
}

Future<void> contarAteOFimDaParte(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
  await gravarATraducao(tester);
  await tocar(tester, confirmar);
}

void main() {
  testWidgets('B1 — a tradução entra tocando, com uma conta pendente e sem '
      'corda', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(
      harness.playback.sounding,
      isTrue,
      reason: 'o ensaio toca sozinho ao entrar',
    );
    expect(harness.playback.playedFrom.last, Duration.zero);
    expect(contas(tester), ['translucent com anel']);
    expect(aceso(tester, pausar), isTrue);
    expect(aceso(tester, tesoura), isTrue);
    expect(aceso(tester, confirmar), isFalse);
    expect(aceso(tester, conferir), isFalse);
    expect(corda(), findsNothing, reason: 'as contas substituem a corda');
    closeTheRoom(container);
  });

  testWidgets('B2 — a tesoura só corta: para o clipe, não abre o microfone, '
      'e nasce a conta do resto', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    await tocar(tester, pausar);
    expect(
      aceso(tester, tesoura),
      isFalse,
      reason: 'parada no cursor, a cabeça está num limite do trecho',
    );

    harness.playback.at = cabeca;
    await tocar(tester, ouvir);
    await tocar(tester, pausar);
    expect(
      aceso(tester, tesoura),
      isTrue,
      reason: 'pausada dentro do trecho pendente, há onde cortar',
    );

    await tocar(tester, ouvir);
    expect(aceso(tester, tesoura), isTrue, reason: 'tocando, corta');

    final capturas = harness.recorder.captures;
    await tocar(tester, tesoura);

    expect(harness.playback.sounding, isFalse, reason: 'cortar para o clipe');
    expect(
      harness.recorder.captures,
      capturas,
      reason: 'a tesoura não abre o microfone',
    );
    expect(
      container.read(salaSessionProvider).btPhase,
      isNot(BtPhase.capturing),
    );
    expect(contas(tester), ['translucent com anel', 'translucent']);
    expect(
      aceso(tester, tesoura),
      isFalse,
      reason: 'a cabeça ficou no corte, que é um limite',
    );
    closeTheRoom(container);
  });

  testWidgets('B3 — só o V manda a tradução, confirma o trecho e toca o '
      'seguinte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);

    expect(harness.room.chunksSent, 0, reason: 'nada vai antes do V');
    expect(aceso(tester, confirmar), isTrue);
    final gravada = harness.recorder.lastPath;

    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000']);
    expect(harness.room.chunkFiles, [gravada]);
    expect(contas(tester), ['solid', 'translucent com anel']);
    expect(
      harness.playback.sounding,
      isTrue,
      reason: 'o trecho seguinte toca sozinho',
    );
    expect(harness.playback.playedFrom.last, cabeca);
    expect(aceso(tester, confirmar), isFalse);
    closeTheRoom(container);
  });

  testWidgets('B3b — um V recusado guarda a tradução pendente', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    final gravada = harness.recorder.lastPath;
    final capturas = harness.recorder.captures;

    harness.room.failChunkWith = const RoomBroke('HTTP 500');
    await tocar(tester, confirmar);

    final depois = container.read(salaSessionProvider);
    expect(depois.btChunkFailures, hasLength(1));
    expect(depois.needsPerson, isFalse);
    expect(contas(tester), ['translucent com anel', 'translucent']);
    expect(aceso(tester, confirmar), isTrue);

    harness.room.failChunkWith = null;
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000']);
    expect(harness.room.chunkFiles, [gravada]);
    expect(harness.recorder.captures, capturas, reason: 'não se grava de novo');
    expect(contas(tester), ['solid', 'translucent com anel']);
    closeTheRoom(container);
  });

  testWidgets('B3c — sem corte, a tradução vai do cursor até a cabeça', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, pausar);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000']);
    closeTheRoom(container);
  });

  testWidgets('B4 — o disco de avanço pede o veredito só depois do último V', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    await contarAteOFimDaParte(tester, harness);
    expect(
      harness.playback.sounding,
      isTrue,
      reason: 'o V da primeira parte leva à segunda, que toca sozinha',
    );

    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await gravarATraducao(tester);

    expect(aceso(tester, conferir), isFalse);
    await tester.tap(byLabel(conferir));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'com uma tradução pendente o disco não pede nada',
    );

    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-10000', '0-10000']);
    expect(contas(tester), ['solid', 'solid']);
    expect(aceso(tester, conferir), isTrue);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.room.playedByTakeSent, hasLength(1));
    expect(
      byLabel('Terminei de traduzir'),
      findsNothing,
      reason: 'o disco de avanço é a única saída',
    );
    closeTheRoom(container);
  });

  testWidgets('B5 — a conferida mostra as contas e aprova', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await contarAteOFimDaParte(tester, harness);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(contas(tester), ['solid', 'solid']);
    expect(corda(), findsNothing);
    expect(byLabel(aprovar), findsOneWidget);
    expect(byLabel('Ouvir a gravação'), findsOneWidget);

    await tocar(tester, aprovar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.releasesAsked, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('B7 — o trecho não contado que o veredito nomeia vai pelo V '
      'como substituição', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final gravacao = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await contarAteOFimDaParte(tester, harness);

    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      contas(tester),
      ['solid com anel', 'solid'],
      reason: 'uma conta por trecho, e o anel no trecho nomeado, no seu lugar',
    );
    final daChegada = (
      harness.playback.played.last,
      harness.playback.ranges.last,
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);
    expect(
      (harness.playback.played.last, harness.playback.ranges.last),
      daChegada,
      reason: 'ouvir toca a fatia do próprio trecho nomeado',
    );
    expect(aceso(tester, tesoura), isFalse);
    expect(contas(tester), ['solid com anel', 'solid']);
    await tocar(tester, pausar);

    harness.room.verdictUntoldSegmentId = null;
    final vereditos = harness.room.playedByTakeSent.length;
    await gravarATraducao(tester);
    expect(harness.room.replacesAsked, isEmpty, reason: 'nada antes do V');

    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');
    expect(
      harness.room.playedByTakeSent,
      hasLength(vereditos + 1),
      reason: 'o veredito é pedido de novo, como hoje',
    );
    closeTheRoom(container);
  });

  testWidgets('B3d — uma substituição recusada guarda a tradução pendente', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final gravacao = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await contarAteOFimDaParte(tester, harness);

    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    await gravarATraducao(tester);
    final capturas = harness.recorder.captures;

    harness.room.failReplaceWith = const RoomBroke('HTTP 500');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(aceso(tester, confirmar), isTrue);

    harness.room.failReplaceWith = null;
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked.last, 'trecho-1@$gravacao:0-4000');
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');
    expect(harness.recorder.captures, capturas, reason: 'não se grava de novo');
    closeTheRoom(container);
  });

  testWidgets('B1b — o trecho pendente de uma parte anterior fica no seu '
      'lugar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final primeira = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);
    await contarAteOFimDaParte(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [primeira];
    await tester.tap(byLabel(conferir));
    await tester.pump(const Duration(milliseconds: 600));

    expect(contas(tester), ['solid', 'translucent com anel', 'solid']);
    closeTheRoom(container);
  });

  testWidgets('B3e — o círculo com o clipe tocando grava até a cabeça', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await gravarATraducao(tester);
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000']);
    closeTheRoom(container);
  });

  testWidgets('B3f — com uma tradução pendente a tesoura se apaga e o círculo '
      'não abre outra captura', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, ouvir);
    expect(aceso(tester, tesoura), isFalse);

    final capturas = harness.recorder.captures;
    await tocar(tester, gravar);
    expect(harness.recorder.captures, capturas);
    expect(byLabel(terminar), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('B3h — uma tradução recusada vai para a fila uma vez só', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final fila = harness.takes as FakeTakeQueue;

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    final gravada = harness.recorder.lastPath;

    harness.room.failChunkWith = const RoomBroke('HTTP 500');
    await tocar(tester, confirmar);
    await letTheRehearsalReachTheRoom(tester);
    await tocar(tester, confirmar);
    await letTheRehearsalReachTheRoom(tester);
    harness.room.failChunkWith = null;
    await tocar(tester, confirmar);
    await letTheRehearsalReachTheRoom(tester);

    expect(harness.room.chunkFiles, [gravada]);
    expect(
      [
        for (final linha in fila.rows)
          if (linha.path == gravada) linha.kind,
      ],
      ['retro'],
    );
    closeTheRoom(container);
  });

  testWidgets('B4b — o disco fica apagado enquanto sobra chão por contar na '
      'última parte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(aceso(tester, confirmar), isFalse);
    expect(aceso(tester, conferir), isFalse);
    closeTheRoom(container);
  });

  testWidgets('B4c — uma parte que o player não mede não prende o disco', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(
      tester,
      harness,
      partes: 1,
      medida: null,
    );

    harness.playback.at = cabeca;
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    harness.playback.at = Duration.zero;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(aceso(tester, conferir), isTrue);
    closeTheRoom(container);
  });

  testWidgets('B5b — deixar a passagem apaga a tradução pendente', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await gravarATraducao(tester);
    final gravada = harness.recorder.lastPath;
    container.read(salaSessionProvider.notifier).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, contains(gravada));
    closeTheRoom(container);
  });

  testWidgets('B10 — a tela segue o quadro T1', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 1180)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    expect(tester.getTopLeft(find.byType(BeadRow)).dy, 86);
    expect(tester.getTopLeft(byLabel(gravar)), const Offset(330, 456));
    expect(tester.getTopLeft(byLabel(pausar)), const Offset(296, 680));
    expect(tester.getTopLeft(byLabel(tesoura)), const Offset(380, 680));
    expect(tester.getTopLeft(byLabel(confirmar)), const Offset(464, 680));
    expect(tester.getTopLeft(byLabel(conferir)), const Offset(371, 798));
    closeTheRoom(container);
  });

  testWidgets('B8 — os rótulos falam a língua da sala', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);

    expect(byLabel("Tap to record this stretch's translation"), findsOneWidget);
    expect(byLabel('Pause'), findsOneWidget);
    expect(byLabel('Cut here'), findsOneWidget);
    expect(byLabel('Confirm the translation and go on'), findsOneWidget);
    expect(byLabel('Check the translation'), findsOneWidget);
    expect(byLabel('Stretch 1'), findsOneWidget);

    await tester.tap(byLabel('Pause'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Listen'), findsOneWidget);

    harness.playback.at = cabeca;
    await tester.tap(byLabel("Tap to record this stretch's translation"));
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Tap when you finish'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('B9 — depois do corte, ouvir toca o trecho do cursor ao corte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await tocar(tester, ouvir);

    expect(harness.playback.ranges.last, '0-4000');
    expect(harness.playback.sounding, isTrue);
    closeTheRoom(container);
  });

  testWidgets('B9b — cortar de novo enquanto o trecho repete move o corte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);

    harness.playback.at = const Duration(seconds: 8);
    await tocar(tester, tesoura);
    await tocar(tester, ouvir);
    expect(harness.playback.ranges.last, '4000-8000');

    harness.playback.at = const Duration(seconds: 2);
    expect(aceso(tester, tesoura), isTrue);
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000', '4000-6000']);
    closeTheRoom(container);
  });
}
