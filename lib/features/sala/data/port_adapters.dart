import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/channel.dart';
import '../domain/machine.dart';
import '../domain/ports.dart';
import '../domain/turn_result.dart';
import 'connectivity_service.dart';
import 'facilitator_voice_service.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';
import 'room_answer.dart';
import 'room_repository.dart';
import 'take_upload_queue.dart';

class ProviderRoomPort implements RoomPort {
  final Ref _ref;

  ProviderRoomPort(this._ref);

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
}

class ProviderSoundPort implements SoundPort {
  final Ref _ref;

  ProviderSoundPort(this._ref);

  FacilitatorVoiceService get _voice => _ref.read(facilitatorVoiceProvider);
  PlaybackRepository get _playback => _ref.read(playbackRepositoryProvider);

  @override
  Future<bool> playLine(String url, {void Function()? onSoundStart}) {
    unawaited(_playback.stop());
    return _voice.play(url, onSoundStart: onSoundStart);
  }

  @override
  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    unawaited(_playback.stop());
    return _voice.playAsset(assetPath, onSoundStart: onSoundStart);
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

  @override
  Future<void> discard() => _ref.read(recordingRepositoryProvider).discard();
}

class ProviderStorePort implements StorePort {
  final Ref _ref;

  ProviderStorePort(this._ref);

  @override
  Future<int> flushTheOutbox() =>
      _ref.read(takeUploadQueueProvider).flush(withTheCodeless: true);
}

final roomPortProvider = Provider<RoomPort>(ProviderRoomPort.new);
final soundPortProvider = Provider<SoundPort>(ProviderSoundPort.new);
final recorderPortProvider = Provider<RecorderPort>(ProviderRecorderPort.new);
final storePortProvider = Provider<StorePort>(ProviderStorePort.new);
