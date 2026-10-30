import 'dart:async';

import '../domain/channel.dart';
import '../domain/failure_policy.dart';
import '../domain/halt.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';
import '../domain/scene_rehearsal.dart';
import '../domain/session_snapshot.dart';
import '../domain/session_state.dart';
import '../domain/turn_result.dart';
import 'failure_log.dart';
import 'room_answer.dart';

/// Where a Session read stands in the room's order of reads, and the row it was sent over.
typedef SentRead = ({int order, List<Trecho> row});

/// What the runner asks the Station, what it tells the Station to hear, the answers it
/// brings back to the machine, and the one lifecycle hand-off. It executes no effect.
abstract interface class StationHost {
  bool get watchIsWanted;

  /// The room's session, or null.
  String? get session;

  /// The Station's context for a room result that comes back now (ADR 0059).
  FailureContext failureContext({
    required Door door,
    required RefusalRule rule,
  });

  /// A conversation, a question or a panorama start is still in the air.
  bool get recordingStarts;

  /// Whether a start that answers now still has a microphone to record into.
  bool keepsTheStart(MicOwner owner);

  /// The Station hears a part's end and its failure before the machine is answered.
  void hearThePartEnd();

  void hearThePartFail();

  void hearTheHold();

  void hearTheRun();

  void hearTheMicrophoneTaken(bool taken);

  /// The Station stamps a Session read when it is sent, and applies it with that stamp
  /// when the room answers it.
  SentRead hearTheReadSent();

  void hearTheSessionRead(SessionSnapshot snapshot, SentRead sent);

  /// The room needs a person and the call has not landed.
  bool get callIsWanted;

  /// The room is not gone and a person is needed.
  bool get aPersonIsNeeded;

  /// The Station hears the stop: the call is no longer made and the resume failures start
  /// again.
  void hearTheCallStopped();

  /// The Station hears that the room closed the passage of [session].
  void hearThePassageClosed(String session);

  /// The Station hears a call that landed: no other is made while the sign stands.
  void hearTheCallLanded();

  /// A call's answer for a session that is no longer the room's acts on that session.
  void hearAnEarlierSessionsCall(String session, RoomResult result);

  /// An event the runner brings back to the machine, outside any gesture.
  void answer(MachineEvent event);

  /// An event brought back inside the gesture that asked for the work, so the lines that
  /// follow it are that gesture's own (ADR 0059).
  void answerWhereAsked(MachineEvent event);

  /// The one callback for the Station's lifecycle: opening the Choice, discarding the
  /// session and the silence's own writes.
  void handOver(LifecycleHandOff handOff);

  /// The gestures still waiting on [turn]'s reply.
  Iterable<int> gesturesAwaiting(Turn turn);

  void hearTheTurnLetGo();

  void hearTheReplyFound(Turn turn, TurnResult reply);

  /// The Station rests on a reply the look found, unheard, for «Ouvir de novo» to say.
  void hearTheReplyKept(Turn turn, TurnResult reply);

  void hearTheLineLetGo();

  /// The Station waits again on a look the team's tap resumed.
  void hearTheWaitResumed();

  /// The Station waits on a reply that is loaded again.
  void hearTheReplyWaitingToLoad();

  /// The Station takes the hand-offs the sign held back, once the team's tap cleared it.
  void hearTheSignCleared();

  void hearTheOpeningLetGo();

  void hearTheStepLetGo();

  void hearThePendingTranslationLetGo();

  void hearThePassageRefused();

  /// The Station takes the scene rehearsals the room listed when it was asked again.
  void hearTheSceneRehearsals(List<SceneRehearsalRecord> listed);

  /// The Station asks the frase on its screen again: the room did not keep it.
  void hearTheFraseNotUnderstood();

  /// The room may have kept the frase on the Station's screen whose answer was lost: its
  /// list decides.
  void hearTheFrasePerhapsKept();

  /// The Station tells its screen the tablet's disk could not keep audio the room handed
  /// over.
  void hearTheDiskFailed();

  void hearThePlayFailed();

  /// The scene's «terminei» could not be sent.
  void hearTheSendFailed();

  /// The room refused the scene's «terminei» as already sent.
  void hearItWentAlready();
}

class EffectRunner {
  final RoomPort room;
  final SoundPort sound;
  final RecorderPort recorder;
  final StorePort store;
  final StationHost host;
  final Duration Function() watchPeriod;
  final Duration Function(int step) retryDelay;
  final Duration? Function() partCeiling;
  final Duration Function() clipGrace;
  final Duration Function() lookAgainAfter;
  final Duration Function() reloadAfter;
  final int Function()? generation;

  EffectRunner({
    required this.room,
    required this.sound,
    required this.recorder,
    required this.store,
    required this.host,
    required this.watchPeriod,
    required this.retryDelay,
    required this.partCeiling,
    required this.clipGrace,
    required this.lookAgainAfter,
    required this.reloadAfter,
    this.generation,
  });

  Timer? _watch;
  Timer? _ladder;
  int _ladderStep = 0;
  Timer? _ceiling;
  Timer? _lookAgain;
  Timer? _reload;
  void Function(bool loadAgain)? _reloadAnswered;
  Sound? _part;
  int? _partStamp;
  List<StreamSubscription<void>>? _partSignals;
  StreamSubscription<bool>? _micTaken;
  int _starts = 0;
  bool? _newestStarted;
  bool _anOlderStartRuns = false;
  bool _calling = false;
  bool _disposed = false;

  /// [micWasOpen] is what the microphone was before the machine reduced the event that
  /// returned these effects.
  void run(List<Effect> effects, {bool micWasOpen = false}) {
    for (final effect in effects) {
      switch (effect) {
        case SilenceTheRoom():
          host.handOver(effect);
          host.answerWhereAsked(const GestureSilenced(keepingTheHold: false));
        case CloseAndDiscardTheMic():
          _closeAndDiscardTheMic(wasOpen: micWasOpen);
        case CloseTheMic(:final owner):
          unawaited(_handTheTakeOver(owner));
        case DiscardTheMic():
          unawaited(recorder.discard());
        case ArmTheWatch():
          _armTheWatch();
        case CallForAPerson():
          callForAPerson();
        case StopCallingForAPerson():
          _stopCallingForAPerson();
        case ReadTheState():
          _readTheState();
        case GoOnAfterTheSign():
          host.hearTheSignCleared();
        case LetTheOpeningGo():
          host.hearTheOpeningLetGo();
        case PlayLine(:final line):
          _say(line);
        case PlayPart(:final part):
          _playThePart(part);
        case PlayStretch(:final stretch):
          _playThePart(stretch);
        case OpenTheMic(:final owner, :final take):
          _openTheMic(owner, take);
        case ArmTheCeiling():
          _armTheCeiling();
        case StopTheSound():
          _stopTheSound();
        case StopTheLine():
          unawaited(sound.stopTheLine());
        case DropTheLine(:final line):
          host.answer(LineNotSaid(line, generation: generation?.call()));
        case HoldTheSound():
          _ceiling?.cancel();
          unawaited(sound.pause());
          host.hearTheHold();
        case LetTheSoundRun():
          unawaited(sound.resume());
          _armTheCeiling();
          host.hearTheRun();
        case StopTheSend(:final row):
          store.stopTheSend(row);
        case DiscardTheSession():
          host.handOver(effect);
        case OpenTheChoice():
          host.handOver(effect);
        case ReadTheWheel():
          host.handOver(effect);
        case OpenThePanorama():
          host.handOver(effect);
        case ReturnToThePanorama():
          host.handOver(effect);
        case RestOnThePanorama():
          host.handOver(effect);
        case EnterThePassageLeft():
          host.handOver(effect);
        case ReturnToTheEntryLeft():
          host.handOver(effect);
        case RestOnTheChoice():
          host.handOver(effect);
        case LookAtTheSession(:final turn, :final sounding):
          _lookAt(turn, sounding);
        case PlayTheReply(:final turn, :final reply):
          host.hearTheReplyFound(turn, reply);
        case KeepTheReply(:final turn, :final reply):
          host.hearTheReplyKept(turn, reply);
        case LookAgain(:final turn, :final sounding):
          _armTheLookAgain(turn, sounding);
        case LetTheLineGo():
          host.hearTheLineLetGo();
        case LoadTheReplyAgain(:final answered):
          host.hearTheReplyWaitingToLoad();
          _armTheReload(answered);
        case LetTheReplyGo(:final answered):
          answered(false);
        case StopLooking():
          _lookAgain?.cancel();
        case ResumeTheWait():
          host.hearTheWaitResumed();
        case LetTheTurnGo(:final turn):
          _letTheTurnGo(turn);
        case AskForAPersonAgain():
          _askForAPersonAgain();
        case CloseThePassage():
          _closeThePassage();
        case LetTheStepGo():
          host.hearTheStepLetGo();
        case LetThePendingTranslationGo():
          host.hearThePendingTranslationLetGo();
        case RefuseThePassage():
          host.hearThePassageRefused();
        case ReadTheSceneRehearsals():
          _readTheSceneRehearsals();
        case ShowTheSceneRehearsals(:final listed):
          host.hearTheSceneRehearsals(listed);
        case AskTheFraseAgain():
          host.hearTheFraseNotUnderstood();
        case TellTheDiskFailed():
          host.hearTheDiskFailed();
        case TellThePlayFailed():
          host.hearThePlayFailed();
        case TellTheSendFailed():
          host.hearTheSendFailed();
        case TellItWentAlready():
          host.hearItWentAlready();
        case AskTheFraseAgainAfterTheList():
          host.hearTheFrasePerhapsKept();
      }
    }
  }

  void dispose() {
    _disposed = true;
    endTheWatch();
    unawaited(_micTaken?.cancel());
    _ladder?.cancel();
    _ceiling?.cancel();
    _lookAgain?.cancel();
    _letTheReloadGo();
    for (final signal in _partSignals ?? const <StreamSubscription<void>>[]) {
      unawaited(signal.cancel());
    }
  }

  /// A line's answer is stamped when it comes back: the gesture waiting on the line hears
  /// how it ended whatever moved meanwhile.
  void _say(Line line) {
    final url = line.url;
    final asset = line.asset;
    final fixedLine = line.fixedLine;
    if (url == null && asset == null && fixedLine == null) {
      return host.answer(LineNotSaid(line, generation: generation?.call()));
    }
    unawaited(
      _answerTheLine(
        line,
        fixedLine != null
            ? sound.playFixedLine(
                fixedLine.name,
                fixedLine.language,
                onSoundStart: line.onSoundStart,
              )
            : asset != null
            ? sound.playAsset(asset, onSoundStart: line.onSoundStart)
            : sound.playLine(url!, onSoundStart: line.onSoundStart),
      ),
    );
  }

  Future<void> _answerTheLine(Line line, Future<bool> said) async {
    final bool whole;
    try {
      whole = await said;
    } on RoomFailure catch (failure) {
      if (_disposed) return;
      return host.answer(
        LineNotSaid(line, because: failure, generation: generation?.call()),
      );
    }
    if (_disposed) return;
    final stamp = generation?.call();
    host.answer(
      whole
          ? PlayerEnded(line: line, generation: stamp)
          : PlayerFailed(line.source, line: line, generation: stamp),
    );
  }

  void _playThePart(Sound part) {
    _part = part;
    _partStamp = generation?.call();
    _partSignals ??= [
      sound.partEnded.listen((_) => _thePartEnded()),
      sound.partFailed.listen((_) => _thePartFailed()),
      sound.partOpened.listen((_) => _thePartOpened()),
    ];
    unawaited(sound.playPart(part));
    _armTheCeiling(opening: true);
  }

  void _thePartEnded() {
    _ceiling?.cancel();
    _ended(_part, _partStamp);
  }

  void _ended(Sound? part, int? stamp) {
    host.hearThePartEnd();
    host.answer(PlayerEnded(sound: part, generation: stamp));
  }

  void _thePartFailed() {
    _ceiling?.cancel();
    final part = _part;
    final stamp = _partStamp;
    if (part == null) return;
    host.hearThePartFail();
    host.answer(PlayerFailed(part.source, sound: part, generation: stamp));
  }

  void _thePartOpened() => host.answer(PlayerOpened(generation: _partStamp));

  /// What is left of the clip plus the grace, or the flat ceiling while the clip is still
  /// opening: a held part counts no time, so its ceiling waits for the resume.
  void _armTheCeiling({bool opening = false}) {
    _ceiling?.cancel();
    final length = opening ? null : sound.partLength;
    final ceiling = length == null ? partCeiling() : _leftOf(length);
    if (ceiling == null) return;
    final part = _part;
    final stamp = _partStamp;
    _ceiling = Timer(ceiling, () {
      _ceiling = null;
      unawaited(sound.pause());
      _ended(part, stamp);
    });
  }

  Duration _leftOf(Duration length) {
    final left = length - sound.partPosition;
    return left.isNegative ? clipGrace() : left + clipGrace();
  }

  void _stopTheSound() {
    _ceiling?.cancel();
    unawaited(sound.stop());
  }

  /// The gestures that waited on the turn stop waiting: what the look brings back sounds
  /// as the room's own, not as an answer still owed to a tap.
  void _letTheTurnGo(Turn turn) {
    if (!_disposed) {
      for (final gesture in host.gesturesAwaiting(turn)) {
        host.answerWhereAsked(GestureEnded(gesture));
      }
    }
    host.hearTheTurnLetGo();
  }

  void _lookAt(Turn turn, Kept sounding) {
    final stamp = generation?.call();
    unawaited(
      room.lookAt(turn).then((answer) {
        if (_disposed) return;
        host.answer(switch (answer) {
          TheReplyLanded(:final reply) => LookFound(
            turn,
            reply,
            generation: stamp,
          ),
          StillAnswering() => LookPending(
            turn,
            sounding: sounding,
            generation: stamp,
          ),
          NothingLanded() => LookEmpty(
            turn,
            sounding: sounding,
            generation: stamp,
          ),
          TheLookFailed(:final result) => LookFailed(
            turn,
            result,
            sounding: sounding,
            generation: stamp,
          ),
        });
      }),
    );
  }

  void _armTheLookAgain(Turn turn, Kept sounding) {
    _lookAgain?.cancel();
    final stamp = generation?.call();
    _lookAgain = Timer(lookAgainAfter(), () {
      _lookAgain = null;
      if (generation?.call() == stamp) _lookAt(turn, sounding);
    });
  }

  void _armTheReload(void Function(bool loadAgain) answered) {
    _letTheReloadGo();
    final stamp = generation?.call();
    _reloadAnswered = answered;
    _reload = Timer(reloadAfter(), () {
      _reload = null;
      _reloadAnswered = null;
      answered(generation?.call() == stamp);
    });
  }

  void _letTheReloadGo() {
    _reload?.cancel();
    _reload = null;
    final answered = _reloadAnswered;
    _reloadAnswered = null;
    answered?.call(false);
  }

  final Set<String> _startedTakes = {};

  void _openTheMic(MicOwner owner, String take) {
    _micTaken ??= recorder.taken.listen(host.hearTheMicrophoneTaken);
    _newestStarted = null;
    unawaited(
      _answerTheStart(
        owner,
        ++_starts,
        generation?.call(),
        recorder.start(take, owner),
        take,
      ),
    );
  }

  /// A start's answer is stamped with the generation it was opened under; a late start
  /// that is still the newest closes the Channel and leaves no recorder running (ADR 0057).
  /// An answer that arrives after the runner is disposed has no Channel left to close, so a
  /// start that opened the recorder is discarded and the rest is dropped.
  Future<void> _answerTheStart(
    MicOwner owner,
    int start,
    int? stamp,
    Future<MicAnswer> starting,
    String take,
  ) async {
    final answer = await starting;
    if (answer == MicAnswer.started) _startedTakes.add(take);
    if (_disposed) {
      if (answer == MicAnswer.started) unawaited(recorder.discard());
      return;
    }
    final started = answer == MicAnswer.started;
    final now = generation?.call();
    if (start != _starts) {
      if (started && _newestStarted == false) {
        unawaited(recorder.discard());
      } else if (started) {
        _anOlderStartRuns = true;
      }
      return;
    }
    _newestStarted = started;
    final anOlderStartRuns = _anOlderStartRuns;
    _anOlderStartRuns = false;
    if (stamp != now) {
      if (started || anOlderStartRuns) unawaited(recorder.discard());
      host.answer(
        started
            ? MicAnswered(MicAnswer.abandoned, generation: now)
            : MicClosed(generation: now),
      );
    } else if ((started && !host.keepsTheStart(owner)) ||
        (!started && anOlderStartRuns)) {
      unawaited(recorder.discard());
    }
    host.answer(MicAnswered(answer, owner: owner, generation: stamp));
  }

  /// A take's answer is stamped when it comes back: the gesture waiting on the take gets
  /// it, or the recorder's failure, whatever moved meanwhile.
  Future<void> _handTheTakeOver(MicOwner? owner) async {
    final String? take;
    try {
      take = await recorder.stop();
    } on Object catch (because) {
      if (_disposed) return;
      return host.answer(
        MicAnswered(
          MicAnswer.closed,
          because: because,
          generation: generation?.call(),
        ),
      );
    }
    final handedOver = take;
    if (_disposed) {
      if (handedOver != null &&
          _startedTakes.any((it) => _isTheFileOf(it, handedOver))) {
        unawaited(recorder.delete(handedOver));
      }
      return;
    }
    if (handedOver != null) {
      _startedTakes.removeWhere((it) => _isTheFileOf(it, handedOver));
    }
    host.answer(
      MicAnswered(
        MicAnswer.closed,
        take: take,
        owner: owner,
        generation: generation?.call(),
      ),
    );
  }

  bool _isTheFileOf(String startedTake, String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return (dot < 0 ? name : name.substring(0, dot)) == startedTake;
  }

  void _closeAndDiscardTheMic({required bool wasOpen}) {
    if (!wasOpen && !host.recordingStarts) return;
    unawaited(recorder.discard());
    host.answer(
      MicAnswered(MicAnswer.discarded, generation: generation?.call()),
    );
  }

  void _readTheState() {
    final session = host.session;
    if (session == null) return;
    unawaited(
      _answerTheRead(
        session,
        host.hearTheReadSent(),
        room.readTheSession(session),
      ),
    );
  }

  void _readTheSceneRehearsals() {
    final session = host.session;
    if (session == null) return;
    unawaited(_answerTheSceneRehearsals(session));
  }

  Future<void> _answerTheSceneRehearsals(String session) async {
    final stamp = generation?.call();
    final answer = await room.sceneRehearsalsOf(session);
    if (_disposed || host.session != session) return;
    switch (answer) {
      case SceneRehearsalsListed(:final listed):
        host.answer(TheSceneRehearsalsListed(listed, generation: stamp));
      case SceneRehearsalsFailed(:final result):
        _decideAt(
          result,
          door: Door.sceneRehearsal,
          rule: RefusalRule.letsTheStepGo,
        );
    }
  }

  /// A read the room answers for a session that is no longer the room's changes nothing.
  Future<void> _answerTheRead(
    String session,
    SentRead sent,
    Future<SessionReadAnswer> reading,
  ) async {
    final answer = await reading;
    if (_disposed || host.session != session) return;
    switch (answer) {
      case SessionReadAnswered(:final snapshot):
        host.hearTheSessionRead(snapshot, sent);
      case SessionReadFailed(:final result):
        _decideAt(result, door: Door.watch, rule: RefusalRule.passes);
    }
  }

  /// The call is only made when the server says it has it.
  ///
  /// Most of the ways into a halt are bad network and a room that is not answering, so
  /// the call goes out at the worst possible moment to be delivered — and a lost one left
  /// no trace anywhere: the session never entered the desk's queue, no facilitator was
  /// told, and nobody arrived to tap the screen that is the only thing that asked again.
  void callForAPerson() {
    final session = host.session;
    if (_calling || !host.callIsWanted || session == null) return;
    _calling = true;
    unawaited(_call(session));
  }

  Future<void> _call(String session) async {
    final RoomResult result;
    try {
      result = await room.askForAPerson(session);
    } finally {
      _calling = false;
    }
    if (_disposed) return;
    if (host.session != session) {
      return _anEarlierSessionAnswered(session, result);
    }
    if (result is! RoomAnswered) {
      return _decideAt(result, door: Door.person, rule: RefusalRule.asksAgain);
    }
    if (host.callIsWanted) host.hearTheCallLanded();
  }

  void _anEarlierSessionAnswered(String session, RoomResult result) {
    if (result is! RoomNetworkFailed) {
      host.hearAnEarlierSessionsCall(session, result);
    }
    callForAPerson();
  }

  void _decideAt(
    RoomResult result, {
    required Door door,
    required RefusalRule rule,
  }) => host.answerWhereAsked(
    decided(result, host.failureContext(door: door, rule: rule)),
  );

  /// The arm is gated by [StationHost.aPersonIsNeeded] and not by the generation: the
  /// machine moves the generation on the way into other halts, and a ladder that did not
  /// arm for it would stop insisting in silence. The fire is gated by the generation: a
  /// ladder armed before it moved is dropped, as the Station drops any older answer.
  void _askForAPersonAgain() {
    if (!host.aPersonIsNeeded) return;
    final armedUnder = generation?.call();
    _ladder?.cancel();
    _ladder = Timer(retryDelay(_ladderStep++), () {
      _ladder = null;
      if (generation?.call() != armedUnder) return;
      callForAPerson();
    });
  }

  void forgetTheLadder() {
    _ladder?.cancel();
    _ladder = null;
    _ladderStep = 0;
  }

  void _stopCallingForAPerson() {
    forgetTheLadder();
    host.hearTheCallStopped();
  }

  void _closeThePassage() {
    final session = host.session;
    if (session == null) return;
    host.hearThePassageClosed(session);
  }

  void endTheWatch() {
    _watch?.cancel();
    _watch = null;
  }

  void _armTheWatch() {
    if (!host.watchIsWanted) return endTheWatch();
    if (_watch?.isActive ?? false) return;
    _watch = Timer(watchPeriod(), () {
      _watch = null;
      host.answer(WatchFired(generation: generation?.call()));
    });
  }
}
