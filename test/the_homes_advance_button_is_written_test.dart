import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
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

const _gravar = 'Gravar';
const _parar = 'Parar';
const _enviarAGravacao = 'Enviar a gravação';
const _traduzir = 'Traduzir a gravação';
const _translate = 'Translate the recording';

SalaHarness _umaSala({String lingua = 'pt'}) => SalaHarness(
  lingua: lingua,
  filaEmMemoria: true,
  takesHome: aTempDir('sala-1893'),
)..room.passageScenes = _cenas;

Future<ProviderContainer> _naCasa(
  WidgetTester tester,
  SalaHarness harness,
) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Finder _naLinha(int n, String controle) => find.descendant(
  of: find.descendant(
    of: find.byType(EnsaioView),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label ?? '').startsWith(
            'Cena $n — ${_cenas[n - 1].title}',
          ),
    ),
  ),
  matching: byLabel(controle),
);

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _gravarEEnviar(WidgetTester tester, int n) async {
  await _tocar(tester, _naLinha(n, _gravar));
  await _tocar(tester, _naLinha(n, _parar));
  await _tocar(tester, offTheRows(_enviarAGravacao));
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _gravarTudo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var n = 1; n <= 3; n++) {
    await _gravarEEnviar(tester, n);
  }
  await theRoomNamesTheParts(tester, container, parts: 3);
  await untilTheAdvanceDiscLights(
    container.read(salaSessionProvider.notifier),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

bool _live(WidgetTester tester, String words) =>
    tester.widget<Semantics>(inTheHome(words)).properties.enabled == true;

SalaStage _stage(ProviderContainer container) =>
    container.read(salaSessionProvider).stage;

void main() {
  testWidgets('the recording home\'s advance button is written «$_traduzir»', (
    tester,
  ) async {
    await _naCasa(tester, _umaSala());

    final words = find.descendant(
      of: find.byType(EnsaioView),
      matching: find.text(_traduzir),
    );
    expect(words, findsOneWidget);
    expect(
      find.descendant(of: inTheHome(_traduzir), matching: words),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: inTheHome(_traduzir),
        matching: find.byType(RoundActionButton),
      ),
      findsNothing,
    );
  });

  testWidgets('in English the advance button reads «$_translate»', (
    tester,
  ) async {
    await _naCasa(tester, _umaSala(lingua: 'en'));

    final words = find.descendant(
      of: find.byType(EnsaioView),
      matching: find.text(_translate),
    );
    expect(words, findsOneWidget);
    expect(
      find.descendant(of: inTheHome(_translate), matching: words),
      findsOneWidget,
    );
  });

  testWidgets(
    'VoiceOver reads the advance button once, as the words it shows',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _naCasa(tester, _umaSala());

      final nodes = inTheHome(_traduzir);
      expect(nodes, findsOneWidget);
      await tester.ensureVisible(nodes);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<Semantics>(nodes).properties.button, isTrue);
      var reads = 0;
      void count(SemanticsNode node) {
        reads += _traduzir.allMatches(node.label).length;
        node.visitChildren((child) {
          count(child);
          return true;
        });
      }

      count(tester.getSemantics(nodes));
      expect(reads, 1);
      handle.dispose();
    },
  );

  testWidgets(
    'the advance button is disabled while a scene has no part, and its tap '
    'opens nothing',
    (tester) async {
      final container = await _naCasa(tester, _umaSala());
      await _gravarEEnviar(tester, 1);

      expect(_live(tester, _traduzir), isFalse);
      await _tocar(tester, find.text(_traduzir));
      expect(_stage(container), SalaStage.ensaio);
    },
  );

  testWidgets(
    'once every scene has its part and the room holds every part, the advance '
    'button is live and its tap opens the Back-translation',
    (tester) async {
      final container = await _naCasa(tester, _umaSala());
      await _gravarTudo(tester, container);

      expect(_live(tester, _traduzir), isTrue);
      await _tocar(tester, find.text(_traduzir));
      expect(_stage(container), SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets('a part still going up keeps the advance button disabled', (
    tester,
  ) async {
    final harness = _umaSala();
    final container = await _naCasa(tester, harness);
    await _gravarEEnviar(tester, 1);
    await _gravarEEnviar(tester, 2);
    harness.room.unreachableTake = 'ensaio/parte-3';
    await _gravarEEnviar(tester, 3);
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 200));

    final state = container.read(salaSessionProvider);
    expect(state.everySceneHasItsPart, isTrue);
    expect(state.unsentParts.keys, [3]);
    expect(_live(tester, _traduzir), isFalse);
    await _tocar(tester, find.text(_traduzir));
    expect(_stage(container), SalaStage.ensaio);
  });
}
