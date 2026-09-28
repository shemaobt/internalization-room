import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const continuarOEnsaio = 'Continuar o ensaio';
const irParaARetro = 'Ir para a tradução';
const umaParteInteira = Duration(seconds: 30);

List<String?> gravacoesDe(SalaSessionState state) => [
  for (final take in state.keptTakes) take.takeId,
];

List<String?> trechosDe(SalaSessionState state) => [
  for (final trecho in state.btTrechos) trecho.segmentId,
];

/// How far from nought the reported listening reaches without a gap.
int ouvidoAteMs(List<List<int>> ranges) {
  final spans = List.of(ranges)..sort((a, b) => a[0].compareTo(b[0]));
  var ate = 0;
  for (final span in spans) {
    if (span[0] > ate) break;
    if (span[1] > ate) ate = span[1];
  }
  return ate;
}

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

/// Ask, rather than guess, when the disk or the room has done its part.
/// A tablet closed on the rehearsal of a passage told back in three parts, and opened
/// again on it: the rehearsal is on disk, the ledger says the rehearsal, and the room
/// holds one stretch per part, each from nought to [traduzidasAte]. The stretches named in
/// [porTraduzir] are ones the room says nobody has explained yet.
Future<ProviderContainer> aRetomadaNoEnsaio(
  SalaHarness harness, {
  required List<int> traduzidasAte,
  Set<String> porTraduzir = const {},
}) async {
  final home = Directory.systemTemp.createTempSync('sala-resto-da-historia');
  addTearDown(() => home.deleteSync(recursive: true));
  final gravadas = [
    for (var parte = 1; parte <= traduzidasAte.length; parte++)
      KeptTake(
        scopeId: KeptScope.parte(parte),
        path: (File(
          '${home.path}/p$parte.m4a',
        )..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'antiga-$parte',
      ),
  ];
  await harness.emAberto.remember(
    'Ruth',
    'P01',
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: gravadas,
    ),
  );
  harness.room.retroSoFar = BackTranslationProgress(
    segments: [
      for (var parte = 1; parte <= traduzidasAte.length; parte++)
        SegmentView(
          segmentId: 'trecho-$parte',
          takeId: 'antiga-$parte',
          startsMs: 0,
          endsMs: traduzidasAte[parte - 1],
          told: !porTraduzir.contains('trecho-$parte'),
        ),
    ],
  );
  harness.playback.length = umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  return container;
}

/// Record one more part over the real outbox, and wait for the room to name it.
Future<KeptTake> gravarMaisUmaParte(ProviderContainer container) async {
  final notifier = container.read(salaSessionProvider.notifier);
  final antes = container.read(salaSessionProvider).keptTakes.length;
  notifier.ensaioTap();
  await waitFor(
    'a gravação da parte começar',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
  );
  notifier.ensaioTap();
  await waitFor(
    'a gravação da parte terminar',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
  );
  notifier.takeKeep();
  await waitFor('a sala nomear a parte nova', () {
    final takes = container.read(salaSessionProvider).keptTakes;
    return takes.length == antes + 1 && takes.last.takeId != null;
  });
  return container.read(salaSessionProvider).keptTakes.last;
}

/// Record one part and keep it: the two taps are start and stop, the way the team taps
/// the circle, and the keep waits for the room to name the recording.
Future<void> gravarUmaParte(
  WidgetTester tester,
  SalaSessionNotifier notifier,
) async {
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
}

/// Tell the part in the air back whole, from its beginning to its end, then let it finish.
Future<void> traduzirAParteInteira(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.playback.at = umaParteInteira;
  notifier.cortarTrecho();
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A team that recorded the passage in three parts, told every part back whole and got
/// everything right — and did not record the end of the story. The analyst says a part
/// is missing and cannot place it in any stretch, so the finding carries no address.
///
/// Every step is a verb the team has on the screen; nothing is written into the session
/// by hand.
Future<ProviderContainer> aHistoriaSemOFim(
  WidgetTester tester,
  SalaHarness harness, {
  String? ondeFalta,
}) async {
  harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingSegmentId = ondeFalta;
  harness.playback.length = umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var parte = 0; parte < 3; parte++) {
    await gravarUmaParte(tester, notifier);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  for (var parte = 0; parte < 3; parte++) {
    await traduzirAParteInteira(tester, harness, container);
    if (parte < 2) {
      notifier.ouvirGravacao();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets('a falta sem endereço não apaga nada, nem no app nem na sala', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(tester, harness);

    final antes = container.read(salaSessionProvider);
    expect(antes.btPhase, BtPhase.findings);
    expect(
      antes.btFindingTrecho,
      isNull,
      reason: 'a falta está depois do último trecho: o achado não tem endereço',
    );
    expect(gravacoesDe(antes), hasLength(3));
    expect(trechosDe(antes), ['trecho-1', 'trecho-2', 'trecho-3']);
    final naSala = List.of(harness.room.segmentIds);
    final pedidos = harness.room.calls.length;

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 400));

    final depois = container.read(salaSessionProvider);
    expect(
      gravacoesDe(depois),
      gravacoesDe(antes),
      reason:
          'as tomadas são o trabalho da equipe; voltar ao ensaio não as apaga',
    );
    expect(depois.takes, antes.takes);
    expect(
      trechosDe(depois),
      trechosDe(antes),
      reason: 'os trechos já contados e certos ficam contados',
    );
    expect(
      harness.room.calls.sublist(pedidos),
      isNot(contains('replaceSegment')),
    );
    expect(
      harness.room.segmentIds,
      naSala,
      reason: 'a sala segue guardando exatamente os mesmos trechos',
    );
  });

  testWidgets(
    'a equipe volta ao ensaio e a tomada nova se acrescenta às antigas',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await aHistoriaSemOFim(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      final antigas = gravacoesDe(container.read(salaSessionProvider));

      await tester.tap(byLabel(continuarOEnsaio));
      await tester.pump(const Duration(milliseconds: 400));

      var agora = container.read(salaSessionProvider);
      expect(agora.stage, SalaStage.ensaio);
      expect(
        agora.ensaio,
        EnsaioStatus.idle,
        reason: 'o círculo está livre para gravar',
      );
      expect(gravacoesDe(agora), antigas);

      await gravarUmaParte(tester, notifier);

      agora = container.read(salaSessionProvider);
      expect(
        gravacoesDe(agora),
        hasLength(4),
        reason: 'a tomada nova é o fim da história, não a história de novo',
      );
      expect(
        gravacoesDe(agora).sublist(0, 3),
        antigas,
        reason: 'e as três anteriores continuam onde estavam',
      );
      expect(agora.takes, 4);
      expect(
        agora.keptTakes.last.takeId,
        isNotNull,
        reason: 'a tomada nova chega à sala como as outras chegaram',
      );
    },
  );

  testWidgets('a cobertura da conversa segue guardada ao voltar ao ensaio', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.nextCoverage = coverage(engaged: 5, surfaced: 7);
    final container = await aHistoriaSemOFim(tester, harness);
    final antes = container.read(salaSessionProvider);
    expect(antes.coverage.engaged, 5);

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      tester
          .widget<BeadRow>(
            find.descendant(
              of: find.byType(EnsaioView),
              matching: find.byType(BeadRow),
            ),
          )
          .entries,
      hasLength(3),
      reason: 'uma conta por tomada guardada, no ensaio, como antes de contar',
    );
    expect(
      find.byType(ColarOverlay),
      findsNothing,
      reason:
          'o progresso do ensaio é a fileira de contas dos pedaços; o '
          'colar da conversa não desenha ali',
    );
    final depois = container.read(salaSessionProvider);
    expect(
      depois.coverage.engaged,
      antes.coverage.engaged,
      reason: 'o colar da passagem não perde o que a conversa já preencheu',
    );
    expect(depois.coverage.surfaced, antes.coverage.surfaced);
  });

  testWidgets('ao avançar, só a parte nova é contada', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final antigas = trechosDe(container.read(salaSessionProvider));
    final contadosAntes = harness.room.chunkTakes.length;

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 400));
    await gravarUmaParte(tester, notifier);
    final nova = container.read(salaSessionProvider).keptTakes.last;

    await tester.tap(byLabel(irParaARetro));
    await tester.pump(const Duration(milliseconds: 400));

    var agora = container.read(salaSessionProvider);
    expect(agora.stage, SalaStage.retro);
    expect(agora.btPhase, BtPhase.playing);
    expect(
      harness.playback.played.last,
      nova.path,
      reason: 'a equipe é levada à parte nova, não ao começo da história',
    );
    expect(
      trechosDe(agora),
      antigas,
      reason: 'os três trechos antigos seguem contados; nenhum é recortado',
    );

    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));

    agora = container.read(salaSessionProvider);
    expect(
      harness.room.chunkTakes.sublist(contadosAntes),
      [nova.takeId],
      reason:
          'um trecho só, sobre a gravação nova; os antigos não são reenviados',
    );
    expect(harness.room.chunkSpans.sublist(contadosAntes), ['0-12000']);
    expect(harness.room.replacesAsked, isEmpty);
    expect(trechosDe(agora).sublist(0, 3), antigas);
    expect(agora.btTrechos, hasLength(4));

    // The room reads the passage only over evidence that the rehearsal was heard end to
    // end. The three parts the team stepped over were heard in the round before, when
    // they were told back; a report of this round's listening alone would have the room
    // send the team back to hear the whole story again.
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.room.playedByTakeSent.last,
      hasLength(4),
      reason: 'as três partes antigas e a nova, uma entrada cada',
    );
    expect(
      [
        for (final parte in harness.room.playedByTakeSent.last)
          ouvidoAteMs(parte['played_ranges']! as List<List<int>>),
      ],
      List.filled(4, umaParteInteira.inMilliseconds),
      reason:
          'o que a sala recebe como ouvido cobre cada parte inteira, sem '
          'buraco, senão o portão dela manda ouvir tudo de novo',
    );
    expect([
      for (final parte in harness.room.playedByTakeSent.last)
        parte['clip_duration_ms'],
    ], List.filled(4, umaParteInteira.inMilliseconds));
  });

  test(
    'sair e reentrar depois de voltar ao ensaio também conta só o novo',
    () async {
      final harness = SalaHarness();
      final container = await aRetomadaNoEnsaio(
        harness,
        traduzidasAte: [30000, 30000, 30000],
      );
      final notifier = container.read(salaSessionProvider.notifier);
      expect(
        trechosDe(container.read(salaSessionProvider)),
        ['trecho-1', 'trecho-2', 'trecho-3'],
        reason:
            'a retomada no ensaio traz de volta o que a sala guarda como '
            'contado, senão o avanço seguinte recomeça do zero',
      );

      final nova = await gravarMaisUmaParte(container);

      notifier.startRetro();
      await waitFor(
        'a retro começar a tocar',
        () => harness.playback.played.isNotEmpty,
      );

      expect(
        harness.playback.played.last,
        nova.path,
        reason: 'a equipe é levada à parte nova, não ao começo da história',
      );

      harness.playback.at = const Duration(seconds: 12);
      notifier.cortarTrecho();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await waitFor(
        'o trecho chegar à sala',
        () => harness.room.chunksSent == 1,
      );

      expect(
        harness.room.chunkTakes,
        [nova.takeId],
        reason: 'os três trechos que a sala guarda não são contados de novo',
      );
      expect(harness.room.chunkSpans, ['0-12000']);
    },
  );

  test('uma parte contada até pouco antes do fim conta como inteira', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000, 29500],
    );
    final nova = await gravarMaisUmaParte(container);

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a retro começar a tocar',
      () => harness.playback.played.isNotEmpty,
    );

    expect(
      harness.playback.played.last,
      nova.path,
      reason:
          'o último corte de uma parte é feito onde o clipe parou, e a '
          'posição lida no fim pode ficar um pouco antes da medida do arquivo',
    );
  });

  test('uma parte contada só pela metade é retomada, não pulada', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 25000, 30000],
    );
    final notifier = container.read(salaSessionProvider.notifier);
    await gravarMaisUmaParte(container);

    notifier.startRetro();
    await waitFor(
      'a retro começar a tocar',
      () => harness.playback.played.isNotEmpty,
    );

    final partes = container.read(salaSessionProvider).keptTakes;
    expect(
      harness.playback.played.last,
      partes[1].path,
      reason: 'a segunda parte tem cinco segundos por contar',
    );

    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    expect(
      harness.room.chunksSent,
      0,
      reason: 'um corte sobre os vinte e cinco segundos já contados não sai',
    );

    harness.playback.at = const Duration(seconds: 28);
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor('o trecho chegar à sala', () => harness.room.chunksSent == 1);
    expect(harness.room.chunkSpans, ['25000-28000']);
    expect(harness.room.chunkTakes, [partes[1].takeId]);
  });

  test('uma metade que ninguém contou ainda não é chão para pular', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000, 30000],
      porTraduzir: {'trecho-3'},
    );
    await gravarMaisUmaParte(container);

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a retro começar a tocar',
      () => harness.playback.played.isNotEmpty,
    );

    final partes = container.read(salaSessionProvider).keptTakes;
    expect(
      harness.playback.played.last,
      partes[2].path,
      reason:
          'a terceira parte tem um trecho nascido de uma divisão que '
          'ninguém explicou; pulá-la seria dizer à sala que foi ouvida e '
          'deixá-la esperando a explicação',
    );
  });

  test('uma parte que não se deixa medir é retomada do começo', () async {
    final harness = SalaHarness()..playback.measured = null;
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000, 30000],
    );
    await gravarMaisUmaParte(container);

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a retro começar a tocar',
      () => harness.playback.played.isNotEmpty,
    );

    final partes = container.read(salaSessionProvider).keptTakes;
    expect(
      harness.playback.played.last,
      partes[0].path,
      reason:
          'sem medida não há como saber se a parte está inteira; a sala '
          'toca-a com o cursor no fim do já contado, como uma retomada faz',
    );
  });

  testWidgets('enquanto a sala mede as partes, um toque não abre o microfone', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 400));
    await gravarUmaParte(tester, notifier);
    final nova = container.read(salaSessionProvider).keptTakes.last;
    final gravacoes = harness.recorder.captures;
    final tocadas = harness.playback.played.length;

    harness.playback.holdNextMeasurement();
    await tester.tap(byLabel(irParaARetro));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.thinking,
      reason:
          'medir espera pelo tocador, e a sala está ocupada enquanto espera',
    );
    notifier.cortarTrecho();
    notifier.retroTap();
    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.recorder.captures,
      gravacoes,
      reason:
          'um corte dentro da espera abria o microfone sobre um clipe '
          'prestes a começar, com o cursor no zero',
    );
    expect(harness.playback.played.length, tocadas);

    harness.playback.finishHeldMeasurement();
    await tester.pump(const Duration(milliseconds: 400));

    final agora = container.read(salaSessionProvider);
    expect(agora.btPhase, BtPhase.playing);
    expect(harness.playback.played.last, nova.path);

    // Let the part end, so no clip is in the air when the test's screen goes away.
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('uma falta com endereço pergunta pela voz, não vai ao ensaio', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );

    final agora = container.read(salaSessionProvider);
    expect(agora.stage, SalaStage.retro);
    expect(agora.btPhase, BtPhase.findings);
    expect(agora.btFindingTrecho?.segmentId, 'trecho-2');
    for (final microfone in [
      'Gravar a parte de novo na língua materna',
      'Traduzir este trecho de novo',
    ]) {
      expect(
        byLabel(microfone),
        findsOneWidget,
        reason:
            'a falta cabe num trecho: a equipe sabe se a materna já tem o '
            'que faltou, então o achado oferece os dois microfones como para '
            'qualquer outro achado',
      );
    }
    expect(
      byLabel(continuarOEnsaio),
      findsNothing,
      reason: 'o disco que devolve ao ensaio é só para a falta sem endereço',
    );
  });
}
