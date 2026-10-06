import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

class ARoomHost implements EffectHost {
  final List<String> asked = [];
  final List<MachineEvent> answers = [];
  void Function(MachineEvent event)? onAnswer;

  @override
  bool watchIsWanted = true;

  @override
  bool roomIsReachable = true;

  @override
  Kept sounding = const NothingKept();

  void Function()? onPartEnd;

  @override
  void answer(MachineEvent event) {
    answers.add(event);
    onAnswer?.call(event);
  }

  @override
  void hearThePartEnd() {
    asked.add('hearThePartEnd');
    onPartEnd?.call();
  }

  @override
  void hearThePartFail() => asked.add('hearThePartFail');

  @override
  void hearThePartOpen() => asked.add('hearThePartOpen');

  @override
  void silenceTheRoom() => asked.add('silenceTheRoom');

  @override
  void closeAndDiscardTheMic({required bool wasOpen}) =>
      asked.add('closeAndDiscardTheMic');

  @override
  void callForAPerson() => asked.add('callForAPerson');

  @override
  void stopCallingForAPerson() => asked.add('stopCallingForAPerson');

  @override
  void tellAPersonArrived() => asked.add('tellAPersonArrived');

  @override
  void readTheState() => asked.add('readTheState');

  @override
  void replayTheSound(Kept kept) => asked.add('replayTheSound');

  @override
  void askTheOpeningAgain(String freshTurnId) =>
      asked.add('askTheOpeningAgain');

  @override
  void openTheMic(String take) => asked.add('openTheMic');

  @override
  void drainTheOutbox() => asked.add('drainTheOutbox');

  @override
  void resendPending() => asked.add('resendPending');

  @override
  void probeTheRoom() => asked.add('probeTheRoom');

  @override
  void discardTheSession() => asked.add('discardTheSession');

  @override
  void openTheChoice() => asked.add('openTheChoice');

  @override
  void playTheReply(Turn turn, TurnResult reply) => asked.add('playTheReply');

  @override
  void letTheTurnGo(Turn turn) => asked.add('letTheTurnGo');

  @override
  void fellAt(Door door, RoomReach why) => asked.add('fellAt');

  @override
  void askForAPersonAgain() => asked.add('askForAPersonAgain');

  @override
  void markThePassageClosed() => asked.add('markThePassageClosed');

  @override
  void countTheRefusal() => asked.add('countTheRefusal');

  @override
  void refuseThePassage() => asked.add('refuseThePassage');
}

typedef Ports = ({
  RoomPort room,
  SoundPort sound,
  RecorderPort recorder,
  StorePort store,
});

Ports portsOf(ProviderContainer container) => (
  room: container.read(roomPortProvider),
  sound: container.read(soundPortProvider),
  recorder: container.read(recorderPortProvider),
  store: container.read(storePortProvider),
);

EffectRunner runnerOver(
  Ports ports,
  ARoomHost host, {
  Duration watchPeriod = const Duration(seconds: 30),
  Duration retryDelay = Duration.zero,
  Duration clipGrace = Duration.zero,
  int Function()? generation,
}) => EffectRunner(
  room: ports.room,
  sound: ports.sound,
  recorder: ports.recorder,
  store: ports.store,
  host: host,
  watchPeriod: () => watchPeriod,
  retryDelay: (_) => retryDelay,
  partCeiling: () => null,
  clipGrace: () => clipGrace,
  offlineNotice: () =>
      const Line(LineKind.offlineNotice, 0, asset: 'offline.mp3'),
  generation: generation,
);
