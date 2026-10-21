import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

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

void _theRoomHoldsAWarning(_Sala sala) {
  sala.harness.room
    ..serverStatus = 'needs_person'
    ..serverHalt = HaltKind.warning;
}

void main() {
  test('an idle Panorama reads its session within a beat and marks a warning '
      'the room holds for it, never the person sign', () async {
    final sala = _aRoomThatWatches();
    await _theIdlePanorama(sala);
    final before = stateReads(sala.harness);

    _theRoomHoldsAWarning(sala);

    await waitFor('the warning', () => _read(sala).warning);
    expect(stateReads(sala.harness), greaterThan(before));
    expect(_read(sala).needsPerson, isFalse);
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

    _theRoomHoldsAWarning(sala);

    await waitFor('the warning', () => _read(sala).warning);
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

  test('a Panorama whose session the server forgot sends the team to the '
      'Choice with no gesture', () async {
    final sala = _aRoomThatWatches();
    await _theIdlePanorama(sala);

    sala.harness.room.forgetTheSession(sala.harness.room.sessionIds.last);

    await waitFor(
      'the Choice and its Wheel',
      () => _read(sala).station is Menu && _read(sala).naRoda != null,
    );
    expect(_read(sala).needsPerson, isFalse);
  });
}
