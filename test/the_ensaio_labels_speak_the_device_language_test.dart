import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget;

Future<ProviderContainer> _pumpAoGravadoEmIngles(WidgetTester tester) async {
  final harness = SalaHarness(lingua: 'en');
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));

  return container;
}

void main() {
  testWidgets('the recorded-take row speaks english to an english room', (
    tester,
  ) async {
    final container = await _pumpAoGravadoEmIngles(tester);
    addTearDown(container.dispose);

    expect(
      bySemanticsLabelWidget('Listen to the recording'),
      findsOneWidget,
      reason: 'quem gravou em inglês ouve o próprio idioma no play do take',
    );
    expect(bySemanticsLabelWidget('Record again'), findsOneWidget);
    expect(bySemanticsLabelWidget('Keep this recording'), findsOneWidget);

    container.read(salaSessionProvider.notifier).takeKeep();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Go to the translation'),
      findsOneWidget,
      reason: 'o botão que leva à tradução também não fica preso ao português',
    );
  });

  testWidgets('the ghost-play button speaks english to an english room', (
    tester,
  ) async {
    final container = await _pumpAoGravadoEmIngles(tester);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.takeKeep();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Listen to the saved rehearsal before recording'),
      findsOneWidget,
      reason:
          'antes de gravar de novo, a equipe inglesa também precisa saber '
          'que pode ouvir o que já guardou',
    );

    notifier.ghostPlay();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Stop listening to the saved rehearsal'),
      findsOneWidget,
      reason: 'e parar de ouvir precisa do mesmo rótulo no próprio idioma',
    );
    expect(
      bySemanticsLabelWidget('The saved rehearsal is playing'),
      findsOneWidget,
      reason:
          'o círculo apagado durante o ghost play também precisa dizer '
          'isso em inglês, não só o botão ao lado',
    );
  });

  testWidgets('the record circle speaks english to an english room', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en');
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

    expect(
      bySemanticsLabelWidget('Tap to record the rehearsal'),
      findsOneWidget,
      reason: 'a tela recém-aberta convida a gravar, no idioma da equipe',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Tap when you are done'),
      findsOneWidget,
      reason:
          'gravando, o círculo reaproveita o mesmo par que o convite da '
          'conversa já usa para "ouvindo"',
    );
  });
}
