import 'dart:async';

import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
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
/// a reach, a call for a person or a person-arrived mark answers only when the test says
/// so.
class ARoomPort implements RoomPort {
  final List<String> heard = [];
  final List<Completer<SessionReadAnswer>> _reads = [];
  final List<Completer<RoomReach>> _reaches = [];

  @override
  Stream<void> get networkReturned => const Stream.empty();

  @override
  Future<TurnResult?> lookAt(Turn turn) async => null;

  @override
  Future<SessionReadAnswer> readTheSession(String session) {
    heard.add('read:$session');
    final read = Completer<SessionReadAnswer>();
    _reads.add(read);
    return read.future;
  }

  void answerTheRead(SessionReadAnswer answer) =>
      _reads.removeAt(0).complete(answer);

  @override
  Future<RoomReach> reach() {
    heard.add('reach');
    final reach = Completer<RoomReach>();
    _reaches.add(reach);
    return reach.future;
  }

  void answerTheReach(RoomReach reach) => _reaches.removeAt(0).complete(reach);

  final List<Completer<RoomResult>> _calls = [];
  final List<Completer<TabletCallAnswer>> _tabletCalls = [];
  final List<Completer<RoomResult>> _arrivals = [];

  @override
  Future<RoomResult> askForAPerson(String session) {
    heard.add('call:$session');
    final call = Completer<RoomResult>();
    _calls.add(call);
    return call.future;
  }

  void answerTheCall(RoomResult result) => _calls.removeAt(0).complete(result);

  @override
  Future<TabletCallAnswer> askForAPersonWithoutASession() {
    heard.add('call by the tablet');
    final call = Completer<TabletCallAnswer>();
    _tabletCalls.add(call);
    return call.future;
  }

  void answerTheTabletCall(TabletCallAnswer answer) =>
      _tabletCalls.removeAt(0).complete(answer);

  @override
  Future<RoomResult> personArrived(String session) {
    heard.add('arrived:$session');
    final arrival = Completer<RoomResult>();
    _arrivals.add(arrival);
    return arrival.future;
  }

  void answerTheArrival(RoomResult result) =>
      _arrivals.removeAt(0).complete(result);
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

Ports fakePorts(ASoundPort sound, {ARecorderPort? recorder, ARoomPort? room}) =>
    (
      room: room ?? ARoomPort(),
      sound: sound,
      recorder: recorder ?? ARecorderPort(),
      store: AStorePort(),
    );
