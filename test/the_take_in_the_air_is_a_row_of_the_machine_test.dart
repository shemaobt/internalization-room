import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'a_station_host_double.dart';
import 'fake_ports.dart';

final _partTwo = TakeInTheAir(
  row: 'linha-2',
  keep: (
    session: 's1',
    kind: 'ensaio',
    scope: 'parte-2',
    since: DateTime.utc(2026, 10, 22, 9),
  ),
);

const _inThePassage = Machine(station: Canvas(), session: 's1');

void main() {
  test('a take that leaves the Outbox is the take in the air until it '
      'settles', () {
    final (leaving, _) = reduce(_inThePassage, ATakeLeft(_partTwo));
    expect(leaving.inTheAir, _partTwo);

    final (another, _) = reduce(leaving, const ATakeSettled('linha-3'));
    expect(another.inTheAir, _partTwo);

    final (settled, _) = reduce(another, const ATakeSettled('linha-2'));
    expect(settled.inTheAir, isNull);
  });

  test("a stop tapped on this session's take in the air stops that take", () {
    final (_, effects) = reduce(
      _inThePassage.copyWith(inTheAir: _partTwo),
      StopTapped(_partTwo.keep),
    );

    expect(effects, [const StopTheSend('linha-2')]);
  });

  test('a stop tapped as one take of a keep hands over to the next stops the '
      'next', () {
    final next = TakeInTheAir(
      row: 'linha-3',
      keep: (
        session: 's1',
        kind: 'ensaio',
        scope: 'parte-2',
        since: _partTwo.keep.since,
      ),
    );
    final (_, effects) = reduce(
      _inThePassage.copyWith(inTheAir: next),
      StopTapped(_partTwo.keep),
    );

    expect(effects, [const StopTheSend('linha-3')]);
  });

  test("a stop tapped in an earlier pass of the same part stops nothing in a "
      'later one', () {
    final later = TakeInTheAir(
      row: 'linha-2',
      keep: (
        session: 's1',
        kind: 'ensaio',
        scope: 'parte-2',
        since: _partTwo.keep.since.add(const Duration(minutes: 1)),
      ),
    );
    final (_, effects) = reduce(
      _inThePassage.copyWith(inTheAir: later),
      StopTapped(_partTwo.keep),
    );

    expect(effects.whereType<StopTheSend>(), isEmpty);
  });

  test('a stop tapped on a take no longer in the air stops nothing', () {
    for (final machine in [
      _inThePassage,
      _inThePassage.copyWith(
        inTheAir: TakeInTheAir(
          row: 'linha-3',
          keep: (
            session: 's1',
            kind: 'ensaio',
            scope: 'parte-3',
            since: DateTime.utc(2026, 10, 22, 9),
          ),
        ),
      ),
    ]) {
      final (_, effects) = reduce(machine, StopTapped(_partTwo.keep));

      expect(effects.whereType<StopTheSend>(), isEmpty);
    }
  });

  test("a stop tapped on another session's take in the air stops nothing", () {
    final (_, effects) = reduce(
      _inThePassage.copyWith(session: 's2', inTheAir: _partTwo),
      StopTapped(_partTwo.keep),
    );

    expect(effects.whereType<StopTheSend>(), isEmpty);
  });

  test('the runner hands a stop to the Outbox naming its take', () {
    final store = AStorePort();
    final runner = EffectRunner(
      room: ARoomPort(),
      sound: ASoundPort(),
      recorder: ARecorderPort(),
      store: store,
      host: AStationHost(),
      watchPeriod: () => const Duration(seconds: 30),
      retryDelay: (_) => Duration.zero,
      partCeiling: () => null,
      clipGrace: () => Duration.zero,
      lookAgainAfter: () => Duration.zero,
    );

    runner.run(const [StopTheSend('linha-2')]);

    expect(store.stopped, ['linha-2']);
  });
}
