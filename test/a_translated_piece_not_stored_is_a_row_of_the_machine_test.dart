import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _notStored = <RoomResult>[
  RoomNetworkFailed(),
  RoomTimedOut(),
  RoomFoundNothing(),
  RoomAnsweredWithoutAReply(),
  RoomRefused(RefusalCode.wordlessTelling),
];

(Machine, List<Effect>) _decidedAt(
  Machine machine,
  RoomResult result,
  Door door,
) => reduce(
  machine,
  FailurePolicy.decide(
    result,
    FailureContext(
      station: machine.station,
      step: machine.station is Retro ? BtPhase.thinking : null,
      generation: machine.generation,
      door: door,
    ),
  ),
);

void main() {
  test('at the scene frase door, a «found nothing» answer asks the frase again '
      'and raises no person sign', () {
    const onTheScene = Machine(station: SceneRehearsal());

    final (machine, effects) = _decidedAt(
      onTheScene,
      const RoomFoundNothing(),
      Door.sceneFrase,
    );

    expect(effects, const [AskTheFraseAgain()]);
    expect(machine.halt, const NoHalt());
    expect(machine.aHaltWaitsForTheCanvas, isNull);
  });

  for (final (door, station) in [
    (Door.sceneFrase, const SceneRehearsal()),
    (Door.telling, const Retro()),
  ]) {
    test('three pieces not stored in a row at the ${door.name} door never halt '
        'the room nor raise the person sign', () {
      for (final result in _notStored) {
        var machine = Machine(station: station);
        for (var time = 0; time < 3; time++) {
          machine = _decidedAt(machine, result, door).$1;
        }

        expect(machine.halt, const NoHalt(), reason: '$result');
        expect(machine.aHaltWaitsForTheCanvas, isNull, reason: '$result');
      }
    });
  }
}
