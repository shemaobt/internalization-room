import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart' show Sala;

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  testWidgets(
    'a language tapped on a Choice the room could not reach changes the words '
    'and asks the room nothing',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.failBooksWith = const NetworkFailed('sem rede');
      final container = await pumpSala(tester, harness);
      await _catchUp(tester);
      harness.room.reachable = false;
      final asked = harness.room.calls.length;
      var thought = 0;
      container.listen(salaSessionProvider, (_, after) {
        if (after.voice == VoiceState.thinking) thought++;
      });

      await tester.tap(find.text('EN'));
      await tester.pump();
      await _catchUp(tester);

      expect(find.text('Choose the Passage'), findsOneWidget);
      expect(
        harness.room.calls.skip(asked),
        isEmpty,
        reason: 'sem rede, trocar a língua relia os livros na sala',
      );
      expect(
        thought,
        0,
        reason: 'o círculo pensava a cada toque na língua, sem rede',
      );
      expect(container.read(salaSessionProvider).needsPerson, isFalse);
    },
  );

  test(
    'a language tapped after the room refused the Wheel asks it nothing, and the '
    'next open of the Choice reads it in that language',
    () async {
      final harness = SalaHarness()
        ..room.failBooksWith = const Refused('BAD_REQUEST');
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await it.sala.abrirEscolha();
      await settle();
      final asked = harness.room.calls.length;
      var thought = 0;
      container.listen(salaSessionProvider, (_, after) {
        if (after.voice == VoiceState.thinking) thought++;
      });

      it.sala.chooseTheLanguage('en');
      await settle();

      expect(
        harness.room.calls.skip(asked),
        isEmpty,
        reason:
            'a roda que a sala recusou era pedida de novo a cada toque na língua',
      );
      expect(thought, 0);

      harness.room.failBooksWith = null;
      await it.sala.abrirEscolha();

      expect(it.estado.entriesOpen, isTrue);
      expect(
        harness.room.languagesAsked.toSet(),
        {'en'},
        reason: 'a roda lida na próxima abertura vinha na língua de antes',
      );
    },
  );

  test(
    'a language tapped while the tablet still lands on its session does not move '
    'the landing',
    () async {
      final harness = SalaHarness(
        currentSession: FakeCurrentSessionLedger()
          ..held = const CurrentSession(
            sessionId: 'sessao-7',
            book: 'Ruth',
            pericope: 'P02',
            language: 'pt',
          ),
      )..room.holdNextState();
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      it.sala.openTheRoom().ignore();
      await settle();

      it.sala.chooseTheLanguage('en');
      harness.room.finishHeldState();
      await settle();
      await settle();

      expect(
        it.estado.sessionId,
        'sessao-7',
        reason:
            'a língua tocada no meio do pouso movia a geração e o pouso era abandonado',
      );
    },
  );
}
