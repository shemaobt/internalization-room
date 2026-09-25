import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget;

Future<ProviderContainer> _pumpNoEnsaio(
  WidgetTester tester, {
  String lingua = testLanguage,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: lingua);
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));

  return container;
}

Future<ProviderContainer> _pumpAoGravado(
  WidgetTester tester, {
  String lingua = testLanguage,
}) async {
  final container = await _pumpNoEnsaio(tester, lingua: lingua);
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  testWidgets('the pending-part row speaks english to an english room', (
    tester,
  ) async {
    final container = await _pumpAoGravado(tester, lingua: 'en');
    addTearDown(container.dispose);

    expect(
      bySemanticsLabelWidget('Hear the rehearsal so far'),
      findsOneWidget,
      reason: 'quem gravou em inglês ouve o próprio idioma no play do ensaio',
    );
    expect(bySemanticsLabelWidget('Confirm this part'), findsOneWidget);
    expect(
      bySemanticsLabelWidget('Go to the translation'),
      findsOneWidget,
      reason: 'o botão que leva à tradução também não fica preso ao português',
    );

    container.read(salaSessionProvider.notifier).takeKeep();
    await letTheRehearsalReachTheRoom(tester);

    expect(
      bySemanticsLabelWidget('Tap to record the next part'),
      findsOneWidget,
      reason: 'confirmada a parte, o círculo convida a próxima em inglês',
    );
  });

  testWidgets(
    'the rehearsal-play button names the tap it is about to receive, in english',
    (tester) async {
      final container = await _pumpAoGravado(tester, lingua: 'en');
      addTearDown(container.dispose);

      await tester.tap(bySemanticsLabelWidget('Hear the rehearsal so far'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        bySemanticsLabelWidget('Pause the rehearsal'),
        findsOneWidget,
        reason:
            'o ícone já vira pausa; o rótulo em inglês precisa dizer a '
            'mesma coisa, não repetir "hear" sobre um toque que pausa',
      );
      expect(bySemanticsLabelWidget('Hear the rehearsal so far'), findsNothing);
    },
  );

  testWidgets(
    'the rehearsal-play button names the tap it is about to receive, in portuguese',
    (tester) async {
      final container = await _pumpAoGravado(tester);
      addTearDown(container.dispose);

      await tester.tap(bySemanticsLabelWidget('Ouvir o ensaio até aqui'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        bySemanticsLabelWidget('Pausar o ensaio'),
        findsOneWidget,
        reason: 'a mesma palavra que retro_view.dart já usa para o mesmo gesto',
      );
      expect(bySemanticsLabelWidget('Ouvir o ensaio até aqui'), findsNothing);
    },
  );

  testWidgets('the record circle speaks english to an english room', (
    tester,
  ) async {
    final container = await _pumpNoEnsaio(tester, lingua: 'en');
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(
      bySemanticsLabelWidget('Tap to record the rehearsal'),
      findsOneWidget,
      reason: 'a tela recém-aberta convida a gravar, no idioma da equipe',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Tap when you finish'),
      findsOneWidget,
      reason: 'gravando, o círculo diz em inglês que o toque encerra',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      bySemanticsLabelWidget('Tap to record this part again'),
      findsOneWidget,
      reason: 'com a parte pendente, o círculo oferece regravá-la em inglês',
    );
  });
}
