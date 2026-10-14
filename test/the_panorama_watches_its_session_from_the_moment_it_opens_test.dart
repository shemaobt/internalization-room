import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _period = Duration(milliseconds: 60);

const _theBook = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
];

typedef _Sala = ({
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier notifier,
});

_Sala _aRoomThatWatches() {
  final harness = SalaHarness(settleDelay: _period, watchesWithoutAHalt: true)
    ..room.passages = _theBook;
  final container = harness.container();
  addTearDown(container.dispose);
  return (
    harness: harness,
    container: container,
    notifier: container.read(salaSessionProvider.notifier),
  );
}

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

Future<void> _theIdlePanorama(_Sala sala) async {
  await enterThePanorama(sala.notifier, () => _read(sala));
  await waitFor(
    'the Panorama to be said',
    () => _read(sala).panoramaSaid && _read(sala).voice == VoiceState.invite,
  );
}

Future<void> _theRoomHoldsAHalt(_Sala sala) async {
  sala.harness.room
    ..serverStatus = 'needs_person'
    ..serverHalt = HaltKind.blocking;
}

void main() {
  test('an idle Panorama reads its session within a beat and shows a halt the '
      'room holds for it', () async {
    final sala = _aRoomThatWatches();
    await _theIdlePanorama(sala);
    final before = stateReads(sala.harness);

    await _theRoomHoldsAHalt(sala);

    await waitFor('the person sign', () => _read(sala).needsPerson);
    expect(stateReads(sala.harness), greaterThan(before));
  });

  test('the Panorama returned to in silence watches its session too', () async {
    final sala = _aRoomThatWatches();
    await _theIdlePanorama(sala);
    sala.notifier.leaveThePassage();
    await waitFor('the way back', () => _read(sala).theWayBackIsLive);
    await sala.notifier.returnToTheLeftEntry();
    await waitFor(
      'the Panorama to be back',
      () => _read(sala).stage == SalaStage.panorama,
    );
    final before = stateReads(sala.harness);

    await _theRoomHoldsAHalt(sala);

    await waitFor('the person sign', () => _read(sala).needsPerson);
    expect(stateReads(sala.harness), greaterThan(before));
  });

  test('leaving the Panorama for the Choice ends its watch', () async {
    final sala = _aRoomThatWatches();
    await _theIdlePanorama(sala);
    final opened = stateReads(sala.harness);
    await waitFor(
      'the idle Panorama to be read',
      () => stateReads(sala.harness) > opened,
    );
    sala.notifier.leaveThePassage();
    await Future<void>.delayed(_period * 2);
    final after = stateReads(sala.harness);

    await Future<void>.delayed(_period * 4);

    expect(stateReads(sala.harness), after);
  });
}
