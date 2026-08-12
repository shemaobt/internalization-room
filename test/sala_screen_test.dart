import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
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

  testWidgets(
    'conversa offers a tap to speak, the hand and the colar — paused while the hand is disabled (handReachesAPerson)',
      (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(find.byType(ColarOverlay), findsOneWidget);
    expect(bySemanticsLabelWidget('Levantar a mão'), findsOneWidget);
    expect(bySemanticsLabelWidget('Tocar para falar'), findsOneWidget);
  }, skip: true);

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

  testWidgets(
    'an unheard reply turns the hand into a listening affordance — paused while the hand is disabled (handReachesAPerson)',
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
  }, skip: true);

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

  testWidgets(
    'the findings screen offers the retell and re-record exits — unreachable '
    'while the back-translation verdict lives on the backend without a route',
    (tester) async {},
    skip: true,
  );

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
}
