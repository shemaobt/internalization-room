import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/passage_ruler.dart';
import 'package:internalization_room/features/sala/presentation/widgets/panorama_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _p01 = Passagem(pericope: 'P01', audioUrl: '/voice/p01');
const _p02 = Passagem(pericope: 'P02', audioUrl: '/voice/p02');
const _p03 = Passagem(pericope: 'P03', audioUrl: '/voice/p03');
const _theBook = [_panorama, _p01, _p02, _p03];

void _expectThePassageChoice(SalaHarness harness, SalaSessionState state) {
  expect(state.station, isA<Menu>());
  expect(state.stage, SalaStage.escolha);
  expect(state.naRoda, _theBook);
  expect(
    harness.room.calls,
    isNot(contains('createSession')),
    reason: 'opening the room on the Choice opens no session',
  );
}

void main() {
  test(
    'a tablet that never heard a Panorama opens on the passage choice',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(salaSessionProvider.notifier).openTheRoom();
      await settle();

      _expectThePassageChoice(harness, container.read(salaSessionProvider));
    },
  );

  test(
    'a tablet that already heard the Panorama opens on the passage choice too',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      harness.finished.done.add('livro:Ruth');
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(salaSessionProvider.notifier).openTheRoom();
      await settle();

      _expectThePassageChoice(harness, container.read(salaSessionProvider));
    },
  );

  testWidgets(
    'after the link the screen shows the passage choice and no other screen first',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passages = _theBook;
      harness.finished.holdNextAll();
      final container = await pumpSala(tester, harness);

      for (var pump = 0; pump < 10; pump++) {
        expect(find.byType(PanoramaView), findsNothing);
        expect(find.byType(EscolhaView), findsOneWidget);
        if (pump == 5) harness.finished.finishHeldAll();
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(container.read(salaSessionProvider).naRoda, _theBook);
    },
  );

  test(
    'opening the room again while the team is in a passage changes nothing',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(pericope: 'P01');
      await waitFor(
        'the passage to open',
        () => container.read(salaSessionProvider).sessionId != null,
      );
      final session = container.read(salaSessionProvider).sessionId;
      final wheelsAsked = harness.room.booksAsked.length;

      await notifier.openTheRoom();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.station, isA<Canvas>());
      expect(state.sessionId, session);
      expect(harness.room.booksAsked, hasLength(wheelsAsked));
    },
  );

  testWidgets(
    'the Panorama is the book\'s first entry and carries no done mark, and '
    'progress never reorders or hides an entry',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passages = _theBook;
      harness.finished.done.add('Ruth/P01');
      harness.emAberto.rows['Ruth/P02'] = const ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.conversa,
      );
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(salaSessionProvider).naRoda, _theBook);
      final ruler = tester.widget<PassageRuler>(find.byType(PassageRuler));
      expect(ruler.total, 4);
      expect(ruler.finished, {1});
      expect(ruler.started, {2});
    },
  );
}
