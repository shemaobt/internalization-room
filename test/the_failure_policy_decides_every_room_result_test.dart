import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'machine_generator.dart';

const _turn = Turn('sessao-1', 'turno-7');
const _kept = TheOpening();

final _aTurn = FailureContext(
  station: Station.stored(SalaStage.conversa),
  generation: 4,
  turn: _turn,
  rule: RefusalRule.aSpokenTurn,
);

final _theOpening = FailureContext(
  station: Station.stored(SalaStage.conversa),
  generation: 4,
  rule: RefusalRule.aSpokenTurn,
  sounding: _kept,
);

FailureContext _notATurn({
  RefusalRule rule = RefusalRule.letsTheStepGo,
  Door door = Door.outbox,
  RoomReach why = RoomReach.noNetwork,
}) => FailureContext(
  station: Station.stored(SalaStage.retro),
  step: BtPhase.thinking,
  generation: 4,
  door: door,
  why: why,
  rule: rule,
  sounding: const ThePart(),
);

FailureContext _at(
  Station station, {
  Turn? turn,
  RefusalRule rule = RefusalRule.letsTheStepGo,
  Door door = Door.step,
  Kept sounding = const NothingKept(),
}) => FailureContext(
  station: station,
  generation: 4,
  turn: turn,
  rule: rule,
  door: door,
  sounding: sounding,
);

String _said(MachineEvent event) => switch (event) {
  final AnsweringEvent answer =>
    '${describeEvent(answer)} @${answer.generation}',
  _ => describeEvent(event),
};

void _decides(RoomResult result, FailureContext context, MachineEvent event) =>
    expect(
      _said(FailurePolicy.decide(result, context)),
      _said(event),
      reason: '${result.runtimeType} at ${context.station.stage.name}',
    );

void _decidesOnTheTablet(
  TabletFailure failure,
  FailureContext context,
  MachineEvent event,
) => expect(
  _said(FailurePolicy.decideOnTheTablet(failure, context)),
  _said(event),
);

void main() {
  group('only her six cases bring the person sign', () {
    test('a spoken turn the room refuses brings the person sign, whatever the '
        'code', () {
      for (final code in [
        RefusalCode.unnamed(500),
        RefusalCode.deviceRevoked,
        'TURN_COLLISION',
      ]) {
        _decides(
          RoomRefused(code),
          _aTurn,
          const RoomRaisedAHalt(generation: 4),
        );
      }
    });

    test('a Panorama turn the room refuses brings the person sign', () {
      _decides(
        RoomRefused(RefusalCode.unnamed(500)),
        _at(
          const Panorama('OV-Ruth'),
          turn: _turn,
          rule: RefusalRule.aSpokenTurn,
        ),
        const RoomRaisedAHalt(generation: 4),
      );
    });

    test('a spoken turn answered without a reply brings the person sign', () {
      _decides(
        const RoomAnsweredWithoutAReply(),
        _aTurn,
        const RoomRaisedAHalt(generation: 4),
      );
    });

    test('an opening answered without a reply rests at the invite', () {
      _decides(
        const RoomAnsweredWithoutAReply(),
        _theOpening,
        const TheOpeningMissed(generation: 4),
      );
    });

    test('a spoken turn given up whose look finds nothing brings the person '
        'sign', () {
      _decides(
        const RoomFoundNothing(),
        _at(const Canvas(), turn: _turn),
        const RoomRaisedAHalt(generation: 4),
      );
    });

    test('a look over an opening that finds nothing rests at the invite', () {
      _decides(
        const RoomFoundNothing(),
        _at(const Canvas(), turn: _turn, sounding: _kept),
        const TheOpeningMissed(generation: 4),
      );
    });

    test('a scene rehearsal given up whose look finds nothing keeps its screen '
        'and holds the sign for the Canvas', () {
      _decides(
        const RoomFoundNothing(),
        _at(const SceneRehearsal(), turn: _turn),
        const TheSceneTurnFoundNothing(generation: 4),
      );
    });

    test('the reply\'s sound failing once brings nothing; twice brings the '
        'person sign', () {
      final context = _at(const Canvas(), sounding: const ThePart());
      _decidesOnTheTablet(
        const TheSoundFailed(1),
        context,
        const TheRefusalPassed(generation: 4),
      );
      _decidesOnTheTablet(
        const TheSoundFailed(2),
        context,
        const RoomRaisedAHalt(generation: 4),
      );
    });

    test('a tablet that cannot record brings the person sign', () {
      _decidesOnTheTablet(
        const TheTabletCannotRecord(),
        _at(const Canvas()),
        const RoomRaisedAHalt(generation: 4),
      );
    });

    test('a microphone that fails to start once brings nothing; twice in a row '
        'brings the person sign', () {
      _decidesOnTheTablet(
        const TheMicFailedToStart(1),
        _at(const Canvas()),
        const TheRefusalPassed(generation: 4),
      );
      _decidesOnTheTablet(
        const TheMicFailedToStart(2),
        _at(const Canvas()),
        const RoomRaisedAHalt(generation: 4),
      );
    });
  });

  test('the build guard shows the sign without calling anyone', () {
    _decidesOnTheTablet(
      const TheBuildCannotReachTheRoom(),
      _at(const Menu()),
      const RoomRaisedAHalt(callsForAPerson: false, generation: 4),
    );
  });

  group('nothing else halts the room', () {
    test('a request that is not a spoken turn, refused any number of times and '
        'with any code, lets its Step go and calls nobody', () {
      for (final context in [
        _notATurn(door: Door.step),
        _at(const Menu()),
        _at(const Canvas()),
        _at(const Panorama('OV-Ruth')),
      ]) {
        for (final code in [
          RefusalCode.unnamed(409),
          RefusalCode.forbidden,
          RefusalCode.unauthorized,
          RefusalCode.deviceRevoked,
        ]) {
          _decides(
            RoomRefused(code),
            context,
            const TheStepFailed(generation: 4),
          );
        }
      }
    });

    test('a wait with no turn that timed out lets its Step go', () {
      _decides(
        const RoomTimedOut(),
        _notATurn(),
        const TheStepFailed(generation: 4),
      );
    });

    test('a resume the room refuses or no longer holds goes calmly back to the '
        'passage menu', () {
      final resume = _notATurn(
        door: Door.resume,
        rule: RefusalRule.keepsTheResume,
      );
      for (final result in [
        RoomRefused(RefusalCode.unnamed(500)),
        const RoomSessionGone(),
        const RoomNetworkFailed(),
        const RoomFoundNothing(),
      ]) {
        _decides(result, resume, const TheResumeFailed(generation: 4));
      }
    });

    test('a scene rehearsal refusal the server names keeps the screen\'s own '
        'words and never brings the sign', () {
      for (final code in [
        RefusalCode.sceneRehearsalSent,
        RefusalCode.restartOutOfOrder,
        RefusalCode.notFound,
      ]) {
        _decides(
          RoomRefused(code),
          _notATurn(door: Door.sceneRehearsal),
          const TheSceneDoorFailed(readAgain: true, generation: 4),
        );
      }
      for (final code in [
        RefusalCode.unnamed(409),
        RefusalCode.deviceRevoked,
      ]) {
        _decides(
          RoomRefused(code),
          _notATurn(door: Door.sceneRehearsal),
          const TheSceneDoorFailed(generation: 4),
        );
        _decides(
          RoomRefused(code),
          _notATurn(
            door: Door.sceneRehearsal,
            rule: RefusalRule.readsTheListAgain,
          ),
          const TheSceneDoorFailed(readAgain: true, generation: 4),
        );
      }
    });

    test('a call for a person lost on the network is asked again', () {
      _decides(
        const RoomNetworkFailed(),
        _notATurn(door: Door.person, rule: RefusalRule.asksAgain),
        const TheCallWasRefused(generation: 4),
      );
    });
  });

  final rows = <(String, RoomResult, FailureContext, MachineEvent)>[
    (
      'a turn answered lands the turn in flight',
      const RoomAnswered(),
      _aTurn,
      const TurnAnswered(_turn, generation: 4),
    ),
    (
      'a turn whose network failed is looked at once',
      const RoomNetworkFailed(),
      _aTurn,
      const TurnGivenUp(_turn, generation: 4),
    ),
    (
      'a turn that timed out is looked at once',
      const RoomTimedOut(),
      _aTurn,
      const TurnGivenUp(_turn, generation: 4),
    ),
    (
      'a turn refused because the passage cannot open goes back to the Choice',
      const RoomRefused(RefusalCode.passageCannotOpen),
      _aTurn,
      const ThePassageCannotOpen(generation: 4),
    ),
    (
      'a turn refused calls a person on the spot whatever its family says',
      const RoomRefused(RefusalCode.unreadable),
      FailureContext(
        station: Station.stored(SalaStage.conversa),
        generation: 4,
        turn: _turn,
      ),
      const RoomRaisedAHalt(generation: 4),
    ),
    (
      'an opening refused with any code is missed, not halted',
      const RoomRefused(RefusalCode.unreadable),
      _theOpening,
      const TheOpeningMissed(generation: 4),
    ),
    (
      'an opening refused with a code that once stopped the room is missed, '
          'not halted',
      const RoomRefused(RefusalCode.deviceRevoked),
      _theOpening,
      const TheOpeningMissed(generation: 4),
    ),
    (
      'a turn whose session is gone is the session gone',
      const RoomSessionGone(),
      _aTurn,
      const TheSessionIsGone(generation: 4),
    ),
    (
      'a call that is not a turn answered is the room answering',
      const RoomAnswered(),
      _notATurn(),
      const TheRoomAnswered(generation: 4),
    ),
    (
      'a call that is not a turn whose network failed falls at its door',
      const RoomNetworkFailed(),
      _notATurn(),
      const NetworkFailedAt(Door.outbox, generation: 4),
    ),
    (
      'a call that is not a turn refused because the passage cannot open goes back to the Choice',
      const RoomRefused(RefusalCode.passageCannotOpen),
      _notATurn(),
      const ThePassageCannotOpen(generation: 4),
    ),
    (
      'a wordless telling is its own answer',
      const RoomRefused(RefusalCode.wordlessTelling),
      _notATurn(),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a telling whose network failed is a telling not understood, never out of reach',
      const RoomNetworkFailed(),
      _notATurn(door: Door.telling),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a call that is not a turn whose room is silent falls at its door saying so',
      const RoomNetworkFailed(),
      _notATurn(why: RoomReach.roomSilent),
      const NetworkFailedAt(
        Door.outbox,
        why: RoomReach.roomSilent,
        generation: 4,
      ),
    ),
    (
      'the Watch refused changes nothing, whatever the code',
      const RoomRefused(RefusalCode.unauthorized),
      _notATurn(door: Door.watch, rule: RefusalRule.passes),
      const TheRefusalPassed(generation: 4),
    ),
    (
      'the coverage read refused changes nothing, whatever the code',
      const RoomRefused(RefusalCode.deviceRevoked),
      _notATurn(door: Door.coverage, rule: RefusalRule.passes),
      const TheRefusalPassed(generation: 4),
    ),
    (
      'the call for a person refused is asked again, whatever the code',
      const RoomRefused(RefusalCode.unauthorized),
      _notATurn(door: Door.person, rule: RefusalRule.asksAgain),
      const TheCallWasRefused(generation: 4),
    ),
    (
      'the call for a person met by a closed passage closes the passage',
      const RoomRefused(RefusalCode.passageClosed),
      _notATurn(door: Door.person, rule: RefusalRule.asksAgain),
      const TheCallMetAClosedPassage(generation: 4),
    ),
    (
      'the call for a person nobody can be reached for is not asked again',
      const RoomRefused(RefusalCode.nobodyToReach),
      _notATurn(door: Door.person, rule: RefusalRule.asksAgain),
      const TheRefusalPassed(generation: 4),
    ),
    (
      'a scene door whose session is gone is the session gone',
      const RoomSessionGone(),
      _notATurn(door: Door.sceneRehearsal),
      const TheSessionIsGone(generation: 4),
    ),
    (
      'a scene door whose network failed falls at its door',
      const RoomNetworkFailed(),
      _notATurn(door: Door.sceneRehearsal),
      const NetworkFailedAt(Door.sceneRehearsal, generation: 4),
    ),
    (
      'a scene send refused for any other reason reads the list again',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneRehearsal, rule: RefusalRule.readsTheListAgain),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a wordless frase is a frase not understood, never a counted refusal',
      const RoomRefused(RefusalCode.wordlessTelling),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase whose network failed is not understood, never out of reach',
      const RoomNetworkFailed(),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused naming an unknown frase is a frase not understood',
      const RoomRefused(RefusalCode.unknownReference),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused as too large is a frase not understood',
      const RoomRefused(RefusalCode.tooLarge),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused with a bare 413 is a frase not understood',
      RoomRefused(RefusalCode.unnamed(413)),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused with an answer the tablet cannot read is a frase not understood',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a translation again whose answer was lost is not understood and reads the list',
      const RoomNetworkFailed(),
      _notATurn(door: Door.sceneFrase, rule: RefusalRule.readsTheListAgain),
      const TheTellingCameBackEmpty(readAgain: true, generation: 4),
    ),
    (
      'a translation again whose answer the tablet cannot read is not understood and reads the list',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(door: Door.sceneFrase, rule: RefusalRule.readsTheListAgain),
      const TheTellingCameBackEmpty(readAgain: true, generation: 4),
    ),
    (
      'a sent rehearsal met at the frase door reads the list again',
      const RoomRefused(RefusalCode.sceneRehearsalSent),
      _notATurn(door: Door.sceneFrase),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a frase refused as out of place reads the list again',
      const RoomRefused(RefusalCode.fraseOutOfPlace),
      _notATurn(door: Door.sceneFrase, rule: RefusalRule.readsTheListAgain),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a frase refused with no name is a frase not understood, never counted',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase met while its rehearsal is being sent is never a frase not understood',
      const RoomRefused(RefusalCode.sceneRehearsalSending),
      _notATurn(door: Door.sceneFrase),
      const TheSceneDoorFailed(generation: 4),
    ),
    (
      'a translation again refused with no name is a frase not understood',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneFrase, rule: RefusalRule.readsTheListAgain),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused as forbidden is a frase not understood, never the person sign',
      const RoomRefused(RefusalCode.forbidden),
      _notATurn(door: Door.sceneFrase),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a call that is not a turn whose session is gone is the session gone',
      const RoomSessionGone(),
      _notATurn(),
      const TheSessionIsGone(generation: 4),
    ),
  ];

  group(
    'The failure policy decides each room result for a turn and for a call that is not a turn.',
    () {
      for (final (name, result, context, expected) in rows) {
        test(name, () {
          expect(_said(FailurePolicy.decide(result, context)), _said(expected));
        });
      }
    },
  );

  test('The failure policy gives the same event for the same inputs.', () {
    for (final (_, result, context, _) in rows) {
      expect(
        _said(FailurePolicy.decide(result, context)),
        _said(FailurePolicy.decide(result, context)),
      );
    }
    final imports = RegExp(r"^(?:import|export) '([^']+)'", multiLine: true)
        .allMatches(
          File(
            'lib/features/sala/domain/failure_policy.dart',
          ).readAsStringSync(),
        )
        .map((import) => import.group(1)!);
    expect(
      imports.where(
        (import) =>
            import.contains('data/') ||
            import.startsWith('dart:io') ||
            import.startsWith('package:flutter') ||
            import.startsWith('package:flutter_riverpod'),
      ),
      isEmpty,
      reason:
          'a policy that reaches the data layer or the platform is no '
          'longer a pure function of its inputs',
    );
  });
}
