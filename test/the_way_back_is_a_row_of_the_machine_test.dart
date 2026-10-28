import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/left_entry.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _onTheChoice = Machine(
  station: Menu(),
  generation: 3,
  panorama: HeldPanorama('OV-Ruth', 'pt', session: 's1'),
);

void main() {
  test('The way back to a Panorama whose line was said, on the session the '
      'room still holds, returns to it in silence and arms the Watch', () {
    final (machine, effects) = reduce(
      _onTheChoice,
      const TheWayBackTaken(
        LeftEntry(
          pericope: 'OV-Ruth',
          panorama: true,
          session: 's1',
          language: 'pt',
          said: true,
        ),
      ),
    );

    expect(machine.station, const Panorama('OV-Ruth'));
    expect(machine.generation, greaterThan(_onTheChoice.generation));
    expect(effects, contains(const ArmTheWatch()));
    expect(effects, contains(const ReturnToThePanorama()));
    expect(effects.whereType<OpenThePanorama>(), isEmpty);
  });

  test('The way back to a Panorama whose line was not said asks for it again '
      'in the language it was left in', () {
    final (machine, effects) = reduce(
      _onTheChoice,
      const TheWayBackTaken(
        LeftEntry(
          pericope: 'OV-Ruth',
          panorama: true,
          session: 's1',
          language: 'en',
          said: false,
        ),
      ),
    );

    expect(machine.station, const Panorama('OV-Ruth'));
    expect(effects, contains(const OpenThePanorama('OV-Ruth', 'en')));
    expect(effects.whereType<ReturnToThePanorama>(), isEmpty);
  });

  test('The way back to a Panorama whose session the room let go asks for it '
      'again', () {
    for (final held in const [
      HeldPanorama('OV-Ruth', 'pt'),
      HeldPanorama('OV-Ruth', 'pt', session: 's9'),
    ]) {
      final (machine, effects) = reduce(
        Machine(station: const Menu(), panorama: held),
        const TheWayBackTaken(
          LeftEntry(
            pericope: 'OV-Ruth',
            panorama: true,
            session: 's1',
            language: 'pt',
            said: true,
          ),
        ),
      );

      expect(machine.station, const Panorama('OV-Ruth'));
      expect(effects, contains(const OpenThePanorama('OV-Ruth', 'pt')));
      expect(effects, isNot(contains(const ArmTheWatch())));
    }
  });

  test('The way back to a passage enters it again in the language it was '
      'left in', () {
    const left = LeftEntry(
      book: 'Ruth',
      pericope: 'P01',
      session: 's2',
      language: 'en',
      held: Paused(PartSound(0, 'parte-0.m4a')),
    );

    final (machine, effects) = reduce(
      _onTheChoice,
      const TheWayBackTaken(left),
    );

    expect(effects, const [EnterThePassageLeft(left)]);
    expect(machine.station, const Menu());
  });
}
