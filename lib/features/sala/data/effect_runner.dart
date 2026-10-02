import 'dart:async';

import '../domain/channel.dart';
import '../domain/halt.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';

/// Temporary: what the runner still asks the notifier to do, one method per effect that
/// reads or writes state the Station will own.
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

  void thePartIsInTheAir();

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
}

class EffectRunner {
  final RoomPort room;
  final SoundPort sound;
  final RecorderPort recorder;
  final StorePort store;
  final EffectHost host;
  final Duration Function() watchPeriod;
  final Duration Function(int step) retryDelay;

  EffectRunner({
    required this.room,
    required this.sound,
    required this.recorder,
    required this.store,
    required this.host,
    required this.watchPeriod,
    required this.retryDelay,
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
          _putInTheAir(part);
        case PlayStretch(:final stretch):
          _putInTheAir(stretch);
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
      }
    }
  }

  void dispose() {
    endTheWatch();
    _retry?.cancel();
    unawaited(_networkWatch?.cancel());
  }

  void _putInTheAir(Sound part) {
    unawaited(sound.playPart(part));
    host.thePartIsInTheAir();
  }

  void _armTheRetry(Duration delay) {
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      host.answer(const RetryFired());
    });
    if (!host.roomIsReachable) {
      _networkWatch ??= room.networkReturned.listen(
        (_) => host.answer(const RetryFired()),
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
      host.answer(const WatchFired());
    });
  }
}
