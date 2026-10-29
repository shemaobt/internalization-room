import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

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

  testWidgets('while the checagem externa opens the terminei is dimmed, and a '
      'tap on it asks for no check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ateAConferida(tester, harness);
    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    await tocar(tester, aprovar);
    await waitFor(
      'o ensaio salvo',
      () => find.text('Ensaio salvo').evaluate().isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.tap(byLabel('Pronto'));
    await tester.pump(const Duration(milliseconds: 800));
    final sala = container.read(salaSessionProvider.notifier);
    harness.room.readsChecked = true;
    sala.openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    sala.startRetro();
    await waitFor(
      'a retrotradução aprovada voltar conferida',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    harness.room.readsChecked = false;
    await tester.pump(const Duration(milliseconds: 800));
    await tocar(tester, 'Ouvir a gravação');
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 600));
    expect(aceso(tester, conferir), isTrue);

    harness.room.holdNextExternalCheck();
    await tocar(tester, 'Checagem externa');

    expect(
      aceso(tester, conferir),
      isFalse,
      reason: 'com a checagem externa abrindo o terminei ficava aceso',
    );
    await tocar(tester, conferir);
    expect(
      harness.room.playedByTakeSent,
      hasLength(1),
      reason: 'o terminei pedia a conferência por cima da checagem externa',
    );
    harness.room.finishHeldExternalCheck();
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
}
