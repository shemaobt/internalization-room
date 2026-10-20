import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _held = Machine(
  station: Panorama('OV-Ruth'),
  session: 's2',
  panorama: HeldPanorama('OV-Ruth', 'pt', session: 's1'),
);

void main() {
  test('Asking for the Panorama the machine holds, in the same language, keeps '
      'its session', () {
    final (machine, _) = reduce(_held, const ThePanoramaAsked('OV-Ruth', 'pt'));

    expect(
      machine.panorama,
      const HeldPanorama('OV-Ruth', 'pt', session: 's1'),
    );
  });

  test('Asking for it in another language, or for another Panorama, lets its '
      'session go', () {
    expect(
      reduce(_held, const ThePanoramaAsked('OV-Ruth', 'en')).$1.panorama,
      const HeldPanorama('OV-Ruth', 'en'),
    );
    expect(
      reduce(_held, const ThePanoramaAsked('OV-Jonah', 'pt')).$1.panorama,
      const HeldPanorama('OV-Jonah', 'pt'),
    );
  });

  test(
    'The Choice keeps the Panorama the machine holds, and a session the room '
    'let go leaves it',
    () {
      final onTheChoice = _held.withNoPassage(const {});

      expect(onTheChoice.panorama, _held.panorama);
      expect(onTheChoice.session, isNull);
      expect(
        reduce(onTheChoice, const TheSessionLetGo('s1')).$1.panorama,
        const HeldPanorama('OV-Ruth', 'pt'),
      );
      expect(
        reduce(onTheChoice, const TheSessionLetGo('other')).$1,
        same(onTheChoice),
      );
    },
  );
}
