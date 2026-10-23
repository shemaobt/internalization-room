import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _generation = 7;

const _thePlan = Ensaio(step: EnsaioStep.plan);

Machine _at(Station station) =>
    Machine(station: station, generation: _generation);

void main() {
  test('the plan opened from the Canvas reaches the Ensaio Final plan', () {
    final (machine, effects) = reduce(
      _at(const Canvas()),
      const ThePlanOpened(),
    );

    expect(machine.station, _thePlan);
    expect(machine.generation, _generation + 1);
    expect(effects, isEmpty);
  });

  test('the plan opened from any other Station changes nothing', () {
    for (final from in const <Station>[
      Menu(),
      Panorama('OV-Ruth'),
      Retro(),
      Fim(),
      SceneRehearsal(),
      Ensaio(),
    ]) {
      final (machine, _) = reduce(_at(from), const ThePlanOpened());

      expect(machine.station, from, reason: '$from');
      expect(machine.generation, _generation, reason: '$from');
    }
  });

  test('the rehearsal opened from the plan reaches the recording home', () {
    final (machine, _) = reduce(_at(_thePlan), const TheRehearsalOpened());

    expect(machine.station, const Ensaio());
    expect(machine.generation, _generation + 1);
  });

  test('the back-translation asked from the plan stays on the plan, every '
      'scene with its part', () {
    final (machine, _) = reduce(
      _at(const Ensaio(step: EnsaioStep.plan, everySceneHasItsPart: true)),
      const TheBackTranslationOpened(),
    );

    expect(machine.station, _thePlan);
    expect(machine.generation, _generation);
  });

  test('weighing the rehearsal keeps the plan', () {
    final (machine, _) = reduce(
      _at(_thePlan),
      const TheRehearsalWeighed(
        everySceneHasItsPart: true,
        everyPartIsHere: true,
      ),
    );

    expect(machine.station, _thePlan);
  });
}
