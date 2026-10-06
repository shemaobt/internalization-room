import 'dart:async';

import '../domain/channel.dart';
import '../domain/halt.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';
import '../domain/room_reach.dart';
import '../domain/turn_result.dart';
import 'room_answer.dart';

/// Temporary: what the runner still asks the notifier to do, one method per effect that
/// reads or writes state the Station will own.
abstract interface class EffectHost {
  bool get watchIsWanted;

  bool get roomIsReachable;

  /// A conversation, a question or a panorama start is still in the air.
  bool get recordingStarts;

  /// Whether a start that answers now still has a microphone to record into.
  bool keepsTheStart(MicOwner owner);

  /// What the room keeps to sound again if a line it fails to say calls a person.
  Kept get sounding;

  /// The Station hears a part's end and its failure before the machine is answered.
  void hearThePartEnd();

  void hearThePartFail();

  void hearTheHold();

  void hearTheRun();

  void hearTheMicrophoneTaken(bool taken);

  /// An event the runner brings back to the machine, outside any gesture.
  void answer(MachineEvent event);

  void silenceTheRoom();

  void callForAPerson();

  void stopCallingForAPerson();

  void tellAPersonArrived();

  void readTheState();

  void replayTheSound(Kept kept);

  void askTheOpeningAgain(String freshTurnId);

  void drainTheOutbox();

  void resendPending();

  void probeTheRoom();

  void discardTheSession();

  void openTheChoice();

  void playTheReply(Turn turn, TurnResult reply);

  void countTheRefusal();

  void refuseThePassage();

  void letTheTurnGo(Turn turn);

  void fellAt(Door door, RoomReach why);

  void askForAPersonAgain();

  void markThePassageClosed();
}

class EffectRunner {
  final RoomPort room;
  final SoundPort sound;
  final RecorderPort recorder;
  final StorePort store;
  final EffectHost host;
  final Duration Function() watchPeriod;
  final Duration Function(int step) retryDelay;
  final Duration? Function() partCeiling;
  final Duration Function() clipGrace;
  final Line Function() offlineNotice;
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
    required this.offlineNotice,
    this.generation,
  });

  Timer? _watch;
  Timer? _retry;
  StreamSubscription<void>? _networkWatch;
  Timer? _ceiling;
  Sound? _part;
  int? _partStamp;
  List<StreamSubscription<void>>? _partSignals;
  StreamSubscription<bool>? _micTaken;
  int _starts = 0;
  bool _disposed = false;

  /// [micWasOpen] is what the microphone was before the machine reduced the event that
  /// returned these effects.
  void run(List<Effect> effects, {bool micWasOpen = false}) {
    for (final effect in effects) {
      switch (effect) {
        case SilenceTheRoom():
          host.silenceTheRoom();
        case CloseAndDiscardTheMic():
          _closeAndDiscardTheMic(wasOpen: micWasOpen);
        case CloseTheMic():
          unawaited(_handTheTakeOver());
        case DiscardTheMic():
          unawaited(recorder.discard());
        case ArmTheWatch():
          _armTheWatch();
        case CallForAPerson():
          host.callForAPerson();
        case StopCallingForAPerson():
          host.stopCallingForAPerson();
        case TellAPersonArrived():
          host.tellAPersonArrived();
        case ReadTheState():
          host.readTheState();
        case ReplayTheSound(:final kept):
          host.replayTheSound(kept);
        case AskTheOpeningAgain(:final freshTurnId):
          host.askTheOpeningAgain(freshTurnId);
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
        case ArmTheRetry(:final step, :final due):
          _armTheRetry(due ?? retryDelay(step));
        case CancelTheRetry():
          _cancelTheRetry();
        case DrainTheOutbox():
          host.drainTheOutbox();
        case ResendPending():
          host.resendPending();
        case ProbeTheRoom():
          host.probeTheRoom();
        case DiscardTheSession():
          host.discardTheSession();
        case OpenTheChoice():
          host.openTheChoice();
        case SayTheOfflineNotice():
          _sayTheOfflineNotice();
        case LookAtTheSession(:final turn, :final sounding):
          _lookAt(turn, sounding);
        case PlayTheReply(:final turn, :final reply):
          host.playTheReply(turn, reply);
        case LetTheTurnGo(:final turn):
          host.letTheTurnGo(turn);
        case FellAt(:final door, :final why):
          host.fellAt(door, why);
        case AskForAPersonAgain():
          host.askForAPersonAgain();
        case MarkThePassageClosed():
          host.markThePassageClosed();
        case CountTheRefusal():
          host.countTheRefusal();
        case RefuseThePassage():
          host.refuseThePassage();
      }
    }
  }

  void dispose() {
    _disposed = true;
    endTheWatch();
    unawaited(_micTaken?.cancel());
    _retry?.cancel();
    _ceiling?.cancel();
    unawaited(_networkWatch?.cancel());
    for (final signal in _partSignals ?? const <StreamSubscription<void>>[]) {
      unawaited(signal.cancel());
    }
  }

  /// A line's answer is stamped when it comes back: the gesture waiting on the line hears
  /// how it ended whatever moved meanwhile.
  void _say(Line line) {
    final url = line.url;
    final asset = line.asset;
    if (url == null && asset == null) {
      return host.answer(LineNotSaid(line, generation: generation?.call()));
    }
    unawaited(
      _answerTheLine(
        line,
        asset != null
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
      return host.answer(
        LineNotSaid(line, because: failure, generation: generation?.call()),
      );
    }
    final stamp = generation?.call();
    host.answer(
      whole
          ? PlayerEnded(line: line, generation: stamp)
          : PlayerFailed(
              line.source,
              sounding: host.sounding,
              line: line,
              generation: stamp,
            ),
    );
  }

  void _sayTheOfflineNotice() =>
      host.answer(LineArrived(offlineNotice(), generation: generation?.call()));

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

  void _lookAt(Turn turn, Kept sounding) {
    final stamp = generation?.call();
    unawaited(
      room
          .lookAt(turn)
          .then(
            (reply) => host.answer(
              reply == null
                  ? LookEmpty(sounding: sounding, generation: stamp)
                  : LookFound(turn, reply, generation: stamp),
            ),
          ),
    );
  }

  void _armTheRetry(Duration delay) {
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      host.answer(RetryFired(generation: generation?.call()));
    });
    if (!host.roomIsReachable) {
      _networkWatch ??= room.networkReturned.listen(
        (_) => host.answer(RetryFired(generation: generation?.call())),
      );
    }
  }

  void _cancelTheRetry() {
    _retry?.cancel();
    _retry = null;
    if (!host.roomIsReachable) return;
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
  }

  void _openTheMic(MicOwner owner, String take) {
    _micTaken ??= recorder.taken.listen(host.hearTheMicrophoneTaken);
    unawaited(
      _answerTheStart(
        owner,
        ++_starts,
        generation?.call(),
        recorder.start(take, owner),
      ),
    );
  }

  /// A start's answer is stamped with the generation it was opened under. The answer can
  /// arrive a minute late, while the platform asks for the permission. A late start that
  /// is still the newest closes the Channel, and one that started is discarded first, so
  /// no recorder keeps running on a generation the room left. One that started after the
  /// room closed its microphone is discarded too.
  Future<void> _answerTheStart(
    MicOwner owner,
    int start,
    int? stamp,
    Future<MicAnswer> starting,
  ) async {
    final answer = await starting;
    if (_disposed) return;
    final started = answer == MicAnswer.started;
    final now = generation?.call();
    if (stamp != now) {
      if (start == _starts && started) {
        unawaited(recorder.discard());
        host.answer(MicAnswered(MicAnswer.abandoned, generation: now));
      } else if (start == _starts) {
        host.answer(MicClosed(generation: now));
      }
    } else if (started && !host.keepsTheStart(owner)) {
      unawaited(recorder.discard());
    }
    host.answer(MicAnswered(answer, generation: stamp));
  }

  /// A take's answer is stamped when it comes back: the gesture waiting on the take gets
  /// it whatever moved meanwhile.
  Future<void> _handTheTakeOver() async {
    final take = await recorder.stop();
    if (_disposed) return;
    host.answer(
      MicAnswered(MicAnswer.closed, take: take, generation: generation?.call()),
    );
  }

  void _closeAndDiscardTheMic({required bool wasOpen}) {
    if (!wasOpen && !host.recordingStarts) return;
    unawaited(recorder.discard());
    host.answer(
      MicAnswered(MicAnswer.discarded, generation: generation?.call()),
    );
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
