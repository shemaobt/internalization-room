import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

void main() {
  test('A session opened at the Conversation arms the Watch and is the '
      'Station\'s session', () {
    final (machine, effects) = reduce(
      const Machine(station: Canvas()),
      const TheSessionOpened('s2', generation: 0),
    );

    expect(machine.stationSession, 's2');
    expect(effects, contains(const ArmTheWatch()));
  });

  test('A session opened at the Panorama arms the Watch and is held with the '
      'Panorama', () {
    const atThePanorama = Machine(
      station: Panorama('OV-Ruth'),
      generation: 2,
      panorama: HeldPanorama('OV-Ruth', 'pt'),
    );

    final (machine, effects) = reduce(
      atThePanorama,
      const TheSessionOpened('s1', generation: 2),
    );

    expect(machine.panorama?.session, 's1');
    expect(machine.stationSession, 's1');
    expect(effects, contains(const ArmTheWatch()));
    expect(
      reduce(atThePanorama, const TheSessionOpened('s1', generation: 1)).$1,
      same(atThePanorama),
    );
  });

  test('The Station\'s session is the Panorama\'s at the Panorama and the '
      'passage\'s elsewhere', () {
    const held = HeldPanorama('OV-Ruth', 'pt', session: 's1');

    expect(
      const Machine(station: Menu(), panorama: held).stationSession,
      isNull,
    );
    expect(
      const Machine(
        station: Panorama('OV-Ruth'),
        session: 's2',
        panorama: held,
      ).stationSession,
      's1',
    );
    expect(
      const Machine(
        station: Canvas(),
        session: 's2',
        panorama: held,
      ).stationSession,
      's2',
    );
  });
}
