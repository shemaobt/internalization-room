import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/channel.dart';
import '../domain/ports.dart';
import 'connectivity_service.dart';
import 'facilitator_voice_service.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';
import 'take_upload_queue.dart';

class ProviderRoomPort implements RoomPort {
  final Ref _ref;

  ProviderRoomPort(this._ref);

  @override
  Stream<void> get networkReturned =>
      _ref.read(connectivityServiceProvider).onNetworkReturned;
}

class ProviderSoundPort implements SoundPort {
  final Ref _ref;

  ProviderSoundPort(this._ref);

  FacilitatorVoiceService get _voice => _ref.read(facilitatorVoiceProvider);
  PlaybackRepository get _playback => _ref.read(playbackRepositoryProvider);

  bool _lineSounding = false;
  bool _partSounding = false;

  @override
  Future<bool> playLine(String url, {void Function()? onSoundStart}) =>
      _aLine(() => _voice.play(url, onSoundStart: onSoundStart));

  @override
  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) =>
      _aLine(() => _voice.playAsset(assetPath, onSoundStart: onSoundStart));

  Future<bool> _aLine(Future<bool> Function() say) async {
    if (_partSounding) {
      _partSounding = false;
      unawaited(_playback.stop());
    }
    _lineSounding = true;
    try {
      return await say();
    } finally {
      _lineSounding = false;
    }
  }

  @override
  Future<void> playPart(Sound sound) {
    if (_lineSounding) {
      _lineSounding = false;
      unawaited(_voice.stop());
    }
    _partSounding = true;
    final to = sound.to;
    return to == null
        ? _playback.play(sound.path, from: sound.from)
        : _playback.playRange(sound.path, sound.from, to);
  }

  @override
  Future<void> pause() {
    _partSounding = false;
    return _playback.pause();
  }

  @override
  Future<void> resume() {
    _partSounding = true;
    return _playback.resume();
  }

  @override
  Future<void> stopTheLine() {
    _lineSounding = false;
    return _voice.stop();
  }

  @override
  Future<void> stop() async {
    _partSounding = false;
    _lineSounding = false;
    unawaited(_playback.stop());
    unawaited(_voice.stop());
  }
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
