import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _onTheConversationOfAnEndedPassage() async {
  final harness = SalaHarness()..room.done = true;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor(
    'the passage to stand at done',
    () => it.estado.sessionId != null && it.estado.voice == VoiceState.done,
  );
  await settle();
  return it;
}

void main() {
  test('the way back from the recording finds the ended passage still at done, '
      'not at the invite', () async {
    final it = await _onTheConversationOfAnEndedPassage();
    expect(it.estado.orangeDotLook, OrangeDotLook.bright);

    it.sala.openTheEnsaioFinal();
    await waitFor('the recording to open', () => it.estado.station is Ensaio);
    await settle();
    it.sala.leaveTheRecording();
    await settle();

    expect(it.estado.station, isA<Canvas>());
    expect(
      it.estado.voice,
      VoiceState.done,
      reason: 'a volta da gravação deixava a conversa encerrada no convite',
    );
    expect(
      it.estado.orangeDotLook,
      OrangeDotLook.bright,
      reason: 'o ponto laranja voltava apagado',
    );
  });
}
