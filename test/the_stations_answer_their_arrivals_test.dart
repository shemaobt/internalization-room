import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
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

const _aGivenUpTurn = Turn('sessao-1', 'turno-1');

Machine _lookingAt(Machine machine) =>
    machine.copyWith(look: const TheLook(_aGivenUpTurn));

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
        const ThePanoramaChosen('OV-Ruth'),
        isA<Panorama>(),
      );
    });
  });

  test('choosing a Panorama brings the room to that Panorama\'s Station', () {
    final (machine, _) = reduce(
      _at(const Menu()),
      const ThePanoramaChosen('OV-Jonah'),
    );

    expect(
      machine.station,
      isA<Panorama>().having((station) => station.id, 'id', 'OV-Jonah'),
    );
  });

  test('choosing another Panorama at a Panorama brings the room to the one '
      'chosen', () {
    final (machine, _) = reduce(
      _at(const Panorama('OV-Ruth')),
      const ThePanoramaChosen('OV-Jonah'),
    );

    expect(
      machine.station,
      isA<Panorama>().having((station) => station.id, 'id', 'OV-Jonah'),
    );
  });

  test('the Menu ignores an event that is not its own', () {
    for (final event in _notTheirOwn) {
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
    for (final event in _notTheirOwn) {
      _expectItStays(const Canvas(), event, isA<Canvas>());
    }
  });

  group('the Panorama, the Rehearsal, the Back-translation and the Closing '
      'answer their arrivals', () {
    test('the Panorama', () {
      _expectTheArrival(
        const Panorama('OV-Ruth'),
        const TheChoiceOpened(),
        isA<Menu>(),
      );
      _expectTheArrival(
        const Panorama('OV-Ruth'),
        const PassageChosen(),
        isA<Canvas>(),
      );
      _expectTheArrival(
        const Panorama('OV-Ruth'),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
      _expectTheArrival(
        const Panorama('OV-Ruth'),
        const TheBackTranslationOpened(),
        isA<Retro>(),
      );
      _expectTheArrival(
        const Panorama('OV-Ruth'),
        const TheRoomStartedOver(),
        isA<Menu>(),
      );
    });

    test('the Rehearsal', () {
      _expectTheArrival(
        const Ensaio(everySceneHasItsPart: true),
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
    });

    test('the Back-translation', () {
      _expectTheArrival(
        const Retro(),
        const TheRehearsalOpened(),
        isA<Ensaio>(),
      );
      _expectTheArrival(const Retro(), const TheChoiceOpened(), isA<Menu>());
      _expectTheArrival(const Retro(), const PassageChosen(), isA<Canvas>());
      _expectTheArrival(const Retro(), const TheRoomStartedOver(), isA<Menu>());
    });

    test('both recording screens leave for the conversation, the '
        'Back-translation as much as the home', () {
      _expectTheArrival(
        const Ensaio(),
        const TheRecordingLeft(),
        isA<Canvas>(),
      );
      _expectTheArrival(const Retro(), const TheRecordingLeft(), isA<Canvas>());
    });
  });

  test('an arrival at the Station already held moves nothing', () {
    _expectItStays(const Menu(), const TheChoiceOpened(), isA<Menu>());
    _expectItStays(const Canvas(), const PassageChosen(), isA<Canvas>());
    _expectItStays(
      const Panorama('OV-Ruth'),
      const ThePanoramaChosen('OV-Ruth'),
      isA<Panorama>(),
    );
    _expectItStays(const Menu(), const TheRoomStartedOver(), isA<Menu>());
    _expectItStays(const Ensaio(), const TheRehearsalOpened(), isA<Ensaio>());
    _expectItStays(
      const Retro(),
      const TheBackTranslationOpened(),
      isA<Retro>(),
    );
  });

  test(
    'the Canvas answers the scene rehearsal opened with the Scene rehearsal',
    () {
      _expectTheArrival(
        const Canvas(),
        const TheSceneRehearsalOpened(),
        isA<SceneRehearsal>(),
      );
    },
  );

  test('the Scene rehearsal answers the way back with the Canvas', () {
    _expectTheArrival(
      const SceneRehearsal(),
      const TheSceneRehearsalLeft(),
      isA<Canvas>(),
    );
  });

  test(
    'the Rehearsal does not open the Back-translation while a scene has no part',
    () {
      _expectItStays(
        const Ensaio(),
        const TheBackTranslationOpened(),
        isA<Ensaio>(),
      );
    },
  );

  test('the Rehearsal weighed with a part still in the Outbox does not open '
      'the Back-translation, as hers', () {
    final (weighed, _) = reduce(
      _at(const Ensaio()),
      const TheRehearsalWeighed(
        everySceneHasItsPart: true,
        everyPartIsSent: false,
      ),
    );

    expect(
      reduce(weighed, const TheBackTranslationOpened()).$1.station,
      isA<Ensaio>(),
      reason:
          'a tradução abria com uma parte ainda na fila de envio, e a dela '
          'espera a sala ter todas',
    );
  });

  test('the Rehearsal weighed keeps its Station and its generation', () {
    final (weighed, effects) = reduce(
      _at(const Ensaio()),
      const TheRehearsalWeighed(
        everySceneHasItsPart: true,
        everyPartIsSent: true,
      ),
    );

    expect(weighed.generation, _generation);
    expect(effects, isEmpty);
    expect(
      reduce(weighed, const TheBackTranslationOpened()).$1.station,
      isA<Retro>(),
      reason: 'weighed whole, the Rehearsal opens the Back-translation',
    );
  });

  test(
    'the Ensaio Final plan answers the scene rehearsal opened with the Scene '
    'rehearsal',
    () {
      _expectTheArrival(
        const Ensaio(step: EnsaioStep.plan),
        const TheSceneRehearsalOpened(),
        isA<SceneRehearsal>(),
      );
    },
  );

  test('the recording home answers the scene rehearsal opened with the Scene '
      'rehearsal, as the plan does', () {
    _expectTheArrival(
      const Ensaio(),
      const TheSceneRehearsalOpened(),
      isA<SceneRehearsal>(),
    );
  });

  test('every other Station ignores the scene rehearsal opened', () {
    for (final station in const <Station>[
      Menu(),
      Panorama('OV-Ruth'),
      Retro(),
      ChecagemExterna(1),
    ]) {
      _expectItStays(station, const TheSceneRehearsalOpened(), equals(station));
    }
  });

  test(
    'the Back-translation answers the external check opened with the Checagem '
    'externa of that version',
    () {
      _expectTheArrival(
        const Retro(),
        const TheExternalCheckOpened(3),
        equals(const ChecagemExterna(3)),
      );
    },
  );

  test(
    'the Checagem externa answers the way back with the Back-translation',
    () {
      _expectTheArrival(
        const ChecagemExterna(3),
        const TheExternalCheckLeft(),
        isA<Retro>(),
      );
    },
  );

  test('the recording home answers the external check opened with the Checagem '
      'externa of that version', () {
    _expectTheArrival(
      const Ensaio(),
      const TheExternalCheckOpened(3),
      equals(const ChecagemExterna(3, fromTheHome: true)),
    );
  });

  test('the Checagem externa leaves to the door it was opened from', () {
    _expectTheArrival(
      const ChecagemExterna(3, fromTheHome: true),
      const TheExternalCheckLeft(),
      isA<Ensaio>(),
    );
    _expectTheArrival(
      const ChecagemExterna(3),
      const TheExternalCheckLeft(),
      isA<Retro>(),
    );
  });

  test('every other Station ignores the external check opened', () {
    for (final station in const <Station>[
      Menu(),
      Panorama('OV-Ruth'),
      Canvas(),
      SceneRehearsal(),
    ]) {
      _expectItStays(station, const TheExternalCheckOpened(3), equals(station));
    }
  });

  test(
    'every Station but the Checagem externa ignores the external check left',
    () {
      for (final station in const <Station>[
        Menu(),
        Panorama('OV-Ruth'),
        Canvas(),
        Ensaio(),
        Retro(),
        SceneRehearsal(),
      ]) {
        _expectItStays(station, const TheExternalCheckLeft(), equals(station));
      }
    },
  );

  test(
    'the Scene rehearsal shows a list of its rehearsals the room answered',
    () {
      const listed = [
        SceneRehearsalRecord(
          rehearsalId: 'ensaio-da-cena-1',
          sessionId: 'sessao-1',
          n: 1,
        ),
      ];
      final (machine, effects) = reduce(
        _at(const SceneRehearsal()),
        const TheSceneRehearsalsListed(listed, generation: _generation),
      );

      expect(machine.generation, _generation);
      expect(
        effects.single,
        isA<ShowTheSceneRehearsals>().having((e) => e.listed, 'listed', listed),
      );
    },
  );

  test('a list of scene rehearsals from an older generation is dropped', () {
    final (_, effects) = reduce(
      _at(const SceneRehearsal()),
      const TheSceneRehearsalsListed([], generation: _generation - 1),
    );

    expect(effects, isEmpty);
  });

  test('the way back from the Scene rehearsal carries the turn in flight and '
      'its look to the Canvas', () {
    for (final sending in [
      _at(const SceneRehearsal()).copyWith(inFlight: _aGivenUpTurn),
      _lookingAt(_at(const SceneRehearsal())),
    ]) {
      final (machine, _) = reduce(sending, const TheSceneRehearsalLeft());

      expect(machine.station, isA<Canvas>());
      expect(machine.generation, _generation);
      expect(machine.inFlight, sending.inFlight);
      expect(machine.look, sending.look);
    }
  });

  test('the scene screen closing over its reply keeps the generation, and a '
      'halt raised during the flash lands at the close and silences the line, '
      'as any halt on the Canvas', () {
    const reply = Line(LineKind.guide, 1, url: '/voice/resposta');
    final (flashing, _) = reduce(
      _at(const SceneRehearsal()).copyWith(channel: const GuideSpeaking(reply)),
      const RoomRaisedAHalt(),
    );

    final (closed, _) = reduce(
      flashing,
      const TheSceneRehearsalLeft(keepsTheReply: true),
    );

    expect(closed.station, isA<Canvas>());
    expect(closed.generation, _generation);
    expect(closed.halt, isA<Blocking>());
    expect(closed.channel, isA<Silence>());
  });

  test('the scene screen closing over its reply with no halt keeps the line '
      'playing', () {
    const reply = Line(LineKind.guide, 1, url: '/voice/resposta');

    final (closed, _) = reduce(
      _at(const SceneRehearsal()).copyWith(channel: const GuideSpeaking(reply)),
      const TheSceneRehearsalLeft(keepsTheReply: true),
    );

    expect(closed.generation, _generation);
    expect(closed.channel, isA<GuideSpeaking>());
  });

  test('the sign held on the scene screen shows when the team is back on the '
      'Canvas', () {
    final (held, heldEffects) = reduce(
      _lookingAt(_at(const SceneRehearsal())),
      const LookEmpty(_aGivenUpTurn, generation: _generation),
    );

    expect(held.halt, isNot(isA<Blocking>()));
    expect(heldEffects, contains(const ReadTheSceneRehearsals()));
    expect(heldEffects, contains(const LetTheStepGo()));

    final (back, backEffects) = reduce(held, const TheSceneRehearsalLeft());

    expect(back.station, isA<Canvas>());
    expect(back.halt, isA<Blocking>());
    expect(back.channel, isA<Silence>());
    expect(backEffects, contains(const CallForAPerson()));
  });

  test('a scene rehearsal sent again forgets the sign held for the Canvas', () {
    const turn = Turn('sessao-1', 'turno-8');
    var (machine, _) = reduce(
      _at(const SceneRehearsal()),
      const TheSceneTurnFoundNothing(generation: _generation),
    );
    for (final event in const <MachineEvent>[
      TurnSent(turn),
      TurnAnswered(turn),
      TheSceneRehearsalLeft(),
    ]) {
      (machine, _) = reduce(machine, event);
    }

    expect(machine.station, isA<Canvas>());
    expect(machine.halt, isNot(isA<Blocking>()));
  });

  test('a held sign is forgotten with the passage', () {
    final (held, _) = reduce(
      _at(const SceneRehearsal()),
      const TheSceneTurnFoundNothing(generation: _generation),
    );
    for (final away in <List<MachineEvent>>[
      [const TheSessionIsGone(), const PassageChosen()],
      [const TheChoiceOpened(), const PassageChosen()],
      [
        const TheChoiceOpened(),
        const PassageChosen(),
        const TheSceneRehearsalOpened(),
        const TheSceneRehearsalLeft(),
      ],
    ]) {
      var machine = held;
      for (final event in away) {
        (machine, _) = reduce(machine, event);
        expect(
          machine.halt,
          isNot(isA<Blocking>()),
          reason: away.map((event) => event.runtimeType).join(' → '),
        );
      }
      expect(machine.station, isA<Canvas>());
    }
  });

  test('a scene look that finds nothing once the screen closed shows the sign '
      'at once', () {
    final (machine, effects) = reduce(
      _lookingAt(_at(const Canvas())),
      const LookEmpty(_aGivenUpTurn, generation: _generation),
    );

    expect(machine.halt, isA<Blocking>());
    expect(effects, isNot(contains(const ReadTheSceneRehearsals())));
  });

  test(
    'a resume that failed goes back to the Choice and keeps its session',
    () {
      final (_, effects) = reduce(
        _at(const Canvas()),
        const TheResumeFailed(generation: _generation),
      );

      expect(effects, contains(const OpenTheChoice()));
      expect(effects, isNot(contains(const DiscardTheSession())));
    },
  );

  test('the machine is born on the Menu', () {
    expect(Machine().station, isA<Menu>());
  });

  test('every Station answers the Panorama chosen with the Panorama, and the '
      'room started over with the Menu', () {
    const everyStation = <Station>[
      Menu(),
      Panorama('OV-Ruth'),
      Canvas(),
      Ensaio(),
      Retro(),
      ChecagemExterna(1),
    ];
    for (final station in everyStation) {
      expect(
        reduce(_at(station), const ThePanoramaChosen('OV-Ruth')).$1.station,
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
