import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

const _audioSession = MethodChannel('internalization_room/audio_session');

double? _sampleRateBefore;

Future<void> configureRoomAudio() async {
  _sampleRateBefore = await _ask<double>('sampleRate');
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ),
  );
}

Future<void> restoreTheSampleRate() async {
  final rate = _sampleRateBefore;
  if (rate == null) return;
  await _ask<void>('preferSampleRate', rate);
}

Future<T?> _ask<T>(String method, [Object? arguments]) async {
  try {
    return await _audioSession.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
