import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

Finder bySemanticsLabelWidget(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

void main() {
  testWidgets('convite renders the facilitator circle', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SalaApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FacilitatorCircle), findsOneWidget);
  });

  testWidgets('conversa renders circle, hand button and colar',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SalaApp(),
      ),
    );
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(find.byType(ColarOverlay), findsOneWidget);
    expect(bySemanticsLabelWidget('Levantar a mão'), findsOneWidget);
    expect(bySemanticsLabelWidget('Segurar para falar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
  });
}
