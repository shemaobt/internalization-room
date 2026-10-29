import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _chosen = Machine(
  station: Panorama('OV-Ruth'),
  generation: 3,
  panorama: HeldPanorama('OV-Ruth', 'pt', session: 's1'),
);

void main() {
  test('A Panorama chosen whose session the room says was opened rests on '
      'it, asks nothing and arms the Watch', () {
    final (machine, effects) = reduce(
      _chosen,
      const ThePanoramaFound('s1', opened: true),
    );

    expect(
      machine.panorama,
      const HeldPanorama('OV-Ruth', 'pt', session: 's1'),
    );
    expect(effects, contains(const ArmTheWatch()));
    expect(effects, contains(const RestOnThePanorama()));
    expect(effects.whereType<OpenThePanorama>(), isEmpty);
  });

  test('A Panorama chosen whose session was never opened is asked for, not '
      'rested on', () {
    final (machine, effects) = reduce(
      _chosen,
      const ThePanoramaFound('s1', opened: false),
    );

    expect(
      machine.panorama,
      const HeldPanorama('OV-Ruth', 'pt', session: 's1'),
    );
    expect(effects, contains(const OpenThePanorama('OV-Ruth', 'pt')));
    expect(effects.whereType<RestOnThePanorama>(), isEmpty);
  });

  test('The first Panorama of a launch holds the session the room found for '
      'it, opened or not', () {
    const first = Machine(
      station: Panorama('OV-Ruth'),
      generation: 3,
      panorama: HeldPanorama('OV-Ruth', 'pt'),
    );

    for (final opened in const [true, false]) {
      final (machine, effects) = reduce(
        first,
        ThePanoramaFound('s7', opened: opened),
      );

      expect(
        machine.panorama,
        const HeldPanorama('OV-Ruth', 'pt', session: 's7'),
      );
      expect(effects, contains(const ArmTheWatch()));
    }
  });
}
