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
const _kept = TheOpening('turno-7');

final _aTurn = FailureContext(
  station: Station.stored(SalaStage.conversa),
  generation: 4,
  turn: _turn,
  rule: RefusalRule.haltsAtOnce,
);

final _theOpening = FailureContext(
  station: Station.stored(SalaStage.conversa),
  generation: 4,
  rule: RefusalRule.haltsAtOnce,
  sounding: _kept,
);

FailureContext _notATurn({
  int refusals = 0,
  RefusalRule rule = RefusalRule.counts,
  Door door = Door.outbox,
  RoomReach why = RoomReach.noNetwork,
}) => FailureContext(
  station: Station.stored(SalaStage.retro),
  step: BtPhase.thinking,
  generation: 4,
  door: door,
  why: why,
  refusals: refusals,
  rule: rule,
  sounding: const ThePart(),
);

String _said(MachineEvent event) => switch (event) {
  final AnsweringEvent answer =>
    '${describeEvent(answer)} @${answer.generation}',
  _ => describeEvent(event),
};

void main() {
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
      'a turn refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.deviceRevoked),
      _aTurn,
      const RoomRaisedAHalt(generation: 4),
    ),
    (
      'a turn refused because the passage cannot open goes back to the Choice',
      const RoomRefused(RefusalCode.passageCannotOpen),
      _aTurn,
      const ThePassageCannotOpen(generation: 4),
    ),
    (
      'a turn refused with any other code calls a person on the spot',
      const RoomRefused(RefusalCode.unreadable),
      _aTurn,
      const RoomRaisedAHalt(generation: 4),
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
      'an opening refused with any code that does not stop the room is missed, '
          'not halted',
      const RoomRefused(RefusalCode.unreadable),
      _theOpening,
      const TheOpeningMissed(generation: 4),
    ),
    (
      'an opening refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.deviceRevoked),
      _theOpening,
      const RoomRaisedAHalt(sounding: _kept, generation: 4),
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
      'a call that is not a turn whose network failed falls out of reach at its door',
      const RoomNetworkFailed(),
      _notATurn(),
      const NetworkFailedAt(Door.outbox, generation: 4),
    ),
    (
      'a wait that is not a turn and timed out calls a person',
      const RoomTimedOut(),
      _notATurn(),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'a call that is not a turn refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.unauthorized),
      _notATurn(),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'a call that is not a turn refused because the passage cannot open goes back to the Choice',
      const RoomRefused(RefusalCode.passageCannotOpen),
      _notATurn(),
      const ThePassageCannotOpen(generation: 4),
    ),
    (
      'a wordless telling is its own answer and never a counted refusal',
      const RoomRefused(RefusalCode.wordlessTelling),
      _notATurn(refusals: 2),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a telling whose network failed is a telling not understood, never out of reach',
      const RoomNetworkFailed(),
      _notATurn(door: Door.telling, refusals: 2),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a refusal that is not a turn and is under the strike count is counted',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(refusals: 1),
      const TheRoomRefused(sounding: ThePart(), generation: 4),
    ),
    (
      'the first refusal that is not a turn is counted',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(),
      const TheRoomRefused(sounding: ThePart(), generation: 4),
    ),
    (
      'the third refusal that is not a turn calls a person',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(refusals: 2),
      const TheRoomRefused(third: true, sounding: ThePart(), generation: 4),
    ),
    (
      'a refusal of a call that calls a person on the spot is not counted',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(rule: RefusalRule.haltsAtOnce),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'a call that is not a turn whose room is silent falls out of reach saying so',
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
      'the coverage read refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.deviceRevoked),
      _notATurn(door: Door.coverage, rule: RefusalRule.passesUnlessItStops),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'the coverage read refused with any other code changes nothing',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(door: Door.coverage, rule: RefusalRule.passesUnlessItStops),
      const TheRefusalPassed(generation: 4),
    ),
    (
      'the resume refused calls a person and keeps the resume',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(door: Door.resume, rule: RefusalRule.keepsTheResume),
      const RoomRaisedAHalt(sounding: TheResume(), generation: 4),
    ),
    (
      'the resume whose parts the room no longer knows calls a person and keeps the resume',
      const RoomSessionGone(),
      _notATurn(door: Door.resume, rule: RefusalRule.keepsTheResume),
      const RoomRaisedAHalt(sounding: TheResume(), generation: 4),
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
      'a scene door whose network failed falls out of reach at its door',
      const RoomNetworkFailed(),
      _notATurn(door: Door.sceneRehearsal),
      const NetworkFailedAt(Door.sceneRehearsal, generation: 4),
    ),
    (
      'a scene door refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.unauthorized),
      _notATurn(door: Door.sceneRehearsal),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'a scene door refused because the rehearsal was sent reads it again',
      const RoomRefused(RefusalCode.sceneRehearsalSent),
      _notATurn(door: Door.sceneRehearsal),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a scene door refused because a restart landed unheard reads it again',
      const RoomRefused(RefusalCode.restartOutOfOrder),
      _notATurn(door: Door.sceneRehearsal),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a scene door that does not find the rehearsal reads it again',
      const RoomRefused(RefusalCode.notFound),
      _notATurn(door: Door.sceneRehearsal),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a scene door refused for any other reason is never counted',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneRehearsal, refusals: 2),
      const TheSceneDoorFailed(generation: 4),
    ),
    (
      'a scene send refused for any other reason reads the list again',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneRehearsal, rule: RefusalRule.readsTheListAgain),
      const TheSceneDoorFailed(readAgain: true, generation: 4),
    ),
    (
      'a scene send refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.unauthorized),
      _notATurn(door: Door.sceneRehearsal, rule: RefusalRule.readsTheListAgain),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
    ),
    (
      'a wordless frase is a frase not understood, never a counted refusal',
      const RoomRefused(RefusalCode.wordlessTelling),
      _notATurn(door: Door.sceneFrase, refusals: 2),
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
      _notATurn(door: Door.sceneFrase, refusals: 2),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused as too large is a frase not understood',
      const RoomRefused(RefusalCode.tooLarge),
      _notATurn(door: Door.sceneFrase, refusals: 2),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused with a bare 413 is a frase not understood',
      RoomRefused(RefusalCode.unnamed(413)),
      _notATurn(door: Door.sceneFrase, refusals: 2),
      const TheTellingCameBackEmpty(generation: 4),
    ),
    (
      'a frase refused with an answer the tablet cannot read is a frase not understood',
      const RoomRefused(RefusalCode.unreadable),
      _notATurn(door: Door.sceneFrase, refusals: 2),
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
      'a frase refused for any other reason is never counted',
      RoomRefused(RefusalCode.unnamed(422)),
      _notATurn(door: Door.sceneFrase, refusals: 2),
      const TheSceneDoorFailed(generation: 4),
    ),
    (
      'a frase refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.forbidden),
      _notATurn(door: Door.sceneFrase),
      const RoomRaisedAHalt(sounding: ThePart(), generation: 4),
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
