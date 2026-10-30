import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/left_entry.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

const _held = LeftEntry(pericope: 'P01', book: 'Ruth', session: 's1');

SalaSessionState _theChoiceHolding({bool voiceBusy = false}) =>
    SalaSessionState(
      leftEntry: _held,
      awaitingTheGuide: voiceBusy,
      machine: const Machine(waiting: _held),
    );

void main() {
  test('the Choice shows the way back to a held session before the Wheel is '
      'read, and keeps it live while the voice is busy', () {
    for (final busy in [false, true]) {
      final choice = _theChoiceHolding(voiceBusy: busy);

      expect(choice.naRoda, isNull);
      expect(choice.theWayBackIsOffered, isTrue);
      expect(choice.theWayBackIsLive, isTrue, reason: 'voiceBusy: $busy');
    }
  });

  test('the Choice offers no way back with nothing held', () {
    const choice = SalaSessionState();

    expect(choice.theWayBackIsOffered, isFalse);
  });
}
