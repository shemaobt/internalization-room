import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

class AStationHost implements StationHost {
  final List<String> asked = [];
  final List<MachineEvent> answers = [];
  void Function(MachineEvent event)? onAnswer;

  @override
  bool watchIsWanted = true;

  @override
  String? session;

  FailureContext context = const FailureContext(station: Menu(), generation: 0);

  @override
  FailureContext failureContext({
    required Door door,
    required RefusalRule rule,
  }) => FailureContext(
    station: context.station,
    step: context.step,
    generation: context.generation,
    turn: context.turn,
    sounding: context.sounding,
    door: door,
    rule: rule,
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
  bool aPersonIsNeeded = true;

  int callsStopped = 0;
  final List<String> passagesClosedHeard = [];

  @override
  void hearTheCallStopped() => callsStopped++;

  @override
  void hearThePassageClosed(String session) => passagesClosedHeard.add(session);

  int callsLanded = 0;
  final List<(String, RoomResult)> earlierCallsHeard = [];

  @override
  void hearTheCallLanded() => callsLanded++;

  @override
  void hearAnEarlierSessionsCall(String session, RoomResult result) =>
      earlierCallsHeard.add((session, result));

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

  final List<LifecycleHandOff> handedOver = [];
  final Map<Turn, List<int>> awaiting = {};

  @override
  void handOver(LifecycleHandOff handOff) => handedOver.add(handOff);

  @override
  Iterable<int> gesturesAwaiting(Turn turn) => awaiting[turn] ?? const [];

  @override
  void hearTheTurnLetGo() => asked.add('hearTheTurnLetGo');

  @override
  void hearTheReplyFound(Turn turn, TurnResult reply) =>
      asked.add('hearTheReplyFound:${turn.turnId}');

  @override
  void hearTheSignCleared() => asked.add('hearTheSignCleared');

  @override
  void hearTheOpeningLetGo() => asked.add('hearTheOpeningLetGo');

  @override
  void hearTheReplyKept(Turn turn, TurnResult reply) =>
      asked.add('hearTheReplyKept:${turn.turnId}');

  @override
  void hearTheLineLetGo() => asked.add('hearTheLineLetGo');

  @override
  void hearTheWaitResumed() => asked.add('hearTheWaitResumed');

  @override
  void hearTheReplyWaitingToLoad() => asked.add('hearTheReplyWaitingToLoad');

  @override
  void hearTheStepLetGo() => asked.add('hearTheStepLetGo');

  @override
  void hearThePendingTranslationLetGo() =>
      asked.add('hearThePendingTranslationLetGo');

  @override
  void hearThePassageRefused() => asked.add('hearThePassageRefused');

  @override
  void hearTheSceneRehearsals(List<SceneRehearsalRecord> listed) =>
      asked.add('hearTheSceneRehearsals:${listed.length}');

  @override
  void hearTheFraseNotUnderstood() => asked.add('hearTheFraseNotUnderstood');

  @override
  void hearTheFrasePerhapsKept() => asked.add('hearTheFrasePerhapsKept');

  @override
  void hearTheDiskFailed() => asked.add('hearTheDiskFailed');

  @override
  void hearThePlayFailed() => asked.add('hearThePlayFailed');

  @override
  void hearTheSendFailed() => asked.add('hearTheSendFailed');

  @override
  void hearItWentAlready() => asked.add('hearItWentAlready');
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
  AStationHost host, {
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
  lookAgainAfter: () => Duration.zero,
  reloadAfter: () => Duration.zero,
  generation: generation,
);
