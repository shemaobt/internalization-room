import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
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

  @override
  String? session;

  FailureContext context = const FailureContext(station: Menu(), generation: 0);

  @override
  FailureContext failureContext({
    required Door door,
    required RefusalRule rule,
    required RoomReach why,
  }) => FailureContext(
    station: context.station,
    step: context.step,
    generation: context.generation,
    turn: context.turn,
    refusals: context.refusals,
    sounding: context.sounding,
    door: door,
    rule: rule,
    why: why,
  );

  final List<SessionSnapshot> readsHeard = [];
  int _readsSent = 0;

  @override
  SentRead hearTheReadSent() => (order: ++_readsSent, row: const []);

  @override
  void hearTheSessionRead(SessionSnapshot snapshot, SentRead sent) =>
      readsHeard.add(snapshot);

  @override
  bool callIsWanted = true;

  @override
  String? passageInCourse;

  int callsLanded = 0;
  int callsLandedWithoutASession = 0;
  final List<(String, String?, RoomResult)> earlierCallsHeard = [];
  final List<String> earlierSessionsGone = [];

  @override
  void hearTheCallLanded() => callsLanded++;

  @override
  void hearTheCallLandedWithoutASession() => callsLandedWithoutASession++;

  @override
  Future<void> hearAnEarlierSessionsCall(
    String session,
    String? passage,
    RoomResult result,
  ) async => earlierCallsHeard.add((session, passage, result));

  @override
  void hearAnEarlierSessionGone(String session) =>
      earlierSessionsGone.add(session);

  void Function()? onPartEnd;

  @override
  bool recordingStarts = false;

  bool keepsALateStart = true;

  @override
  bool keepsTheStart(MicOwner owner) => keepsALateStart;

  @override
  void answer(MachineEvent event) {
    answers.add(event);
    onAnswer?.call(event);
  }

  @override
  void answerWhereAsked(MachineEvent event) => answer(event);

  @override
  void hearThePartEnd() {
    asked.add('hearThePartEnd');
    onPartEnd?.call();
  }

  @override
  void hearThePartFail() => asked.add('hearThePartFail');

  @override
  void hearTheHold() => asked.add('hearTheHold');

  @override
  void hearTheRun() => asked.add('hearTheRun');

  @override
  void hearTheMicrophoneTaken(bool taken) =>
      asked.add('hearTheMicrophoneTaken:$taken');

  @override
  void silenceTheRoom() => asked.add('silenceTheRoom');

  @override
  void stopCallingForAPerson() => asked.add('stopCallingForAPerson');

  @override
  void replayTheSound(Kept kept) => asked.add('replayTheSound');

  @override
  void letTheOpeningGo() => asked.add('letTheOpeningGo');

  @override
  void drainTheOutbox() => asked.add('drainTheOutbox');

  @override
  void resendPending() => asked.add('resendPending');

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
