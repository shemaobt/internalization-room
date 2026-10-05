import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'machine_generator.dart';

const _turn = Turn('sessao-1', 'turno-7');
const _kept = TheOpening('turno-7');

const _aTurn = FailureContext(
  stage: SalaStage.conversa,
  generation: 4,
  turn: _turn,
  refusalHalts: true,
  sounding: _kept,
);

FailureContext _notATurn({int refusals = 0, bool refusalHalts = false}) =>
    FailureContext(
      stage: SalaStage.retro,
      step: BtPhase.thinking,
      generation: 4,
      door: Door.outbox,
      refusals: refusals,
      refusalHalts: refusalHalts,
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
      'a turn answered is the room answering',
      const RoomAnswered(),
      _aTurn,
      const TheRoomAnswered(generation: 4),
    ),
    (
      'a turn whose network failed is looked at once',
      const RoomNetworkFailed(),
      _aTurn,
      const TurnGivenUp(_turn, sounding: _kept, generation: 4),
    ),
    (
      'a turn that timed out is looked at once',
      const RoomTimedOut(),
      _aTurn,
      const TurnGivenUp(_turn, sounding: _kept, generation: 4),
    ),
    (
      'a turn refused with a code that stops the room calls a person',
      const RoomRefused(RefusalCode.deviceRevoked),
      _aTurn,
      const RoomRaisedAHalt(sounding: _kept, generation: 4),
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
      const RoomRaisedAHalt(sounding: _kept, generation: 4),
    ),
    (
      'a turn refused calls a person on the spot whatever its family says',
      const RoomRefused(RefusalCode.unreadable),
      const FailureContext(
        stage: SalaStage.conversa,
        generation: 4,
        turn: _turn,
        sounding: _kept,
      ),
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
      _notATurn(refusalHalts: true),
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
