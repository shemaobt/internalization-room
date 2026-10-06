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

  void openTheMic(String take);

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
  final String Function() offlineNotice;
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
  bool _held = false;
  int _notices = 0;
  List<StreamSubscription<void>>? _partSignals;

  /// [micWasOpen] is what the microphone was before the machine reduced the event that
  /// returned these effects.
  void run(List<Effect> effects, {bool micWasOpen = false}) {
    for (final effect in effects) {
      switch (effect) {
        case SilenceTheRoom():
          host.silenceTheRoom();
          _stopTheSound();
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
          _say(line);
        case PlayPart(:final part):
          _playThePart(part);
        case PlayStretch(:final stretch):
          _playThePart(stretch);
        case OpenTheMic(:final take):
          host.openTheMic(take);
        case StopTheSound():
          _stopTheSound();
        case StopTheLine():
          unawaited(sound.stopTheLine());
        case DropTheLine(:final line):
          host.answer(LineNotSaid(line, generation: generation?.call()));
        case HoldTheSound():
          _ceiling?.cancel();
          _held = true;
          unawaited(sound.pause());
        case LetTheSoundRun():
          _held = false;
          unawaited(sound.resume());
          _armTheCeiling();
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
    endTheWatch();
    _retry?.cancel();
    _ceiling?.cancel();
    unawaited(_networkWatch?.cancel());
    for (final signal in _partSignals ?? const <StreamSubscription<void>>[]) {
      unawaited(signal.cancel());
    }
  }

  void _say(Line line) {
    final stamp = generation?.call();
    final url = line.url;
    final asset = line.asset;
    if (url == null && asset == null) {
      return host.answer(LineNotSaid(line, generation: stamp));
    }
    unawaited(
      _answerTheLine(
        line,
        asset != null
            ? sound.playAsset(asset, onSoundStart: line.onSoundStart)
            : sound.playLine(url!, onSoundStart: line.onSoundStart),
        stamp,
      ),
    );
  }

  Future<void> _answerTheLine(Line line, Future<bool> said, int? stamp) async {
    final bool whole;
    try {
      whole = await said;
    } on RoomFailure catch (failure) {
      return host.answer(
        LineNotSaid(line, because: failure, generation: stamp),
      );
    }
    host.answer(
      whole
          ? PlayerEnded(line: line, generation: stamp)
          : PlayerFailed(line.source, line: line, generation: stamp),
    );
  }

  void _sayTheOfflineNotice() => host.answer(
    LineArrived(
      Line(
        LineKind.offlineNotice,
        ++_notices,
        source: Source.aside(LineKind.offlineNotice.name),
        asset: offlineNotice(),
      ),
      generation: generation?.call(),
    ),
  );

  void _playThePart(Sound part) {
    _part = part;
    _partStamp = generation?.call();
    _held = false;
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
    host.answer(PlayerEnded(generation: _partStamp));
  }

  void _thePartFailed() {
    _ceiling?.cancel();
    final part = _part;
    if (part == null) return;
    host.answer(PlayerFailed(part.source, generation: _partStamp));
  }

  void _thePartOpened() {
    host.answer(PlayerOpened(generation: _partStamp));
    if (!_held) _armTheCeiling();
  }

  /// What is left of the clip plus the grace, or the flat ceiling while the clip is still
  /// opening: a held part counts no time, so its ceiling waits for the resume.
  void _armTheCeiling({bool opening = false}) {
    _ceiling?.cancel();
    final length = opening ? null : sound.partLength;
    final ceiling = length == null ? partCeiling() : _leftOf(length);
    if (ceiling == null) return;
    final stamp = _partStamp;
    _ceiling = Timer(ceiling, () {
      _ceiling = null;
      host.answer(PlayerEnded(generation: stamp));
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
