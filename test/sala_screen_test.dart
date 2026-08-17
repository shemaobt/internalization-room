import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

Finder bySemanticsLabelWidget(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

Future<ProviderContainer> pumpSala(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

Future<void> takeATurn(WidgetTester tester, ProviderContainer container) async {
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.conversaTap();
  await tester.pump(const Duration(milliseconds: 20));
  notifier.conversaTap();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('convite renders the facilitator circle', (tester) async {
    await pumpSala(tester, SalaHarness());

    expect(find.byType(FacilitatorCircle), findsOneWidget);
  });

  testWidgets('the circle has real size, not just a place in the tree', (tester) async {
    await pumpSala(tester, SalaHarness());

    final drawn = tester.getSize(find.byType(FacilitatorCircle));

    expect(drawn.width, greaterThan(0),
        reason: 'um Stack com restrições frouxas encolhe para o maior filho sem '
            'posição — um filho de 0x0 colapsa a tela inteira, e o widget continua '
            'na árvore como se estivesse lá');
    expect(drawn.height, greaterThan(0));
  });

  testWidgets('every stage paints something the team can see', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    for (final go in [notifier.goConversa, notifier.goEnsaio, notifier.startRetro]) {
      go();
      await tester.pump(const Duration(milliseconds: 120));
      final body = tester.getSize(find.byType(Scaffold));
      expect(body.width, greaterThan(0));
      expect(body.height, greaterThan(0));
    }
  });




  testWidgets('no stage ever shows a written word', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(find.byType(Text), findsNothing, reason: 'convite');

    for (final go in [notifier.goConversa, notifier.goEnsaio, notifier.startRetro]) {
      go();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Text), findsNothing,
          reason: 'a sala é falada de ponta a ponta: uma palavra escrita é uma '
              'palavra que esta equipe não pode ler');
    }
  });

  testWidgets('no stage is a dead end — every screen answers a touch',
      (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    Future<void> expectALiveGesture(String stage) async {
      await tester.pump(const Duration(milliseconds: 200));
      final live = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .where((it) => it.onTap != null || it.onLongPress != null);
      expect(live, isNotEmpty,
          reason: 'sem gesto vivo em "$stage" a equipe não tem o que tocar, e '
              'não há texto que explique o que houve');
    }

    await expectALiveGesture('convite');
    notifier.goConversa();
    await expectALiveGesture('conversa');
    notifier.goEnsaio();
    await expectALiveGesture('ensaio');
    notifier.startRetro();
    await expectALiveGesture('retro');
  });

  testWidgets('the mic gate answers a touch out loud, not in silence',
      (tester) async {
    final harness = SalaHarness()..recorder.permitted = false;
    final container = await pumpSala(tester, harness);
    await container.read(micPermissionProvider.notifier).check();
    await tester.pump(const Duration(milliseconds: 200));
    harness.voice.assets.clear();

    await tester.tap(find.byType(FacilitatorCircle));
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.voice.assets, contains(micBlockedAsset),
        reason: 'a tela do microfone não tem texto: se o toque não fala, ela é '
            'muda e sem efeito para sempre');
  });

  testWidgets('conversa offers a tap to speak, the hand and the colar',
      (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(find.byType(ColarOverlay), findsOneWidget);
    expect(bySemanticsLabelWidget('Levantar a mão'), findsOneWidget);
    expect(bySemanticsLabelWidget('Tocar para falar'), findsOneWidget);
  });

  testWidgets('a peer cue turns the circle into team-talk mode',
      (tester) async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await pumpSala(tester, harness);
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(find.byIcon(LucideIcons.users), findsOneWidget);
    expect(
      bySemanticsLabelWidget(
        'Conversem entre vocês — tocar quando quiserem me contar',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unheard reply turns the hand into a listening affordance',
      (tester) async {
    final container = await pumpSala(
      tester,
      SalaHarness(replies: const [HandReply(id: 'r1', audioUrl: '/api/internalization-room/voice/resposta')]),
    );
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      bySemanticsLabelWidget('Ouvir a resposta do facilitador'),
      findsOneWidget,
    );
    expect(bySemanticsLabelWidget('Levantar a mão'), findsNothing);
  });

  testWidgets('the back-translation offers terminei once the clip ends',
      (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      bySemanticsLabelWidget('Terminei de contar de volta'),
      findsNothing,
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      bySemanticsLabelWidget('Terminei de contar de volta'),
      findsOneWidget,
    );
  });

  testWidgets('the findings screen offers the retell and re-record exits',
      (tester) async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(
      bySemanticsLabelWidget('Ouvir e contar esta parte de novo'),
      findsOneWidget,
    );
    expect(bySemanticsLabelWidget('Gravar esta parte de novo'), findsOneWidget);
  });

  testWidgets('the ensaio offers ghost play before recording', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      bySemanticsLabelWidget('Ouvir o ensaio guardado antes de gravar'),
      findsNothing,
    );

    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      bySemanticsLabelWidget('Ouvir o ensaio guardado antes de gravar'),
      findsOneWidget,
    );
  });

  testWidgets('a long press unsticks a retro the room abandoned', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.takeKeep();
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room.failWith = const RoomRefused();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    await tester.longPress(find.byType(FacilitatorCircle).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'a retro travada não tinha saída nenhuma pela tela');
  });
}
