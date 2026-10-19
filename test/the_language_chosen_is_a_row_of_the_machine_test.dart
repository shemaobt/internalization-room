import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _chosen = TheLanguageChosen();

void main() {
  test('A language chosen on the Choice reads the Wheel again and drops every '
      'answer still in the air.', () {
    const onTheChoice = Machine(station: Menu(), generation: 4);

    final (machine, effects) = reduce(onTheChoice, _chosen);

    expect(effects, const [ReadTheWheel()]);
    expect(
      reduce(machine, const TheRoomAnswered(generation: 4)).$1,
      same(machine),
    );
  });

  test('A language chosen anywhere but the Choice changes nothing.', () {
    for (final station in const <Station>[
      Canvas(),
      Ensaio(),
      Retro(),
      Panorama('OV-Ruth'),
      Fim(),
    ]) {
      final standing = Machine(station: station);

      final (machine, effects) = reduce(standing, _chosen);

      expect(machine, same(standing));
      expect(effects, isEmpty);
    }
  });
}
