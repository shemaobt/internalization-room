import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        aprovar,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        parte,
        tocar,
        tocarNoCirculo;

const _naoDeuParaConferir = 'não deu para conferir agora — tentem de novo';

Future<ProviderContainer> _ateAConferida(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await contarAteOFimDaParte(tester, harness);
  await tocar(tester, conferir);
  await tester.pump(const Duration(milliseconds: 600));
  expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
  return container;
}

void main() {
  testWidgets('after a clean verdict the terminei stays on the check instead '
      'of leaving it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);

    expect(
      byLabel(conferir),
      findsOneWidget,
      reason: 'o veredito limpo tirava o terminei da tela; o dela fica',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on the terminei of a checked telling checks it again, '
      'as hers does, and lands back on the approval', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);

    expect(
      aceso(tester, conferir),
      isTrue,
      reason: 'na conferida o terminei ficava sem toque nenhum',
    );
    harness.room.holdNextVerdict();
    await tocar(tester, conferir);

    expect(byLabel('conferindo…'), findsOneWidget);
    harness.room.finishHeldVerdict();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.playedByTakeSent,
      hasLength(2),
      reason: 'o segundo terminei não pedia a conferência de novo',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(byLabel(aprovar), findsOneWidget);
    expect(byLabel(conferir), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('while an approval is in the air the terminei is dimmed, and a '
      'tap on it asks for no check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.holdNextRelease();
    await tocar(tester, aprovar);

    expect(
      aceso(tester, conferir),
      isFalse,
      reason: 'com a aprovação no ar o terminei ficava aceso',
    );
    await tocar(tester, conferir);
    expect(
      harness.room.playedByTakeSent,
      hasLength(1),
      reason: 'o terminei pedia a conferência por cima da aprovação',
    );
    harness.room.finishHeldRelease();
    await tester.pump(const Duration(milliseconds: 600));
    closeTheRoom(container);
  });

  testWidgets('a check the room cannot make over a checked telling leaves the '
      'team on the approval, as hers does, not back on the telling', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'a recusa do segundo terminei devolvia a equipe à tradução',
    );
    expect(byLabel(aprovar), findsOneWidget);
    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  testWidgets('a play after a check the room cannot make over a checked '
      'telling leaves her line standing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_naoDeuParaConferir), findsOneWidget);
    final tocadas = harness.playback.played.length;

    await tocar(tester, 'Ouvir a gravação');
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.playback.played.length, greaterThan(tocadas));
    expect(
      find.text(_naoDeuParaConferir),
      findsOneWidget,
      reason: 'o play apagava a linha da conferência que não rodou',
    );
    closeTheRoom(container);
  });

  testWidgets('a play after an approval the room could not take leaves her '
      'line standing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.failReleaseWith = const NetworkFailed('sem rede');
    await tocar(tester, aprovar);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_naoDeuParaConferir), findsOneWidget);
    final tocadas = harness.playback.played.length;

    await tocar(tester, 'Ouvir a gravação');
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.playback.played.length, greaterThan(tocadas));
    expect(find.text(_naoDeuParaConferir), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a check lost on the network over a checked telling leaves the '
      'team on the approval, not back on the telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.failFinishWith = const NetworkFailed('sem rede');
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'o segundo terminei sem rede devolvia a equipe à tradução',
    );
    expect(byLabel(aprovar), findsOneWidget);
    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  testWidgets('a check the room refuses over a checked telling leaves the team '
      'on the approval, not back on the telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.failFinishWith = const Refused('BAD_REQUEST');
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason:
          'a recusa da sala ao segundo terminei devolvia a equipe à tradução',
    );
    expect(byLabel(aprovar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a verdict over a checked telling whose sound will not play '
      'leaves the team on the approval, not back on the telling', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.voice.refuses.add(falaDoVeredito);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 900));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'o veredito que não tocava devolvia a equipe à tradução',
    );
    expect(byLabel(aprovar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a checked telling reopened from the home has terminei lit at '
      'once when the room counts it heard, before anything plays', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room
      ..readsChecked = true
      ..listeningUnheardTakeIds = const [];
    final sala = container.read(salaSessionProvider.notifier);
    sala.leaveTheBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    final tocadas = harness.playback.played.length;

    sala.startRetro();
    await waitFor(
      'a conferida voltar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.playback.played.length, tocadas);
    expect(
      aceso(tester, conferir),
      isTrue,
      reason:
          'o terminei da passagem conferida esperava a gravação tocar até o '
          'fim, com a sala já contando tudo ouvido',
    );
    closeTheRoom(container);
  });

  testWidgets('a tablet reopened into a checked telling has terminei lit at '
      'once when the room counts it heard, before anything plays', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..playback.length = parte
      ..playback.measured = parte;
    final casa = Directory.systemTemp.createTempSync('sala-conferida');
    addTearDown(() => casa.deleteSync(recursive: true));
    await holdTheSession(
      harness,
      ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          KeptTake(
            scopeId: KeptScope.parte(1),
            path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1])).path,
            takeId: 'gravacao-1',
          ),
        ],
      ),
    );
    harness.room
      ..retroSoFar = BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: parte.inMilliseconds,
          ),
        ],
        checked: true,
      )
      ..listeningUnheardTakeIds = const [];
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
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(harness.playback.played, isEmpty);
    expect(
      aceso(tester, conferir),
      isTrue,
      reason:
          'a passagem conferida retomada abria com o terminei apagado até uma '
          'escuta inteira, com a sala já contando tudo ouvido',
    );
    closeTheRoom(container);
  });
}
