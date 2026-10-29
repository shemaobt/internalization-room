import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const parte = Duration(seconds: 10);
const cabeca = Duration(seconds: 4);

/// Long enough for the part to have run past the cursor, with no gesture of its own.
const passaDoCursor = Duration(seconds: 1);

const gravar = 'Tocar para gravar a tradução deste trecho';
const ouvindo = 'ouvindo a gravação de vocês…';
const pausadaNoToque =
    'a pausa ficou no toque — toquem no círculo para traduzir';
const fimDaGravacao = 'fim da gravação';
const pausado = 'pausado — toque no círculo para marcar onde a frase acaba';
const terminar = 'Tocar ao terminar';
const ouvir = 'Ouvir';
const pausar = 'Pausar';
const tesoura = 'Pausar onde a frase acaba';
const confirmar = 'Confirmar a tradução e seguir';
const conferir = 'terminei';
const aprovar = 'Aprovar como rascunho final';

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

Finder corda() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == 'RetroCord',
);

Future<void> tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(offTheRows(label));
  await tester.tap(offTheRows(label));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A control of the Back-translation's own, while the Rehearsal it left still fades out
/// beneath it with controls of the same name.
Future<void> _tocarNaTraducao(WidgetTester tester, String label) async {
  final alvo = find.descendant(
    of: find.byType(RetroView),
    matching: byLabel(label),
  );
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
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
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var gravada = 0; gravada < partes; gravada++) {
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

Future<void> gravarATraducao(
  WidgetTester tester, {
  String circulo = pausadaNoToque,
}) async {
  await tocar(tester, circulo);
  await tocar(tester, terminar);
}

Future<void> tocarNoCirculo(WidgetTester tester) async {
  final circulo = find.descendant(
    of: find.byType(RetroView),
    matching: find.byType(FacilitatorCircle),
  );
  await tester.ensureVisible(circulo);
  await tester.tap(circulo);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> contarAteOFimDaParte(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.playback.at = parte;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await waitFor(
    'a parte seguir depois da frase',
    () => harness.playback.sounding,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<PendingTake> guardar(FakeTakeQueue fila, String scope) => fila.enqueue(
  File('/gravacoes/$scope.m4a'),
  sessionId: 'sessao-1',
  kind: 'retro',
  scope: scope,
);

List<Object?> armado(ProviderContainer container) {
  final estado = container.read(salaSessionProvider);
  return [
    estado.btTrechoTraduzidoDeNovo?.segmentId,
    for (final trecho in estado.btTrechos) trecho.contado,
  ];
}

void main() {
  testWidgets('B1 — a tradução entra tocando, sem nada contado e sem corda', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.takeLandsAfter = const Duration(seconds: 1);
    final container = await entrarNaTraducao(tester, harness);

    expect(
      harness.playback.sounding,
      isTrue,
      reason: 'o ensaio toca sozinho ao entrar',
    );
    expect(harness.playback.playedFrom.last, Duration.zero);
    expect(faixas(tester), ['0 contadas', '0 contadas']);
    expect(aceso(tester, pausar), isTrue);
    expect(container.read(salaSessionProvider).canConfirmTranslation, isFalse);
    expect(aceso(tester, conferir), isFalse);
    expect(corda(), findsNothing, reason: 'as contas substituem a corda');
    closeTheRoom(container);
  });

  testWidgets('B2 — o primeiro toque no círculo só pausa: para o clipe, não '
      'abre o microfone, e a pausa fica na faixa da parte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    await tocar(tester, pausar);
    harness.playback.at = cabeca;
    await _tocarNaTraducao(tester, ouvir);
    await tocar(tester, pausar);
    await _tocarNaTraducao(tester, ouvir);

    final capturas = harness.recorder.captures;
    await tocarNoCirculo(tester);

    expect(harness.playback.sounding, isFalse, reason: 'cortar para o clipe');
    expect(
      harness.recorder.captures,
      capturas,
      reason: 'o primeiro toque não abre o microfone',
    );
    expect(
      container.read(salaSessionProvider).btPhase,
      isNot(BtPhase.capturing),
    );
    expect(faixas(tester), ['0 contadas · pausa', '0 contadas']);
    closeTheRoom(container);
  });

  testWidgets('a told stretch that ends back onto the part held beneath it '
      'leaves the cursor as the part left it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await tester.pump(passaDoCursor);
    expect(
      container.read(salaSessionProvider).nothingHeardSinceCursor,
      isFalse,
      reason: 'a parte seguinte já passou do cursor',
    );

    container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).nothingHeardSinceCursor,
      isFalse,
      reason: 'o fim do trecho contado não é a parte parando no cursor',
    );
    closeTheRoom(container);
  });

  testWidgets('B3b — um V recusado é um pedaço não entendido', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocar(tester, terminar);
    final gravada = harness.recorder.lastPath;
    final capturas = harness.recorder.captures;

    final depois = container.read(salaSessionProvider);
    expect(depois.btChunkFailures, hasLength(1));
    expect(depois.needsPerson, isFalse);
    expect(faixas(tester), ['0 contadas · pausa', '0 contadas']);
    expect(container.read(salaSessionProvider).wordlessTelling, isTrue);

    harness.room.failChunkWith = null;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);

    expect(harness.room.chunkSpans, ['0-4000']);
    expect(harness.room.chunkFiles, [harness.recorder.lastPath]);
    expect(harness.room.chunkFiles, isNot(contains(gravada)));
    expect(
      harness.recorder.captures,
      capturas + 1,
      reason: 'o toque depois da recusa mandava a mesma gravação de novo',
    );
    expect(faixas(tester), ['1 contadas', '0 contadas']);
    closeTheRoom(container);
  });

  testWidgets('a stretch told over a take the part was recorded again over is '
      'never a strike, three times running', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    for (var recusa = 0; recusa < 3; recusa++) {
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await tocar(tester, pausadaNoToque);
      harness.room.replaceThePart(harness.room.takeIds.last);
      await tocar(tester, terminar);
      await tester.pump(const Duration(milliseconds: 600));
    }

    expect(harness.room.chunkKeys, hasLength(3), reason: 'três recusas');
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'a terceira recusa do trecho que não vale mais chamava uma pessoa',
    );
    expect(harness.room.personsAsked, 0);
    closeTheRoom(container);
  });

  testWidgets('a stretch refused because its take was replaced reads the room '
      'again, and the row is the one the room has now', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    expect(container.read(salaSessionProvider).btTrechos, hasLength(1));

    harness.playback.at = const Duration(seconds: 7);
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    final substituida = harness.room.takeIds.last;
    harness.room
      ..replaceThePart(substituida)
      ..recordThePartAgain(substituida);
    final leituras = harness.room.calls.where((c) => c == 'fetchState').length;
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.calls.where((c) => c == 'fetchState').length,
      greaterThan(leituras),
      reason: 'a recusa não foi lida, só contada',
    );
    expect(
      container.read(salaSessionProvider).btTrechos,
      isEmpty,
      reason: 'a fileira ficava com o trecho da gravação que já não vale',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the recording of a stretch refused because its take was replaced '
    'is dropped, not kept for a resend',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await tocar(tester, pausadaNoToque);
      harness.room.replaceThePart(harness.room.takeIds.last);

      await tocar(tester, terminar);
      final gravada = harness.recorder.lastPath;
      await tester.pump(const Duration(milliseconds: 600));
      await letTheRehearsalReachTheRoom(tester);

      expect(
        container.read(salaSessionProvider).canConfirmTranslation,
        isFalse,
        reason: 'a pendente sai',
      );
      expect(
        harness.recorder.deleted,
        contains(gravada),
        reason: 'a gravação era de uma gravação que já não vale',
      );
      expect(
        harness.room.takesReceived.where((take) => take.kind == 'retro'),
        isEmpty,
        reason: 'guardada, ela subiria como uma tomada da passagem inteira',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a re-read that fails after the refusal is a telling not '
      'understood, and nothing of it goes up later', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.room
      ..replaceThePart(harness.room.takeIds.last)
      ..failStateOnceWith = const NetworkFailed('timeout');

    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    final depois = container.read(salaSessionProvider);
    expect(
      depois.wordlessTelling,
      isTrue,
      reason: 'a releitura que cai é a frase que ela não entendeu',
    );
    expect(depois.btChunkFailures, hasLength(1));
    expect(
      harness.room.takesReceived.where((take) => take.kind != 'ensaio'),
      isEmpty,
      reason: 'a equipe traduz o pedaço de novo; nada sobe sozinho depois',
    );
    closeTheRoom(container);
  });

  testWidgets('a read of the takes that fails after the refusal is a telling '
      'not understood too, and nothing of it goes up later', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.room
      ..replaceThePart(harness.room.takeIds.last)
      ..failTakesWith = const NetworkFailed('timeout');

    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    final depois = container.read(salaSessionProvider);
    expect(
      depois.wordlessTelling,
      isTrue,
      reason: 'a lista de gravações que cai é a frase que ela não entendeu',
    );
    expect(depois.btChunkFailures, hasLength(1));
    expect(
      harness.room.takesReceived.where((take) => take.kind != 'ensaio'),
      isEmpty,
      reason: 'a equipe traduz o pedaço de novo; nada sobe sozinho depois',
    );
    closeTheRoom(container);
  });

  testWidgets('after a refusal for a replaced take the next stretch goes to '
      'the take the room counts now', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.room.replaceThePart('gravacao-1');
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    expect(harness.room.chunksSent, 0, reason: 'a primeira foi recusada');

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.chunkTakes,
      ['gravacao-2'],
      reason: 'o trecho seguinte ia outra vez para a gravação substituída',
    );
    closeTheRoom(container);
  });

  testWidgets('a refusal whose new take cannot be handed over is a telling not '
      'understood at its stretch, instead of dropping it in silence', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, pausadaNoToque);
    harness.room
      ..replaceThePart('gravacao-1')
      ..refuseClipOf.add('gravacao-2');

    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    expect(
      container.read(salaSessionProvider).btChunkFailures,
      hasLength(1),
      reason: 'a sala recusou o trecho e a releitura não veio: é uma falha',
    );
    expect(
      container.read(salaSessionProvider).wordlessTelling,
      isTrue,
      reason: 'a equipe ouve a linha dela e traduz o pedaço de novo',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a slow refusal leaves the re-read its own wait, so the room does '
    'not give up in the middle of it',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        busyCeiling: const Duration(seconds: 2),
      );
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await tocar(tester, pausadaNoToque);
      harness.room
        ..replaceThePart('gravacao-1')
        ..replacedTakeRefusalAfter = const Duration(milliseconds: 1500)
        ..holdNextState();

      await tocar(tester, terminar);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 900));
      harness.room.finishHeldState();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        container.read(salaSessionProvider).needsPerson,
        isFalse,
        reason: 'a espera armada antes do envio estourava no meio da releitura',
      );
      expect(
        container.read(salaSessionProvider).canConfirmTranslation,
        isFalse,
        reason: 'a releitura terminou',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('B3c — sem corte, a tradução vai do cursor até a cabeça', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocar(tester, pausar);
    await tocar(tester, pausado);
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);

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
    await tocar(tester, fimDaGravacao);
    await tocar(tester, fimDaGravacao);

    expect(aceso(tester, conferir), isFalse);
    await tester.tap(byLabel(conferir));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'com uma tradução pendente o disco não pede nada',
    );

    await tocarNoCirculo(tester);

    expect(harness.room.chunkSpans, ['0-10000', '0-10000']);
    expect(faixas(tester), ['1 contadas', '1 contadas']);
    expect(aceso(tester, conferir), isTrue);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.room.playedByTakeSent, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('B5 — a conferida mostra as faixas e aprova', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(faixas(tester), ['2 contadas']);
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
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.takeLandsAfter = const Duration(seconds: 1);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final gravacao = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);

    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(armado(container), [
      'trecho-1',
      true,
      true,
    ], reason: 'o veredito não armava o trecho que nomeou');
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
    expect(armado(container), ['trecho-1', true, true]);
    await tocar(tester, pausar);

    harness.room.verdictUntoldSegmentId = null;
    final vereditos = harness.room.playedByTakeSent.length;
    await tocarNoCirculo(tester);
    expect(harness.room.replacesAsked, isEmpty, reason: 'nada antes do V');

    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');
    expect(
      harness.room.playedByTakeSent,
      hasLength(vereditos),
      reason: 'a sala pedia o veredito sozinha depois da substituição',
    );

    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.playedByTakeSent, hasLength(vereditos + 1));
    closeTheRoom(container);
  });

  Future<ProviderContainer> ateOTrechoNomeado(
    WidgetTester tester,
    SalaHarness harness, {
    bool gravando = true,
  }) async {
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    if (gravando) await tocarNoCirculo(tester);
    return container;
  }

  testWidgets('B7c — o trecho nomeado segue armado enquanto a substituição '
      'viaja', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);

    harness.room.holdNextReplace();
    await tocarNoCirculo(tester);
    expect(armado(container), ['trecho-1', true, true]);

    harness.room.finishHeldReplace();
    await tester.pump(const Duration(milliseconds: 600));
    closeTheRoom(container);
  });

  testWidgets('B7d — uma substituição que cai na rede não sobe sozinha, e é '
      'contada de novo como substituição', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final gravacao = harness.room.takeIds.first;

    harness.room.failReplaceWith = const NetworkFailed('sem rede');
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(armado(container), ['trecho-1', true, true]);

    harness.room.failReplaceWith = null;
    await tester.pump(const Duration(seconds: 5));
    expect(harness.room.replacesAsked, isEmpty, reason: 'nada sobe sozinho');
    await tester.ensureVisible(find.byType(FacilitatorCircle));
    await tester.tap(find.byType(FacilitatorCircle));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(FacilitatorCircle));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');
    closeTheRoom(container);
  });

  testWidgets('B7e — a substituição que chega solta o trecho nomeado, mesmo '
      'com o veredito perdido na rede', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);

    final vereditos = harness.room.playedByTakeSent.length;
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(harness.room.replacesAsked, hasLength(1));
    expect(harness.room.playedByTakeSent, hasLength(vereditos));

    harness.room.failFinishWith = const NetworkFailed('sem rede');
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(harness.room.playedByTakeSent, hasLength(vereditos));

    expect(
      container.read(salaSessionProvider).btRecusa,
      CheckRefusal.checkUnavailable,
      reason: 'a linha dela: não deu para conferir agora',
    );

    harness.room.failFinishWith = null;
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    final capturas = harness.recorder.captures;
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.recorder.captures,
      capturas,
      reason: 'o trecho 1 já foi contado de novo',
    );
    expect(harness.room.replacesAsked, hasLength(1));
    expect(
      harness.room.playedByTakeSent,
      hasLength(vereditos + 1),
      reason: 'o veredito perdido é pedido de novo pelo terminei, e chega',
    );
    closeTheRoom(container);
  });

  testWidgets('B7f — uma captura muda sobre o trecho nomeado não o desarma', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness, gravando: false);
    final gravacao = harness.room.takeIds.first;

    harness.recorder.returnsEmpty = true;
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'uma tomada vazia nunca chama a pessoa',
    );
    expect(armado(container), ['trecho-1', true, true]);

    harness.recorder.returnsEmpty = false;
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2);
    closeTheRoom(container);
  });

  testWidgets('B7g — uma captura sem arquivo sobre o trecho nomeado não o '
      'desarma', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness, gravando: false);
    final gravacao = harness.room.takeIds.first;

    harness.recorder.returnsNothing = true;
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);
    expect(armado(container), ['trecho-1', true, true]);

    harness.recorder.returnsNothing = false;
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2);
    closeTheRoom(container);
  });

  Future<void> confirmarEEsperar(WidgetTester tester) async {
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> contarOutraVez(WidgetTester tester) async {
    await tocarNoCirculo(tester);
  }

  Future<void> perderAResposta(WidgetTester tester, SalaHarness harness) async {
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
  }

  Future<void> falharAoConferir(
    WidgetTester tester,
    SalaHarness harness,
  ) async {
    harness.room.failFinishWith = const Refused('BAD_REQUEST');
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('B7h — a correção com a resposta perdida, contada de novo, '
      'pousa no trecho que o servidor guardou, sem strike', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);

    await perderAResposta(tester, harness);
    final leituras = harness.room.calls.where((c) => c == 'fetchState').length;
    await contarOutraVez(tester);
    await confirmarEEsperar(tester);
    final contadaDeNovo = harness.recorder.lastPath!;

    expect(
      container.read(salaSessionProvider).canConfirmTranslation,
      isFalse,
      reason: 'nada pendente',
    );
    expect(
      harness.room.calls.where((c) => c == 'fetchState').length,
      greaterThan(leituras),
      reason: 'os trechos são lidos de novo na sala',
    );
    final estado = container.read(salaSessionProvider);
    expect(estado.needsPerson, isFalse);
    expect(estado.btPhase, BtPhase.playing);
    expect(estado.voice, VoiceState.invite);
    expect(aceso(tester, conferir), isTrue, reason: 'o círculo está pronto');

    sala.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.playback.played.last,
      contadaDeNovo,
      reason: 'a voz azul do trecho 1 é a explicação que pousou por último',
    );
    expect(
      harness.recorder.deleted,
      isNot(contains(contadaDeNovo)),
      reason: 'o arquivo que pousou é o do trecho, não se apaga',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await falharAoConferir(tester, harness);
    await falharAoConferir(tester, harness);
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'nenhuma recusa do veredito chama a pessoa',
    );
    closeTheRoom(container);
  });

  test('a row that lands after the row before it was withdrawn in the air is '
      'stored, not written over the next index', () async {
    final room = FakeRoom()..refuseTake = 'retro/antes';
    final fila = FakeTakeQueue(room: room);
    final antes = await guardar(fila, 'antes');
    final noAr = await guardar(fila, 'no-ar');
    room.holdNextTake('no-ar');

    final passada = fila.flush();
    await room.untilTakeHeld();
    await fila.withdraw(antes);
    room.finishHeldTake();
    final enviadas = await passada;

    expect(enviadas, 1);
    expect(
      [for (final linha in fila.rows) (linha.id, linha.stored, linha.takeId)],
      [(noAr.id, true, room.takeIds.single)],
      reason: 'a linha que estava no ar pousa pelo que ela é, não pelo lugar',
    );
  });

  test('a row withdrawn while its own send is in the air stays withdrawn, '
      'and the row behind it is left alone', () async {
    final room = FakeRoom();
    final fila = FakeTakeQueue(room: room);
    final noAr = await guardar(fila, 'no-ar');
    final atras = await guardar(fila, 'atras');
    room.holdNextTake('no-ar');

    final passada = fila.flush();
    await room.untilTakeHeld();
    await fila.withdraw(noAr);
    room.finishHeldTake();
    final enviadas = await passada;

    expect(enviadas, 2, reason: 'a sala recebeu os dois envios');
    expect(
      [for (final linha in fila.rows) (linha.id, linha.stored)],
      [(atras.id, true)],
      reason:
          'a linha retirada não volta como enviada, e a de trás não some '
          'debaixo dela',
    );
  });

  test('a send that fails after the row before it was withdrawn counts on its '
      'own row', () async {
    final room = FakeRoom()
      ..refuseTake = 'retro/antes'
      ..unreachableTake = 'retro/no-ar';
    final fila = FakeTakeQueue(room: room);
    final antes = await guardar(fila, 'antes');
    final noAr = await guardar(fila, 'no-ar');
    room.holdNextTake('no-ar');

    final passada = fila.flush();
    await room.untilTakeHeld();
    await fila.withdraw(antes);
    room.finishHeldTake();
    await passada;

    expect(
      [for (final linha in fila.rows) (linha.id, linha.stored, linha.attempts)],
      [(noAr.id, false, 1)],
      reason: 'a falha de quem estava no ar é contada em quem estava no ar',
    );
  });

  test('a row withdrawn in the air is not written over the row that shares its '
      'id under another kind', () async {
    final room = FakeRoom();
    final fila = FakeTakeQueue(room: room);
    const noAr = PendingTake(
      id: '7',
      path: '/gravacoes/no-ar.m4a',
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'no-ar',
    );
    const irma = PendingTake(
      id: '7',
      path: '/gravacoes/irma.m4a',
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'irma',
      takeId: 'gravacao-da-irma',
      stored: true,
    );
    fila.rows.addAll([noAr, irma]);
    room.holdNextTake('no-ar');

    final passada = fila.flush();
    await room.untilTakeHeld();
    await fila.withdraw(noAr);
    room.finishHeldTake();
    await passada;

    expect(
      [for (final linha in fila.rows) (linha.kind, linha.takeId)],
      [('retro', 'gravacao-da-irma')],
      reason: 'a linha de outro tipo com o mesmo número não é a que saiu',
    );
  });

  testWidgets('B7i — a stretch that no longer counts is told by its code and '
      'drops the pending translation, the same refusal again too, and no '
      'number of refusals brings the person sign', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    SalaSessionState estado() => container.read(salaSessionProvider);

    harness.room.failReplaceWith = const Refused(
      'STRETCH_NO_LONGER_COUNTS',
      'Esse trecho já foi trocado por outro',
    );
    await confirmarEEsperar(tester);
    final pendente = harness.recorder.lastPath!;

    expect(estado().canConfirmTranslation, isFalse, reason: 'a pendente sai');
    expect(harness.recorder.deleted, contains(pendente));
    expect(
      [for (final trecho in estado().btTrechos) trecho.segmentId],
      harness.room.segmentIds,
      reason: 'a fileira é a que o servidor tem agora',
    );

    harness.room.verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    await tocarNoCirculo(tester);
    await confirmarEEsperar(tester);
    expect(
      estado().canConfirmTranslation,
      isFalse,
      reason: 'a mesma recusa de novo segue o mesmo caminho',
    );

    await falharAoConferir(tester, harness);
    await falharAoConferir(tester, harness);
    await falharAoConferir(tester, harness);
    expect(
      estado().needsPerson,
      isFalse,
      reason: 'recusa nenhuma, em qualquer número, chama a pessoa',
    );
    closeTheRoom(container);
  });

  testWidgets('B7j — o pouso mantém o cursor e o que a equipe já ouviu', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final ouvidoAntes = harness.room.playedByTakeSent.last;

    await perderAResposta(tester, harness);
    await contarOutraVez(tester);
    await confirmarEEsperar(tester);

    final capturas = harness.recorder.captures;
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.recorder.captures,
      capturas,
      reason: 'o cursor fica depois do chão já contado',
    );
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');

    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      harness.room.playedByTakeSent.last,
      ouvidoAntes,
      reason: 'as partes já ouvidas não são pedidas de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('B7k — a releitura que falha é uma frase não entendida, nada '
      'sai sozinho, e a próxima confirmação pousa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);

    await perderAResposta(tester, harness);
    await contarOutraVez(tester);
    harness.room.failStateOnceWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    final pedidos = harness.room.replaceKeys.length;
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }
    expect(
      container.read(salaSessionProvider).wordlessTelling,
      isTrue,
      reason: 'a releitura que cai é a frase que ela não entendeu',
    );
    expect(
      harness.room.replaceKeys,
      hasLength(pedidos),
      reason: 'nada sai sozinho quando a rede volta',
    );
    expect(armado(container), ['trecho-1', true, true], reason: 'o braço saía');

    await contarOutraVez(tester);
    await confirmarEEsperar(tester);
    final terceira = harness.recorder.lastPath!;
    expect(container.read(salaSessionProvider).canConfirmTranslation, isFalse);
    sala.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.playback.played.last, terceira);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(container);
  });

  testWidgets('B7l — a tradução gravada depois de uma resposta perdida '
      'conta de novo o trecho que pousou', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final gravacao = harness.room.takeIds.first;

    await perderAResposta(tester, harness);
    await contarOutraVez(tester);
    expect(armado(container), [
      'trecho-1',
      true,
      true,
    ], reason: 'a tradução não ficava armada sobre o trecho');

    await confirmarEEsperar(tester);
    final segunda = harness.recorder.lastPath!;
    expect(harness.room.replacesAsked.last, 'trecho-1-v1@$gravacao:0-4000');
    expect(harness.room.replacesComArquivo.last, segunda);
    closeTheRoom(container);
  });

  testWidgets('B7m — sem sucessor na releitura nada pousou: a fileira fica '
      'como o servidor a tem, a pendente sai, e não há strike', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);

    harness.room.recordThePartAgain(harness.room.takeIds.first);
    await confirmarEEsperar(tester);
    final pendente = harness.recorder.lastPath!;

    expect(
      container.read(salaSessionProvider).btTrechos,
      isEmpty,
      reason: 'a tradução recomeçada não deixa fileira velha na tela',
    );
    expect(container.read(salaSessionProvider).canConfirmTranslation, isFalse);
    expect(harness.recorder.deleted, contains(pendente));

    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    for (var falha = 0; falha < 2; falha++) {
      sala.retroTap();
      await tester.pump(const Duration(milliseconds: 300));
      await confirmarEEsperar(tester);
    }
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'duas falhas comuns depois da recusa são o primeiro e o segundo '
          'strike',
    );
    closeTheRoom(container);
  });

  testWidgets('the read after a correction refused because the stretch no '
      'longer counts never raises the person sign, though the server says it '
      'needs a person', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.recordThePartAgain(harness.room.takeIds.first);
    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    final lidas = stateReads(harness);
    await confirmarEEsperar(tester);

    expect(stateReads(harness), greaterThan(lidas), reason: 'a sala releu');
    expect(read().needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
    final capturas = harness.recorder.captures;
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.recorder.captures,
      greaterThan(capturas),
      reason: 'o círculo segue gravando',
    );
    closeTheRoom(container);
  });

  testWidgets('the read after a verdict never raises the person sign, though '
      'the server says it needs a person', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1'
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'uma leitura nunca levanta o sinal da pessoa',
    );
    expect(harness.room.personsAsked, 0);
    closeTheRoom(container);
  });

  testWidgets('B7o — a segunda gravação que cai na rede depois de uma resposta '
      'perdida também não foi entendida, e a terceira conta de novo o trecho '
      'que pousou', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final gravacao = harness.room.takeIds.first;

    await perderAResposta(tester, harness);
    await contarOutraVez(tester);
    harness.room.failReplaceWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    harness.room.failReplaceWith = null;
    final pedidos = harness.room.replaceKeys.length;
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }
    expect(
      container.read(salaSessionProvider).wordlessTelling,
      isTrue,
      reason: 'a segunda que a rede perdeu também é a não entendida',
    );
    expect(
      harness.room.replaceKeys,
      hasLength(pedidos),
      reason: 'a segunda não sai sozinha quando a rede volta',
    );
    expect(armado(container), [
      'trecho-1',
      true,
      true,
    ], reason: 'a tradução não ficava armada sobre o trecho');

    await contarOutraVez(tester);
    await confirmarEEsperar(tester);
    final terceira = harness.recorder.lastPath!;
    expect(harness.room.replacesAsked.last, 'trecho-1-v1@$gravacao:0-4000');
    expect(harness.room.replacesComArquivo.last, terceira);
    closeTheRoom(container);
  });

  testWidgets('B7p — o sucessor é o que está na gravação e na fatia do '
      'trecho recusado, não outro trecho contado na mesma fatia', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final [primeira, segunda] = harness.room.takeIds.take(2).toList();

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    int ondeEsta(String gravacao) => container
        .read(salaSessionProvider)
        .btTrechos
        .indexWhere(
          (trecho) => trecho.takeId == gravacao && trecho.from == Duration.zero,
        );
    final daPrimeira = container
        .read(salaSessionProvider)
        .btTrechos[ondeEsta(primeira)]
        .retroPath;
    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = harness.room.segments
          .firstWhere((s) => s.takeId == segunda && s.startsMs == 0)
          .segmentId;
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    await tocarNoCirculo(tester);

    await perderAResposta(tester, harness);
    await contarOutraVez(tester);
    await confirmarEEsperar(tester);
    final contadaNoServidor = harness.recorder.lastPath!;

    sala.ouvirOTrechoContado(ondeEsta(segunda));
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.playback.played.last, contadaNoServidor);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    sala.ouvirOTrechoContado(ondeEsta(primeira));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.playback.played.last,
      daPrimeira,
      reason:
          'o trecho da mesma fatia na outra parte segue com a própria '
          'explicação',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(container);
  });

  testWidgets('B7q — uma gravação que o servidor não captou não prova que a '
      'resposta perdida antes dela não vai pousar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final gravacao = harness.room.takeIds.first;

    harness.room.loseTheNextReplaceAnswerAndLandItLaterWith =
        const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    await contarOutraVez(tester);
    harness.room.failReplaceWith = const Refused('BAD_REQUEST');
    await confirmarEEsperar(tester);
    final segunda = harness.recorder.lastPath!;
    expect(
      container.read(salaSessionProvider).wordlessTelling,
      isTrue,
      reason: 'a recusa é um pedaço não entendido',
    );

    harness.room
      ..failReplaceWith = null
      ..landTheLostReplace();
    await contarOutraVez(tester);
    await confirmarEEsperar(tester);
    final terceira = harness.recorder.lastPath!;

    expect(
      container.read(salaSessionProvider).canConfirmTranslation,
      isFalse,
      reason: 'a perdida pousou, e a contada de novo pousou sobre ela',
    );
    expect(harness.room.replacesAsked, [
      'trecho-1@$gravacao:0-4000',
      'trecho-1-v1@$gravacao:0-4000',
    ]);
    expect(harness.room.replacesComArquivo.last, terceira);
    expect(harness.room.replacesComArquivo, isNot(contains(segunda)));
    closeTheRoom(container);
  });

  testWidgets('B3d — uma substituição recusada é um pedaço não entendido', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    final gravacao = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);

    harness.room
      ..verdictChecked = false
      ..verdictUntoldSegmentId = 'trecho-1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    await tocarNoCirculo(tester);
    harness.room.failReplaceWith = const Refused('BAD_REQUEST');
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 600));
    final capturas = harness.recorder.captures;

    expect(container.read(salaSessionProvider).wordlessTelling, isTrue);

    harness.room.failReplaceWith = null;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked.last, 'trecho-1@$gravacao:0-4000');
    expect(harness.room.chunksSent, 2, reason: 'nenhum trecho novo');
    expect(
      harness.recorder.captures,
      capturas + 1,
      reason: 'o toque depois da recusa mandava a mesma gravação de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('B1b — o trecho pendente de uma parte anterior volta para a '
      'sua parte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final primeira = harness.room.takeIds.first;

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await contarAteOFimDaParte(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [primeira]
      ..listeningUnheardTakeIds = [primeira];
    await tester.ensureVisible(byLabel(conferir));
    await tester.tap(byLabel(conferir));
    await tester.pump(const Duration(milliseconds: 600));
    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect((estado.btParte, estado.btCursor), (0, cabeca));
    expect(faixas(tester), ['1 contadas', '1 contadas']);
    closeTheRoom(container);
  });

  testWidgets('B3e — o círculo com o clipe tocando grava até a cabeça', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);

    expect(harness.room.chunkSpans, ['0-4000']);
    closeTheRoom(container);
  });

  testWidgets('B4b — o disco fica apagado enquanto sobra chão por contar na '
      'última parte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).canConfirmTranslation, isFalse);
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
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
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
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(container.read(salaSessionProvider).btChunkFailures, isNotEmpty);
    final gravada = harness.recorder.lastPath;
    container.read(salaSessionProvider.notifier).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, contains(gravada));
    closeTheRoom(container);
  });

  testWidgets('B10 — a tela segue o quadro dela, com o título e a linha acima '
      'das faixas', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 1180)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(PartStrips),
            ),
          )
          .dy,
      169,
    );
    expect(
      tester.getTopLeft(byLabel(ouvindo)),
      const Offset(335, 336.5),
      reason:
          'o círculo ficava 48 px abaixo, sob uma linha de pausa que a tela '
          'dela não desenha sem pausa',
    );
    expect(
      tester.getTopLeft(byLabel(pausar)),
      const Offset(16, 537),
      reason:
          'o botão ficava à esquerda da tesoura e da confirmação, que os três '
          'toques tiraram; agora só a linha dela, que quebra, fica ao lado e o '
          'leva até a margem',
    );
    expect(tester.getTopLeft(byLabel(conferir)), const Offset(309.8, 653));
    closeTheRoom(container);
  });

  testWidgets('B10b — o círculo tem os 150 px do dela numa tela menor', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(768, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

    expect(tester.getRect(byLabel(ouvindo)).size, const Size(150, 150));
    final pilula = tester.getRect(byLabel(conferir)).size;
    expect(pilula.width, closeTo(200.4, 0.01));
    expect(pilula.height, closeTo(48.6, 0.01));
    closeTheRoom(container);
  });

  testWidgets('B8 — os rótulos falam a língua da sala', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

    expect(byLabel('listening to your recording…'), findsOneWidget);
    expect(byLabel('Pause'), findsOneWidget);
    expect(byLabel('done'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PartStrips),
        matching: find.text('part 1'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(byLabel('Pause'));
    await tester.tap(byLabel('Pause'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Listen'), findsOneWidget);

    harness.playback.at = cabeca;
    await tester.tap(
      byLabel('paused — tap the circle to mark where the sentence ends'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);
    expect(byLabel('Tap when you finish'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets(
    'the retro circle holding a translation it just heard waits in english, '
    'not in portuguese',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
      final container = await entrarNaTraducao(tester, harness);

      harness.playback.at = cabeca;
      await tester.pump(passaDoCursor);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      harness.recorder.holdNextStop();
      await tester.tap(byLabel('Tap when you finish'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(byLabel('One moment'), findsOneWidget);
      expect(
        byLabel('Um instante'),
        findsNothing,
        reason:
            'o círculo do retro pensando dizia "Um instante" a uma sala em '
            'inglês',
      );

      harness.recorder.finishStop();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(container);
    },
  );

  testWidgets('B9 — depois do corte, ouvir toca o trecho do cursor ao corte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await _tocarNaTraducao(tester, ouvir);

    expect(harness.playback.ranges.last, '0-4000');
    expect(harness.playback.sounding, isTrue);
    closeTheRoom(container);
  });
}
