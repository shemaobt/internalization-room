import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/facilitator_script.dart';
import '../domain/meaning_map.dart';
import '../domain/session_state.dart';
import 'facilitator_voice_service.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';

class SalaSessionNotifier extends Notifier<SalaSessionState> {
  final Map<String, Timer> _timers = {};
  int _epoch = 0;
  String? _pendingTakePath;

  FacilitatorVoiceService get _voice => ref.read(facilitatorVoiceProvider);
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);
  PlaybackRepository get _playback => ref.read(playbackRepositoryProvider);

  @override
  SalaSessionState build() {
    ref.onDispose(_cancelTimers);
    return const SalaSessionState();
  }

  void _after(String key, int ms, VoidCallback fn) {
    _timers[key]?.cancel();
    final epoch = _epoch;
    _timers[key] = Timer(Duration(milliseconds: ms), () {
      if (epoch == _epoch) fn();
    });
  }

  void _cancelTimers() {
    _epoch++;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _clearAll() {
    _cancelTimers();
    unawaited(_voice.stop());
    unawaited(_playback.stop());
  }

  Future<void> _speak(String line, {VoidCallback? onDone}) async {
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.speaking);
    await _voice.speak(line);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
    onDone?.call();
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  Future<void> conviteTap() async {
    if (state.stage != SalaStage.convite || state.voice != VoiceState.invite) {
      return;
    }
    switch (state.conviteStep) {
      case ConviteStep.boasVindas:
        await _speak(FacilitatorScript.boasVindas, onDone: () {
          state = state.copyWith(conviteStep: ConviteStep.panorama);
        });
      case ConviteStep.panorama:
        await _speak(FacilitatorScript.panorama, onDone: () {
          state = state.copyWith(conviteStep: ConviteStep.entrada);
        });
      case ConviteStep.entrada:
        break;
    }
  }

  void goConversa() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.conversa,
      voice: VoiceState.invite,
      lineIndex: -1,
    );
    unawaited(_speak(FacilitatorScript.conversaAbertura));
  }

  void conversaHoldStart() {
    if (state.stage != SalaStage.conversa || state.voice != VoiceState.invite) {
      return;
    }
    state = state.copyWith(voice: VoiceState.listening);
    unawaited(_recorder.start('conversa_${_stamp()}'));
  }

  void conversaHoldEnd() {
    if (state.stage != SalaStage.conversa ||
        state.voice != VoiceState.listening) {
      return;
    }
    unawaited(_recorder.stop());
    state = state.copyWith(voice: VoiceState.thinking);
    _after('think', 1500, () {
      final lineIndex = math.min(
        state.lineIndex + 1,
        FacilitatorScript.linhas.length - 1,
      );
      final surfaced = math.min(RuthOneMeaningMap.count, state.engaged + 2);
      state = state.copyWith(lineIndex: lineIndex, surfaced: surfaced);
      unawaited(
        _speak(FacilitatorScript.linhas[lineIndex], onDone: () {
          final from = state.engaged;
          state = state.copyWith(
            engaged: surfaced,
            ping: PingRange(from, surfaced),
          );
          _after('ping', 700, () {
            state = state.copyWith(clearPing: true);
          });
          if (state.conversaDone) {
            unawaited(_speak(FacilitatorScript.coberturaCompleta));
          }
        }),
      );
    });
  }

  void holdCancel() {
    if (state.voice == VoiceState.listening && state.stage != SalaStage.retro) {
      unawaited(_recorder.discard());
      state = state.copyWith(voice: VoiceState.invite, hand: false);
    }
  }

  void handDown() {
    _after('hand', 450, () {
      state = state.copyWith(hand: true, voice: VoiceState.listening);
      unawaited(_recorder.start('pergunta_${_stamp()}'));
    });
  }

  void handUp() {
    _timers.remove('hand')?.cancel();
    if (!state.hand) return;
    unawaited(_recorder.stop());
    state = state.copyWith(
      hand: false,
      handAck: true,
      knots: state.knots + 1,
      voice: VoiceState.invite,
    );
    unawaited(_speak(FacilitatorScript.maoGuardada));
    _after('ack', 3200, () {
      state = state.copyWith(handAck: false);
    });
  }

  void handCancel() {
    _timers.remove('hand')?.cancel();
    if (state.hand) {
      unawaited(_recorder.discard());
      state = state.copyWith(hand: false, voice: VoiceState.invite);
    }
  }

  void goEnsaio() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
    );
    unawaited(_speak(FacilitatorScript.ensaioAbertura));
  }

  void recStart() {
    if (state.ensaio == EnsaioStatus.recording) return;
    state = state.copyWith(ensaio: EnsaioStatus.recording);
    unawaited(_recorder.start('ensaio_tomada_${_stamp()}'));
  }

  Future<void> recStop() async {
    if (state.ensaio != EnsaioStatus.recording) return;
    _pendingTakePath = await _recorder.stop();
    state = state.copyWith(ensaio: EnsaioStatus.recorded);
  }

  void takePlay() {
    final path = _pendingTakePath;
    if (path != null) unawaited(_playback.play(path));
    state = state.copyWith(playPing: true);
    _after('play', 1800, () {
      state = state.copyWith(playPing: false);
    });
  }

  void takeRedo() {
    final path = _pendingTakePath;
    if (path != null) unawaited(_recorder.delete(path));
    _pendingTakePath = null;
    state = state.copyWith(ensaio: EnsaioStatus.idle);
  }

  void takeKeep() {
    _pendingTakePath = null;
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      takes: state.takes + 1,
    );
  }

  void startRetro() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.retro,
      retroPass: 1,
      retroIndex: 0,
      retroPhase: RetroPhase.ouvir,
      fills: const [0, 0, 0, 0, 0],
      voice: VoiceState.invite,
    );
    _after('hear', 2000, () {
      state = state.copyWith(retroPhase: RetroPhase.falar);
    });
  }

  void retroHoldStart() {
    if (state.retroPhase != RetroPhase.falar ||
        state.voice != VoiceState.invite) {
      return;
    }
    state = state.copyWith(voice: VoiceState.listening);
    unawaited(
      _recorder.start(
        'retro_passada${state.retroPass}_trecho${state.retroIndex + 1}',
      ),
    );
  }

  void retroHoldEnd() {
    if (state.voice != VoiceState.listening || state.stage != SalaStage.retro) {
      return;
    }
    unawaited(_recorder.stop());
    state = state.copyWith(voice: VoiceState.thinking);
    _after('fill', 900, () {
      final fills = List<int>.from(state.fills);
      fills[state.retroIndex] = state.retroPass;
      if (state.retroIndex < RuthOneMeaningMap.segmentCount - 1) {
        state = state.copyWith(
          voice: VoiceState.invite,
          fills: fills,
          retroIndex: state.retroIndex + 1,
          retroPhase: RetroPhase.ouvir,
        );
        _after('hear', 2000, () {
          state = state.copyWith(retroPhase: RetroPhase.falar);
        });
      } else if (state.retroPass == 1) {
        state = state.copyWith(
          voice: VoiceState.invite,
          fills: fills,
          retroPass: 2,
          retroIndex: 0,
          retroPhase: RetroPhase.ouvir,
        );
        unawaited(
          _speak(FacilitatorScript.retroSegundaPassada, onDone: () {
            _after('hear', 1600, () {
              state = state.copyWith(retroPhase: RetroPhase.falar);
            });
          }),
        );
      } else {
        state = state.copyWith(voice: VoiceState.invite, fills: fills);
        _after('fim', 700, () {
          state = state.copyWith(stage: SalaStage.fim);
          _after('close', 1000, () {
            state = state.copyWith(fimClosed: true);
            unawaited(_speak(FacilitatorScript.fecho));
          });
        });
      }
    });
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
  SalaSessionNotifier.new,
);
