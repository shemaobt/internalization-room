import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'support/temp.dart';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

void inHerOrder(WidgetTester tester, List<(String, Finder)> pieces) {
  for (final (name, finder) in pieces) {
    expect(finder, findsOneWidget, reason: '«$name» is drawn once');
  }
  for (var i = 1; i < pieces.length; i++) {
    final above = tester.getRect(pieces[i - 1].$2);
    final below = tester.getRect(pieces[i].$2);
    expect(
      above.bottom,
      lessThanOrEqualTo(below.top + 0.01),
      reason: '«${pieces[i - 1].$1}» stands above «${pieces[i].$1}»',
    );
  }
}

Finder _text(String words) =>
    find.descendant(of: find.byType(EnsaioView), matching: find.text(words));

Future<ProviderContainer> _naCasa(
  WidgetTester tester, {
  required int gravadas,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = SalaHarness(
    filaEmMemoria: true,
    takesHome: aTempDir('sala-1913'),
  )..room.passageScenes = _cenas;
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  for (var n = 1; n <= gravadas; n++) {
    await gravarUmaParte(tester, container, n);
  }
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

void main() {
  testWidgets(
    'with every scene recorded, «Ouvir tudo» stands under the rows and the '
    'wood play and above «Traduzir a gravação», and the grain switch is last',
    (tester) async {
      await _naCasa(tester, gravadas: 3);

      inHerOrder(tester, [
        ('the last Scene row', onTheRows('Ouvir').last),
        ('the wood play', offTheRows('Ouvir')),
        ('Ouvir tudo', _text('Ouvir tudo')),
        ('Traduzir a gravação', inTheHome('Traduzir a gravação')),
        ('the grain switch', inTheHome('Gravar a passagem inteira')),
      ]);
    },
  );

  testWidgets(
    'with one scene of three recorded, «gravem todas as partes primeiro» '
    'stands under «Traduzir a gravação» and above the grain switch',
    (tester) async {
      await _naCasa(tester, gravadas: 1);

      inHerOrder(tester, [
        ('Traduzir a gravação', inTheHome('Traduzir a gravação')),
        (
          'gravem todas as partes primeiro',
          _text('gravem todas as partes primeiro'),
        ),
        ('the grain switch', inTheHome('Gravar a passagem inteira')),
      ]);
    },
  );
}
