import 'dart:async';

import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

import 'a_room_host_double.dart';

/// A sound port that sounds nothing: it writes down what it was asked, and a line or a
/// part ends or opens only when the test says so.
class ASoundPort implements SoundPort {
  final List<String> heard = [];
  Completer<bool>? _line;
  final _ended = StreamController<void>.broadcast(sync: true);
  final _failed = StreamController<void>.broadcast(sync: true);
  final _opened = StreamController<void>.broadcast(sync: true);

  @override
  Duration? partLength;

  @override
  Duration partPosition = Duration.zero;

  @override
  Future<bool> playLine(String url, {void Function()? onSoundStart}) {
    heard.add('line:$url');
    return (_line = Completer<bool>()).future;
  }

  @override
  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    heard.add('asset:$assetPath');
    return (_line = Completer<bool>()).future;
  }

  @override
  Future<bool> playFixedLine(
    String line,
    String language, {
    void Function()? onSoundStart,
  }) {
    heard.add('fixed:$line:$language');
    return (_line = Completer<bool>()).future;
  }

  void endTheLine({bool whole = true}) => _line?.complete(whole);

  @override
  Future<void> playPart(Sound sound) async => heard.add('part:${sound.path}');

  @override
  Stream<void> get partEnded => _ended.stream;

  @override
  Stream<void> get partFailed => _failed.stream;

  @override
  Stream<void> get partOpened => _opened.stream;

  void endThePart() => _ended.add(null);

  void openThePart({required Duration length, Duration at = Duration.zero}) {
    partLength = length;
    partPosition = at;
    _opened.add(null);
  }

  @override
  Future<void> pause() async => heard.add('pause');

  @override
  Future<void> resume() async => heard.add('resume');

  @override
  Future<void> stopTheLine() async => heard.add('stop the line');

  @override
  Future<void> stop() async => heard.add('stop');
}

class ARoomPort implements RoomPort {
  @override
  Stream<void> get networkReturned => const Stream.empty();

  @override
  Future<TurnResult?> lookAt(Turn turn) async => null;
}

/// A recorder port that records nothing: it writes down what it was asked, and a start or
/// a stop answers only when the test says so.
class ARecorderPort implements RecorderPort {
  final List<String> heard = [];
  final List<Completer<MicAnswer>> _starts = [];
  final List<Completer<String?>> _stops = [];
  final _taken = StreamController<bool>.broadcast(sync: true);

  @override
  Future<MicAnswer> start(String take, MicOwner owner) {
    heard.add('start:$take:${owner.name}');
    final start = Completer<MicAnswer>();
    _starts.add(start);
    return start.future;
  }

  void answerTheStart(MicAnswer answer) => _starts.removeAt(0).complete(answer);

  @override
  Future<String?> stop() {
    heard.add('stop');
    final stop = Completer<String?>();
    _stops.add(stop);
    return stop.future;
  }

  void answerTheStop(String? take) => _stops.removeAt(0).complete(take);

  void failTheStop(Exception because) =>
      _stops.removeAt(0).completeError(because);

  @override
  Future<void> discard() async => heard.add('discard');

  @override
  Stream<bool> get taken => _taken.stream;

  void takeTheMicrophone() => _taken.add(true);
}

class AStorePort implements StorePort {
  @override
  Future<int> flushTheOutbox() async => 0;
}

Ports fakePorts(ASoundPort sound, {ARecorderPort? recorder}) => (
  room: ARoomPort(),
  sound: sound,
  recorder: recorder ?? ARecorderPort(),
  store: AStorePort(),
);
