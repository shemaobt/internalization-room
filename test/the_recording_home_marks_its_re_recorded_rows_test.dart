import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show cabeca, parte, tocarNoCirculo;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

const _deNovo = 'regravada — traduzam de novo';

Finder _naLinha(int n, String marca) =>
    find.descendant(of: byLabel('Cena $n'), matching: find.text(marca));

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<void> _naCasa(WidgetTester tester, ProviderContainer container) async {
  container.read(salaSessionProvider.notifier).goEnsaio();
  await tester.pump(const Duration(milliseconds: 300));
  await _passo(tester);
}

Future<void> _regravarACena(
  WidgetTester tester,
  ProviderContainer container,
  int n,
) async {
  final sala = container.read(salaSessionProvider.notifier);
  sala.gravarACena(n);
  await _passo(tester);
  sala.gravarACena(n);
  await _passo(tester);
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  await _passo(tester);
}

void main() {
  testWidgets('a scene recorded again after its frases were told says '
      '«$_deNovo» on its own row, not on the other', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness, emWav: false);
    await _naCasa(tester, container);
    expect(find.text(_deNovo), findsNothing);

    await _regravarACena(tester, container, 2);

    expect(container.read(salaSessionProvider).btTrechosRegravados, isNotEmpty);
    expect(byLabel('Cena 2'), findsOneWidget);
    expect(
      _naLinha(2, _deNovo),
      findsOneWidget,
      reason: 'a cena regravada ficava como se as frases dela valessem',
    );
    expect(
      tester.widget<Semantics>(byLabel('Cena 2')).properties.value,
      '✓ $_deNovo',
      reason: 'a marca só se via, quem ouve a tela não sabia',
    );
    expect(_naLinha(1, _deNovo), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('the whole recording made again after its frases were told '
      'says «$_deNovo» on its one row', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..measured = parte
      ..length = parte;
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await _passo(tester);
    final sala = container.read(salaSessionProvider.notifier);
    await sala.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    await _naCasa(tester, container);
    sala.recordTheWholePassageInstead();
    await tester.pump(const Duration(milliseconds: 300));
    await letTheRehearsalReachTheRoom(tester);
    sala.ensaioTap();
    sala.ensaioTap();
    await _passo(tester);
    sala.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    sala.startRetro();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = cabeca;
    for (var toque = 0; toque < 3; toque++) {
      await tocarNoCirculo(tester);
    }
    await waitFor(
      'uma frase da passagem inteira ficar contada',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );
    await _naCasa(tester, container);

    await _regravarACena(tester, container, 1);

    expect(container.read(salaSessionProvider).btTrechosRegravados, isNotEmpty);
    expect(
      find.descendant(
        of: byLabel('A passagem inteira'),
        matching: find.text(_deNovo),
      ),
      findsOneWidget,
      reason: 'a passagem regravada inteira não dizia que a tradução caducou',
    );
    closeTheRoom(container);
  });

  testWidgets('an English session says «re-recorded — translate again»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await quatroFrasesEmWav(tester, harness, emWav: false);
    await _naCasa(tester, container);

    await _regravarACena(tester, container, 2);

    expect(
      find.descendant(
        of: byLabel('Scene 2'),
        matching: find.text('re-recorded — translate again'),
      ),
      findsOneWidget,
    );
    closeTheRoom(container);
  });
}
