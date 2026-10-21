import 'dart:async';

import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';

import 'a_station_host_double.dart';

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
  Duration linePosition = Duration.zero;

  @override
  Duration? lineLength;

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

/// A room port that reaches nothing: it writes down what it was asked, and a Session read,
/// a reach or a call for a person answers only when the test says so.
class ARoomPort implements RoomPort {
  final List<String> heard = [];
  final List<Completer<SessionReadAnswer>> _reads = [];
  final List<Completer<RoomReach>> _reaches = [];

  @override
  Stream<void> get networkReturned => const Stream.empty();

  @override
  Future<LookAnswer> lookAt(Turn turn) async => const NothingLanded();

  @override
  Future<SessionReadAnswer> readTheSession(String session) {
    heard.add('read:$session');
    final read = Completer<SessionReadAnswer>();
    _reads.add(read);
    return read.future;
  }

  void answerTheRead(SessionReadAnswer answer) =>
      _reads.removeAt(0).complete(answer);

  final List<Completer<SceneRehearsalsAnswer>> _sceneReads = [];

  @override
  Future<SceneRehearsalsAnswer> sceneRehearsalsOf(String session) {
    heard.add('sceneRehearsals:$session');
    final read = Completer<SceneRehearsalsAnswer>();
    _sceneReads.add(read);
    return read.future;
  }

  void answerTheSceneRehearsals(SceneRehearsalsAnswer answer) =>
      _sceneReads.removeAt(0).complete(answer);

  @override
  Future<RoomReach> reach() {
    heard.add('reach');
    final reach = Completer<RoomReach>();
    _reaches.add(reach);
    return reach.future;
  }

  void answerTheReach(RoomReach reach) => _reaches.removeAt(0).complete(reach);

  final List<Completer<RoomResult>> _calls = [];

  @override
  Future<RoomResult> askForAPerson(String session) {
    heard.add('call:$session');
    final call = Completer<RoomResult>();
    _calls.add(call);
    return call.future;
  }

  void answerTheCall(RoomResult result) => _calls.removeAt(0).complete(result);
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
  final List<String> heard = [];
  final List<Completer<int>> _flushes = [];
  CurrentSession? _held;

  @override
  Future<int> flushTheOutbox() {
    heard.add('flush');
    final flush = Completer<int>();
    _flushes.add(flush);
    return flush.future;
  }

  void answerTheFlush() => _flushes.removeAt(0).complete(0);

  void failTheFlush(Exception because) =>
      _flushes.removeAt(0).completeError(because);

  @override
  Future<CurrentSession?> currentSession() async => _held;

  @override
  Future<void> holdTheSession(CurrentSession session) async => _held = session;

  @override
  Future<void> letGoOfTheSession({String? only}) async {
    if (only == null || _held?.sessionId == only) _held = null;
  }
}

Ports fakePorts(
  ASoundPort sound, {
  ARecorderPort? recorder,
  ARoomPort? room,
  AStorePort? store,
}) => (
  room: room ?? ARoomPort(),
  sound: sound,
  recorder: recorder ?? ARecorderPort(),
  store: store ?? AStorePort(),
);
