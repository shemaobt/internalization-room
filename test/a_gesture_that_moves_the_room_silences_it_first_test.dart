import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test('the team leaves the Conversation for the Choice while a line plays: '
      'the runner stops the sound before the Station moves', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaStage stage() => container.read(salaSessionProvider).stage;
    Machine machine() => container.read(salaSessionProvider).machine;

    harness.room.holdNextTurn();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    await waitFor('a vez ficar no ar', () => harness.room.turnsSent > 0);
    harness.voice.holdNextLine();
    harness.room.finishHeldTurn();
    await waitFor(
      'a resposta falar',
      () => container.read(salaSessionProvider).voice == VoiceState.speaking,
    );
    expect(stage(), SalaStage.conversa);
    final speaking = machine();
    final stagesAtTheStop = <SalaStage>[];
    harness.voice.onStop = () => stagesAtTheStop.add(stage());

    await notifier.abrirEscolha();
    await waitFor('a Escolha abrir', () => stage() == SalaStage.escolha);

    expect(stagesAtTheStop, isNotEmpty);
    expect(
      stagesAtTheStop,
      everyElement(SalaStage.conversa),
      reason: 'a stop came after the Station had moved',
    );
    final (_, effects) = reduce(speaking, const GestureSilenced());
    expect(effects, contains(isA<StopTheSound>()));
  });
}
