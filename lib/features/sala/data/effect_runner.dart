import 'dart:async';

import '../domain/channel.dart';
import '../domain/halt.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';
import '../domain/room_reach.dart';
import '../domain/turn_result.dart';

/// Temporary: what the runner still asks the notifier to do, one method per effect that
/// reads or writes state the Station will own. PlayPart goes through it so that the voice
/// is not stopped before ENG-1444 wires the Sound port.
abstract interface class EffectHost {
  bool get watchIsWanted;

  bool get roomIsReachable;

  /// An event the runner brings back to the machine, outside any gesture.
  void answer(MachineEvent event);

  void silenceTheRoom();

  void closeAndDiscardTheMic({required bool wasOpen});

  void callForAPerson();

  void stopCallingForAPerson();

  void tellAPersonArrived();

  void readTheState();

  void replayTheSound(Kept kept);

  void askTheOpeningAgain(String freshTurnId);

  void playLine(Line line);

  void playPart(Sound part);

  void openTheMic(String take);

  void dropTheLine(Line line);

  void holdTheSound();

  void letTheSoundRun();

  void drainTheOutbox();

  void resendPending();

  void probeTheRoom();

  void discardTheSession();

  void openTheChoice();

  void sayTheOfflineNotice();

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
  final int Function()? generation;

  EffectRunner({
    required this.room,
    required this.sound,
    required this.recorder,
    required this.store,
    required this.host,
    required this.watchPeriod,
    required this.retryDelay,
    this.generation,
  });

  Timer? _watch;
  Timer? _retry;
  StreamSubscription<void>? _networkWatch;

  /// [micWasOpen] is what the microphone was before the machine reduced the event that
  /// returned these effects.
  void run(List<Effect> effects, {bool micWasOpen = false}) {
    for (final effect in effects) {
      switch (effect) {
        case SilenceTheRoom():
          host.silenceTheRoom();
        case CloseAndDiscardTheMic():
          host.closeAndDiscardTheMic(wasOpen: micWasOpen);
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
          host.playLine(line);
        case PlayPart(:final part):
          host.playPart(part);
        case PlayStretch(:final stretch):
          host.playPart(stretch);
        case OpenTheMic(:final take):
          host.openTheMic(take);
        case StopTheSound():
          unawaited(sound.stop());
        case StopTheLine():
          unawaited(sound.stopTheLine());
        case DropTheLine(:final line):
          host.dropTheLine(line);
        case HoldTheSound():
          host.holdTheSound();
        case LetTheSoundRun():
          host.letTheSoundRun();
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
          host.sayTheOfflineNotice();
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
    endTheWatch();
    _retry?.cancel();
    unawaited(_networkWatch?.cancel());
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
