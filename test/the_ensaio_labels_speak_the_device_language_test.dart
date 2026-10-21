import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, offTheRows, onTheCircle;

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
  await notifier.goConversa(book: 'Ruth');
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
      offTheRows('Listen'),
      findsOneWidget,
      reason: 'quem gravou em inglês ouve o próprio idioma no play do ensaio',
    );
    expect(offTheRows('Send the recording'), findsOneWidget);
    expect(
      byLabel('Translate the recording'),
      findsOneWidget,
      reason: 'o botão que leva à tradução também não fica preso ao português',
    );

    container.read(salaSessionProvider.notifier).takeKeep();
    await letTheRehearsalReachTheRoom(tester);

    expect(
      onTheCircle('Record'),
      findsOneWidget,
      reason: 'confirmada a parte, o círculo convida a próxima em inglês',
    );
  });

  testWidgets(
    'the rehearsal-play button names the tap it is about to receive, in english',
    (tester) async {
      final container = await _pumpAoGravado(tester, lingua: 'en');
      addTearDown(container.dispose);

      await tester.tap(offTheRows('Listen'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        offTheRows('Stop'),
        findsOneWidget,
        reason:
            'o ícone já vira parar; o rótulo em inglês precisa dizer a '
            'mesma coisa, não repetir "listen" sobre um toque que para',
      );
      expect(offTheRows('Listen'), findsNothing);
    },
  );

  testWidgets(
    'the rehearsal-play button names the tap it is about to receive, in portuguese',
    (tester) async {
      final container = await _pumpAoGravado(tester);
      addTearDown(container.dispose);

      await tester.tap(offTheRows('Ouvir'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        offTheRows('Parar'),
        findsOneWidget,
        reason: 'a palavra dela para o mesmo gesto',
      );
      expect(offTheRows('Ouvir'), findsNothing);
    },
  );

  testWidgets('the record circle speaks english to an english room', (
    tester,
  ) async {
    final container = await _pumpNoEnsaio(tester, lingua: 'en');
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(
      onTheCircle('Record'),
      findsOneWidget,
      reason: 'a tela recém-aberta convida a gravar, no idioma da equipe',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      onTheCircle('Stop'),
      findsOneWidget,
      reason: 'gravando, o círculo diz em inglês que o toque encerra',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      onTheCircle('Record again'),
      findsOneWidget,
      reason: 'com a parte pendente, o círculo oferece regravá-la em inglês',
    );
  });
}
