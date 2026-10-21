import 'package:flutter/foundation.dart';

import '../domain/failure_policy.dart';
import '../domain/machine.dart';

/// The failure policy's answer, kept in the log with its door and its reason: what failed
/// and why stays for the operator once the team is shown nothing (ADR 0093).
MachineEvent decided(RoomResult result, FailureContext context) {
  final event = FailurePolicy.decide(result, context);
  if (result is! RoomAnswered) {
    debugPrint(
      'Falha decidida na porta ${context.door.name}: ${_why(result)} → '
      '${event.runtimeType}',
    );
  }
  return event;
}

MachineEvent decidedOnTheTablet(TabletFailure failure, FailureContext context) {
  final event = FailurePolicy.decideOnTheTablet(failure, context);
  debugPrint(
    'Falha do tablet decidida: ${_whatFailed(failure)} → ${event.runtimeType}',
  );
  return event;
}

String _why(RoomResult result) => switch (result) {
  RoomRefused(:final code) => 'recusada ($code)',
  RoomNetworkFailed() => 'a rede caiu',
  RoomSessionGone() => 'a sessão acabou',
  RoomTimedOut() => 'a espera esgotou',
  RoomAnsweredWithoutAReply() => 'respondida sem nada para tocar',
  RoomFoundNothing() => 'o olhar não achou nada',
  RoomAnswered() => 'respondida',
};

String _whatFailed(TabletFailure failure) => switch (failure) {
  TheSoundFailed(:final inARow) => 'o som falhou ($inARow seguidas)',
  TheMicFailedToStart(:final inARow) =>
    'o microfone não abriu ($inARow seguidas)',
  TheTabletCannotRecord() => 'o tablet não grava',
  TheBuildCannotReachTheRoom() => 'o build não alcança a sala',
};
