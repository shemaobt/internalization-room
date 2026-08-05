import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class FacilitatorVoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.48);
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
  }

  Future<void> speak(String line) async {
    try {
      await _configure();
      await _tts.speak(line);
    } on Exception {
      final fallback = Duration(milliseconds: 400 + line.length * 55);
      await Future<void>.delayed(fallback);
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Exception {
      return;
    }
  }
}

final facilitatorVoiceProvider = Provider<FacilitatorVoiceService>(
  (ref) => FacilitatorVoiceService(),
);
