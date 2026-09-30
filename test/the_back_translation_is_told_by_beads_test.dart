import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const parte = Duration(seconds: 10);
const cabeca = Duration(seconds: 4);

/// Long enough for the part to have run past the cursor, with no gesture of its own.
const passaDoCursor = Duration(seconds: 1);

const gravar = 'Tocar para gravar a tradução deste trecho';
const terminar = 'Tocar ao terminar';
const ouvir = 'Ouvir';
const pausar = 'Pausar';
const tesoura = 'Cortar aqui';
const confirmar = 'Confirmar a tradução e seguir';
const conferir = 'Conferir a tradução';
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

    harness.room.failChunkWith = const Refused('BAD_REQUEST');
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

  Future<ProviderContainer> ateOTrechoNomeado(
    WidgetTester tester,
    SalaHarness harness, {
    bool gravando = true,
  }) async {
    final container = await entrarNaTraducao(tester, harness, partes: 1);
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
    if (gravando) await gravarATraducao(tester);
    return container;
  }

  testWidgets('B7c — o trecho nomeado segue armado enquanto a substituição '
      'viaja', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);

    harness.room.holdNextReplace();
    await tocar(tester, confirmar);
    expect(contas(tester), ['solid com anel', 'solid']);

    harness.room.finishHeldReplace();
    await tester.pump(const Duration(milliseconds: 600));
    closeTheRoom(container);
  });

  testWidgets('B7d — uma substituição que cai na rede é tentada de novo como '
      'substituição', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final gravacao = harness.room.takeIds.first;

    harness.room.failReplaceWith = const NetworkFailed('sem rede');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));
    expect(contas(tester), ['solid com anel', 'solid']);

    harness.room.failReplaceWith = null;
    container.read(salaSessionProvider.notifier).retryNow();
    await tester.pump(const Duration(milliseconds: 600));
    await tocar(tester, confirmar);
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
    harness.room.failFinishWith = const NetworkFailed('sem rede');
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));
    expect(harness.room.replacesAsked, hasLength(1));
    expect(harness.room.playedByTakeSent, hasLength(vereditos));

    harness.room.failFinishWith = null;
    container.read(salaSessionProvider.notifier).retryNow();
    await tester.pump(const Duration(milliseconds: 600));
    final capturas = harness.recorder.captures;
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    await container.read(salaSessionProvider.notifier).confirmarTraducao();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.recorder.captures,
      capturas,
      reason: 'o trecho 1 já foi contado de novo',
    );
    expect(harness.room.replacesAsked, hasLength(1));

    expect(aceso(tester, conferir), isTrue);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      harness.room.playedByTakeSent,
      hasLength(vereditos + 1),
      reason: 'o veredito perdido é pedido de novo e chega',
    );
    closeTheRoom(container);
  });

  testWidgets('B7f — uma captura muda sobre o trecho nomeado não o desarma', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness, gravando: false);
    final gravacao = harness.room.takeIds.first;
    final sala = container.read(salaSessionProvider.notifier);

    harness.recorder.returnsEmpty = true;
    await tocar(tester, gravar);
    await tocar(tester, terminar);
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    harness.room.theDeskAttended();
    sala.resolveWithPerson();
    await tester.pump(const Duration(milliseconds: 600));
    expect(contas(tester), ['solid com anel', 'solid']);

    harness.recorder.returnsEmpty = false;
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
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
    await tocar(tester, gravar);
    await tocar(tester, terminar);
    expect(contas(tester), ['solid com anel', 'solid']);

    harness.recorder.returnsNothing = false;
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    expect(harness.room.chunksSent, 2);
    closeTheRoom(container);
  });

  Future<void> confirmarEEsperar(WidgetTester tester) async {
    await tocar(tester, confirmar);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> falharAoConferir(
    WidgetTester tester,
    SalaHarness harness,
  ) async {
    harness.room.failFinishWith = const Refused('BAD_REQUEST');
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('B7h — a correção guardada com a resposta perdida pousa na '
      'recusa seguinte, sem strike', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    final contadaNoServidor = harness.room.replacesComArquivo.single;
    final leituras = harness.room.calls.where((c) => c == 'fetchState').length;

    await confirmarEEsperar(tester);

    expect(aceso(tester, confirmar), isFalse, reason: 'nada pendente');
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
      contadaNoServidor,
      reason: 'a voz azul do trecho 1 é a explicação que o servidor guardou',
    );
    expect(
      harness.recorder.deleted,
      isNot(contains(contadaNoServidor)),
      reason: 'o arquivo que pousou é o do trecho, não se apaga',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await falharAoConferir(tester, harness);
    await falharAoConferir(tester, harness);
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'duas falhas comuns depois do pouso são o primeiro e o segundo '
          'strike, não o segundo e o terceiro',
    );
    closeTheRoom(container);
  });

  testWidgets('B7h2 — a correção guardada com a resposta perdida sai da fila '
      'quando pousa na recusa seguinte', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final fila = harness.takes as FakeTakeQueue;

    harness.room.refuseTake = 'retro/${KeptScope.whole}';
    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    await letTheRehearsalReachTheRoom(tester);
    final contadaNoServidor = harness.room.replacesComArquivo.single;
    expect(
      [
        for (final linha in fila.rows)
          if (linha.path == contadaNoServidor && !linha.stored) linha.kind,
      ],
      ['retro'],
      reason: 'a resposta perdida guarda a correção na fila',
    );

    await confirmarEEsperar(tester);
    await letTheRehearsalReachTheRoom(tester);

    expect(
      fila.rows.where((linha) => linha.path == contadaNoServidor),
      isEmpty,
      reason:
          'a correção já pousou no trecho; na fila ela subiria de novo como '
          'uma tomada da passagem inteira',
    );
    closeTheRoom(container);
  });

  testWidgets('B7i — a stretch that no longer counts is told by its code, '
      'drops the pending translation, and is never a strike, not even the '
      'same refusal again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    SalaSessionState estado() => container.read(salaSessionProvider);
    final pendente = estado().btTraducaoPendente!;

    harness.room.failReplaceWith = const Refused(
      'STRETCH_NO_LONGER_COUNTS',
      'Esse trecho já foi trocado por outro',
    );
    await confirmarEEsperar(tester);

    expect(aceso(tester, confirmar), isFalse, reason: 'a pendente sai');
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
    await gravarATraducao(tester);
    await confirmarEEsperar(tester);
    expect(
      aceso(tester, confirmar),
      isFalse,
      reason: 'a mesma recusa de novo segue o mesmo caminho',
    );

    await falharAoConferir(tester, harness);
    await falharAoConferir(tester, harness);
    expect(
      estado().needsPerson,
      isFalse,
      reason:
          'duas falhas comuns depois de duas recusas iguais são o primeiro e o '
          'segundo strike: a recusa nunca conta',
    );
    await falharAoConferir(tester, harness);
    expect(
      estado().needsPerson,
      isTrue,
      reason: 'e a terceira falha comum chama',
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

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    await confirmarEEsperar(tester);

    final capturas = harness.recorder.captures;
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

  testWidgets('B7k — a releitura que falha não solta nada, e a próxima '
      'confirmação pousa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    final contadaNoServidor = harness.room.replacesComArquivo.single;

    harness.room.failStateOnceWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    expect(aceso(tester, confirmar), isTrue, reason: 'a pendente fica');
    expect(contas(tester), ['solid com anel', 'solid'], reason: 'o braço fica');

    await confirmarEEsperar(tester);
    expect(aceso(tester, confirmar), isFalse);
    sala.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.playback.played.last, contadaNoServidor);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(container);
  });

  testWidgets('B7l — a tradução gravada depois de uma resposta perdida '
      'conta de novo o trecho que pousou', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final gravacao = harness.room.takeIds.first;

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    final primeira = harness.room.replacesComArquivo.single;
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    final segunda = container.read(salaSessionProvider).btTraducaoPendente!;
    expect(segunda, isNot(primeira));

    await confirmarEEsperar(tester);
    expect(
      aceso(tester, confirmar),
      isTrue,
      reason: 'a segunda segue pendente',
    );
    expect(contas(tester), [
      'solid com anel',
      'solid',
    ], reason: 'armada sobre o sucessor');

    sala.ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.playback.played.last,
      container.read(salaSessionProvider).partes.first.path,
      reason:
          'o tablet não tem mais a primeira e nunca toca um arquivo que o '
          'servidor não guarda para o trecho: toca a língua materna',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await confirmarEEsperar(tester);
    expect(harness.room.replacesAsked.last, 'trecho-1-v1@$gravacao:0-4000');
    expect(harness.room.replacesComArquivo.last, segunda);
    closeTheRoom(container);
  });

  testWidgets('B7m — sem sucessor na releitura nada pousou: a fileira fica '
      'como o servidor a tem, a pendente sai, e não há strike', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final pendente = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room.recordThePartAgain(harness.room.takeIds.first);
    await confirmarEEsperar(tester);

    expect(
      container.read(salaSessionProvider).btTrechos,
      isEmpty,
      reason: 'a tradução recomeçada não deixa fileira velha na tela',
    );
    expect(aceso(tester, confirmar), isFalse);
    expect(harness.recorder.deleted, contains(pendente));

    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    for (var falha = 0; falha < 2; falha++) {
      sala.retroTap();
      await tester.pump(const Duration(milliseconds: 300));
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
      'longer counts applies the halt and the warning it carries', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.recordThePartAgain(harness.room.takeIds.first);
    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    await confirmarEEsperar(tester);

    expect(read().needsPerson, isTrue, reason: 'a releitura trouxe a parada');
    expect(
      harness.room.personsAsked,
      0,
      reason: 'uma parada lida não é um novo pedido de pessoa',
    );
    final capturas = harness.recorder.captures;
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.recorder.captures,
      capturas,
      reason: 'todo gesto fecha sob a parada',
    );

    harness.room.serverHalt = HaltKind.warning;
    await tester.pump(const Duration(milliseconds: 300));
    expect(read().needsPerson, isFalse);
    expect(read().warning, isTrue, reason: 'a segunda leitura trouxe o aviso');
    final lidas = stateReads(harness);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      stateReads(harness),
      greaterThan(lidas),
      reason: 'a vigia segue armada sob o aviso',
    );
    closeTheRoom(container);
  });

  testWidgets('the read after a verdict applies the halt it carries, as one '
      'the room only read', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
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
      isTrue,
      reason: 'a releitura dos trechos trouxe a parada, e ela vale inteira',
    );
    expect(
      harness.room.personsAsked,
      0,
      reason: 'uma parada lida não é um novo pedido de pessoa',
    );
    closeTheRoom(container);
  });

  testWidgets('B7n — outra falha entre duas recusas quebra o "em seguida"', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    await confirmarEEsperar(tester);

    harness.room.verdictUntoldSegmentId = 'trecho-1-v1';
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.verdictUntoldSegmentId = null;
    await gravarATraducao(tester);

    harness.room.failReplaceWith = const Refused('BAD_REQUEST');
    await confirmarEEsperar(tester);
    harness.room.failReplaceWith = const Refused(
      RefusalCode.stretchNoLongerCounts,
    );
    await confirmarEEsperar(tester);
    harness.room.failReplaceWith = null;
    expect(
      aceso(tester, confirmar),
      isFalse,
      reason: 'a recusa solta a pendente em vez de guardá-la como strike',
    );

    await falharAoConferir(tester, harness);
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'a recusa depois de outra falha não é "em seguida": só a falha e '
          'a conferência contam. A recusa sobre um trecho que ainda vale é '
          'injetada; o servidor de hoje não a produz',
    );
    closeTheRoom(container);
  });

  testWidgets('B7o — com duas gravações sem resposta, a recusa não sabe qual '
      'pousou e conta de novo com a pendente', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOTrechoNomeado(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final gravacao = harness.room.takeIds.first;

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    final segunda = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room.failReplaceWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    harness.room.failReplaceWith = null;
    await confirmarEEsperar(tester);

    expect(
      aceso(tester, confirmar),
      isTrue,
      reason: 'a segunda segue pendente',
    );
    expect(contas(tester), [
      'solid com anel',
      'solid',
    ], reason: 'armada sobre o sucessor');

    await confirmarEEsperar(tester);
    expect(harness.room.replacesAsked.last, 'trecho-1-v1@$gravacao:0-4000');
    expect(harness.room.replacesComArquivo.last, segunda);
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
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
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
    await gravarATraducao(tester);

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    final contadaNoServidor = harness.room.replacesComArquivo.single;
    await confirmarEEsperar(tester);

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
    final sala = container.read(salaSessionProvider.notifier);
    final gravacao = harness.room.takeIds.first;

    harness.room.loseTheNextReplaceAnswerAndLandItLaterWith =
        const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    final segunda = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room.replaceCaptured = false;
    await confirmarEEsperar(tester);
    harness.room
      ..replaceCaptured = true
      ..landTheLostReplace()
      ..failReplaceWith = const NetworkFailed('timeout');
    await confirmarEEsperar(tester);
    harness.room.failReplaceWith = null;
    await confirmarEEsperar(tester);

    expect(
      aceso(tester, confirmar),
      isTrue,
      reason: 'a segunda segue pendente',
    );
    expect(contas(tester), [
      'solid com anel',
      'solid',
    ], reason: 'armada sobre o sucessor que a primeira deixou');

    await confirmarEEsperar(tester);
    expect(harness.room.replacesAsked.last, 'trecho-1-v1@$gravacao:0-4000');
    expect(harness.room.replacesComArquivo.last, segunda);
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

    harness.room.failReplaceWith = const Refused('BAD_REQUEST');
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
    await tester.pump(passaDoCursor);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);

    expect(harness.room.chunkSpans, ['0-4000']);
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

    harness.room.failChunkWith = const Refused('BAD_REQUEST');
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
    await tester.pump(passaDoCursor);
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
    await tester.pump(passaDoCursor);
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
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(BeadRow),
            ),
          )
          .dy,
      86,
    );
    expect(tester.getTopLeft(byLabel(gravar)), const Offset(330, 456));
    expect(tester.getTopLeft(byLabel(pausar)), const Offset(296, 680));
    expect(tester.getTopLeft(byLabel(tesoura)), const Offset(380, 680));
    expect(tester.getTopLeft(byLabel(confirmar)), const Offset(464, 680));
    expect(tester.getTopLeft(byLabel(conferir)), const Offset(371, 798));
    closeTheRoom(container);
  });

  testWidgets('B10b — o círculo tem 160 px numa tela menor', (tester) async {
    tester.view
      ..physicalSize = const Size(768, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

    expect(tester.getRect(byLabel(gravar)).size, const Size(160, 160));
    expect(tester.getRect(byLabel(conferir)).size, const Size(78, 78));
    closeTheRoom(container);
  });

  testWidgets('B8 — os rótulos falam a língua da sala', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tester.pump(passaDoCursor);

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

  testWidgets(
    'the retro circle holding a translation it just heard waits in english, '
    'not in portuguese',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
      final container = await entrarNaTraducao(tester, harness);

      harness.playback.at = cabeca;
      await tester.pump(passaDoCursor);
      await tester.tap(byLabel("Tap to record this stretch's translation"));
      await tester.pump(const Duration(milliseconds: 300));
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
