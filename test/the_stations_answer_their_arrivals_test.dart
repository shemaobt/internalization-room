import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _generation = 7;

Machine _at(Station station) =>
    Machine(station: station, generation: _generation);

final _notTheirOwn = <MachineEvent>[
  const BeadTapped([PartSound(0, 'parte-0.m4a')]),
  const PlayerEnded(),
  SessionRead(
    const SessionSnapshot(
      sessionId: 'sessao-1',
      pericope: 'rute-1',
      status: 'in_progress',
      coverage: null,
      done: false,
    ),
  ),
];

void _expectTheArrival(Station from, StationEvent arrival, Matcher station) {
  final (machine, effects) = reduce(_at(from), arrival);
  expect(machine.station, station);
  expect(machine.generation, _generation + 1);
  expect(effects, isEmpty);
}

void _expectItStays(Station at, MachineEvent event, Matcher station) {
  final (machine, _) = reduce(_at(at), event);
  expect(machine.station, station);
  expect(machine.generation, _generation);
}

void main() {
  test('the Menu answers the passage being chosen with the Canvas', () {
    _expectTheArrival(const Menu(), const PassageChosen(), isA<Canvas>());
  });

  group('the Menu answers every other arrival with the Station it names', () {
    test('the rehearsal opened: the Rehearsal', () {
      _expectTheArrival(
        const Menu(),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
    });

    test('the back-translation opened: the Back-translation', () {
      _expectTheArrival(
        const Menu(),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
    });

    test('the Panorama chosen: the Panorama', () {
      _expectTheArrival(
        const Menu(),
        const ThePanoramaChosen(),
        isA<Panorama>(),
      );
    });
  });

  test('the Menu ignores an event that is not its own', () {
    for (final event in [..._notTheirOwn, const TheNecklaceClosed()]) {
      _expectItStays(const Menu(), event, isA<Menu>());
    }
  });

  group('the Canvas answers its arrivals with the Station they name', () {
    test('the rehearsal opened: the Rehearsal', () {
      _expectTheArrival(
        const Canvas(),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
    });

    test('the back-translation opened on a resume: the Back-translation', () {
      _expectTheArrival(
        const Canvas(),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
    });

    test('the Choice opened: the Menu', () {
      _expectTheArrival(const Canvas(), const TheChoiceOpened(), isA<Menu>());
    });

    test('the room started over: the Menu', () {
      _expectTheArrival(
        const Canvas(),
        const TheRoomStartedOver(),
        isA<Menu>(),
      );
    });
  });

  test('the Canvas ignores an event that is not its own', () {
    for (final event in [..._notTheirOwn, const TheNecklaceClosed()]) {
      _expectItStays(const Canvas(), event, isA<Canvas>());
    }
  });

  group('the Panorama, the Rehearsal, the Back-translation and the Closing '
      'answer their arrivals', () {
    test('the Panorama', () {
      _expectTheArrival(const Panorama(), const TheChoiceOpened(), isA<Menu>());
      _expectTheArrival(const Panorama(), const PassageChosen(), isA<Canvas>());
      _expectTheArrival(
        const Panorama(),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
      _expectTheArrival(
        const Panorama(),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
      _expectTheArrival(
        const Panorama(),
        const TheRoomStartedOver(),
        isA<Menu>(),
      );
      _expectItStays(
        const Panorama(),
        const TheNecklaceClosed(),
        isA<Panorama>(),
      );
    });

    test('the Rehearsal', () {
      _expectTheArrival(
        const Ensaio(),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
      _expectTheArrival(const Ensaio(), const TheChoiceOpened(), isA<Menu>());
      _expectTheArrival(const Ensaio(), const PassageChosen(), isA<Canvas>());
      _expectTheArrival(
        const Ensaio(),
        const TheRoomStartedOver(),
        isA<Menu>(),
      );
      _expectItStays(const Ensaio(), const TheNecklaceClosed(), isA<Ensaio>());
    });

    test('the Back-translation', () {
      _expectTheArrival(const Retro(), const TheNecklaceClosed(), isA<Fim>());
      _expectTheArrival(
        const Retro(),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
      _expectTheArrival(const Retro(), const TheChoiceOpened(), isA<Menu>());
      _expectTheArrival(const Retro(), const PassageChosen(), isA<Canvas>());
      _expectTheArrival(const Retro(), const TheRoomStartedOver(), isA<Menu>());
    });

    test('the Closing', () {
      _expectTheArrival(const Fim(), const TheRoomStartedOver(), isA<Menu>());
      _expectTheArrival(const Fim(), const TheChoiceOpened(), isA<Menu>());
      _expectTheArrival(const Fim(), const PassageChosen(), isA<Canvas>());
      _expectTheArrival(const Fim(), const TheRehearsalOpened(), isA<Ensaio>());
      _expectTheArrival(
        const Fim(),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
    });
  });

  test('an arrival at the Station already held moves nothing', () {
    _expectItStays(const Menu(), const TheChoiceOpened(), isA<Menu>());
    _expectItStays(const Canvas(), const PassageChosen(), isA<Canvas>());
    _expectItStays(
      const Panorama(),
      const ThePanoramaChosen(),
      isA<Panorama>(),
    );
    _expectItStays(const Menu(), const TheRoomStartedOver(), isA<Menu>());
    _expectItStays(const Ensaio(), const TheRehearsalOpened(), isA<Ensaio>());
    _expectItStays(
      const Retro(),
      const TheBackTranslationOpened(),
      isA<Retro>(),
    );
    _expectItStays(const Fim(), const TheNecklaceClosed(), isA<Fim>());
  });

  test('the machine is born on the Menu', () {
    expect(Machine().station, isA<Menu>());
  });

  test('every Station answers the Panorama chosen with the Panorama, and the '
      'room started over with the Menu', () {
    const everyStation = <Station>[
      Menu(),
      Panorama(),
      Canvas(),
      Ensaio(),
      Retro(),
      Fim(),
    ];
    for (final station in everyStation) {
      expect(
        reduce(_at(station), const ThePanoramaChosen()).$1.station,
        isA<Panorama>(),
        reason: '$station',
      );
      expect(
        reduce(_at(station), const TheRoomStartedOver()).$1.station,
        isA<Menu>(),
        reason: '$station',
      );
    }
  });
}
