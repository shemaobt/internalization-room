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
      'the call for a person met by a closed passage writes the passage down as closed',
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
