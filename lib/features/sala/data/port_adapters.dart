import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/channel.dart';
import '../domain/failure_policy.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';
import '../domain/room_reach.dart';
import '../domain/turn_result.dart';
import 'connectivity_service.dart';
import 'current_session_ledger.dart';
import 'facilitator_voice_service.dart';
import 'finished_passages.dart';
import 'linked_team.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';
import 'room_answer.dart';
import 'room_repository.dart';
import 'take_upload_queue.dart';

class ProviderRoomPort implements RoomPort {
  final Ref _ref;
  bool _gone = false;

  ProviderRoomPort(this._ref) {
    _ref.onDispose(() => _gone = true);
  }

  @override
  Stream<void> get networkReturned =>
      _ref.read(connectivityServiceProvider).onNetworkReturned;

  @override
  Future<TurnResult?> lookAt(Turn turn) async => switch (await _ref
      .read(roomRepositoryProvider)
      .lookAtTheTurn(turn.sessionId, turn.turnId)) {
    Answered(:final value) => value,
    RoomFailure() => null,
  };

  @override
  Future<SessionReadAnswer> readTheSession(String session) async =>
      switch (await _ref.read(roomRepositoryProvider).fetchState(session)) {
        Answered(:final value) => SessionReadAnswered(value),
        final RoomFailure failure => SessionReadFailed(failure.result),
      };

  @override
  Future<RoomReach> reach() =>
      _ref.read(connectivityServiceProvider).reachRoom();

  @override
  Future<RoomResult> askForAPerson(String session) async =>
      _resultOf(await _ref.read(roomRepositoryProvider).askForAPerson(session));

  @override
  Future<TabletCallAnswer> askForAPersonWithoutASession() async {
    final String? deviceId;
    try {
      deviceId = (await _ref.read(linkedTeamProvider).read()).deviceId;
    } on Exception {
      return const TheDeviceLinkUnread();
    }
    if (_gone) return const TheRoomIsGone();
    if (deviceId == null) return const TheTabletIsUnknown();
    return TabletCallAnswered(
      _resultOf(
        await _ref
            .read(roomRepositoryProvider)
            .askForAPersonWithoutASession(deviceId),
      ),
    );
  }

  @override
  Future<RoomResult> personArrived(String session) async =>
      _resultOf(await _ref.read(roomRepositoryProvider).personArrived(session));

  RoomResult _resultOf(RoomAnswer<void> answer) => switch (answer) {
    Answered() => const RoomAnswered(),
    final RoomFailure failure => failure.result,
  };
}

class ProviderSoundPort implements SoundPort {
  final Ref _ref;

  ProviderSoundPort(this._ref);

  FacilitatorVoiceService get _voice => _ref.read(facilitatorVoiceProvider);
  PlaybackRepository get _playback => _ref.read(playbackRepositoryProvider);

  @override
  Future<bool> playLine(String url, {void Function()? onSoundStart}) {
    unawaited(_playback.pause());
    return _voice.play(url, onSoundStart: onSoundStart);
  }

  @override
  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    unawaited(_playback.pause());
    return _voice.playAsset(assetPath, onSoundStart: onSoundStart);
  }

  @override
  Future<bool> playFixedLine(
    String line,
    String language, {
    void Function()? onSoundStart,
  }) {
    unawaited(_playback.pause());
    return _voice.playFixedLine(line, language, onSoundStart: onSoundStart);
  }

  @override
  Future<void> playPart(Sound sound) {
    unawaited(_voice.stop());
    final to = sound.to;
    return to == null
        ? _playback.play(sound.path, from: sound.from)
        : _playback.playRange(sound.path, sound.from, to);
  }

  @override
  Stream<void> get partEnded => _playback.completions;

  @override
  Stream<void> get partFailed => _playback.failures;

  @override
  Stream<void> get partOpened => _playback.openings;

  @override
  Duration? get partLength => _playback.playingLength;

  @override
  Duration get partPosition => _playback.position;

  @override
  Future<void> pause() => _playback.pause();

  @override
  Future<void> resume() => _playback.resume();

  @override
  Future<void> stopTheLine() => _voice.stop();

  @override
  Future<void> stop() => Future.wait([_playback.stop(), _voice.stop()]);
}

class ProviderRecorderPort implements RecorderPort {
  final Ref _ref;

  ProviderRecorderPort(this._ref);

  RecordingRepository get _recorder => _ref.read(recordingRepositoryProvider);

  @override
  Future<MicAnswer> start(String take, MicOwner owner) async =>
      switch (await _recorder.start(take, owner: owner)) {
        Capture.started => MicAnswer.started,
        Capture.denied => MicAnswer.refused,
        Capture.failed => MicAnswer.failed,
      };

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> discard() => _recorder.discard();

  @override
  Stream<bool> get taken => _recorder.interrupted;
}

class ProviderStorePort implements StorePort {
  final Ref _ref;

  ProviderStorePort(this._ref);

  @override
  Future<int> flushTheOutbox() =>
      _ref.read(takeUploadQueueProvider).flush(withTheCodeless: true);

  @override
  Future<void> markThePassageClosed(String book, String passage) =>
      _ref.read(finishedPassagesProvider).add(book, passage).catchError((_) {});

  @override
  Future<CurrentSession?> currentSession() =>
      _ref.read(currentSessionLedgerProvider).read();

  @override
  Future<void> holdTheSession(CurrentSession session) =>
      _ref.read(currentSessionLedgerProvider).hold(session);

  @override
  Future<void> letGoOfTheSession({String? only}) =>
      _ref.read(currentSessionLedgerProvider).letGo(only: only);
}

final roomPortProvider = Provider<RoomPort>(ProviderRoomPort.new);
final soundPortProvider = Provider<SoundPort>(ProviderSoundPort.new);
final recorderPortProvider = Provider<RecorderPort>(ProviderRecorderPort.new);
final storePortProvider = Provider<StorePort>(ProviderStorePort.new);
