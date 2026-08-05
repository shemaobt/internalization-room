import 'meaning_map.dart';

enum SalaStage { convite, conversa, ensaio, retro, fim }

enum VoiceState { invite, listening, thinking, speaking }

enum ConviteStep { boasVindas, panorama, entrada }

enum EnsaioStatus { idle, recording, recorded }

enum RetroPhase { ouvir, falar }

class PingRange {
  final int from;
  final int to;

  const PingRange(this.from, this.to);

  bool contains(int index) => index >= from && index < to;
}

class SalaSessionState {
  final SalaStage stage;
  final VoiceState voice;
  final ConviteStep conviteStep;
  final int lineIndex;
  final int engaged;
  final int surfaced;
  final PingRange? ping;
  final bool hand;
  final bool handAck;
  final int knots;
  final EnsaioStatus ensaio;
  final int takes;
  final bool playPing;
  final int retroPass;
  final int retroIndex;
  final RetroPhase retroPhase;
  final List<int> fills;
  final bool fimClosed;

  const SalaSessionState({
    this.stage = SalaStage.convite,
    this.voice = VoiceState.invite,
    this.conviteStep = ConviteStep.boasVindas,
    this.lineIndex = -1,
    this.engaged = 0,
    this.surfaced = 0,
    this.ping,
    this.hand = false,
    this.handAck = false,
    this.knots = 0,
    this.ensaio = EnsaioStatus.idle,
    this.takes = 0,
    this.playPing = false,
    this.retroPass = 1,
    this.retroIndex = 0,
    this.retroPhase = RetroPhase.ouvir,
    this.fills = const [0, 0, 0, 0, 0],
    this.fimClosed = false,
  });

  bool get colarOn => stage != SalaStage.convite;

  bool get onFim => stage == SalaStage.fim;

  bool get conversaDone =>
      stage == SalaStage.conversa &&
      engaged >= RuthOneMeaningMap.count &&
      voice == VoiceState.invite;

  bool get ensaioDone => takes >= 1 && ensaio == EnsaioStatus.idle;

  bool get showEntrada =>
      stage == SalaStage.convite &&
      conviteStep == ConviteStep.entrada &&
      voice == VoiceState.invite;

  bool get showBook =>
      stage == SalaStage.convite && conviteStep != ConviteStep.boasVindas;

  bool get showListenDot => voice == VoiceState.listening && !hand;

  SalaSessionState copyWith({
    SalaStage? stage,
    VoiceState? voice,
    ConviteStep? conviteStep,
    int? lineIndex,
    int? engaged,
    int? surfaced,
    PingRange? ping,
    bool clearPing = false,
    bool? hand,
    bool? handAck,
    int? knots,
    EnsaioStatus? ensaio,
    int? takes,
    bool? playPing,
    int? retroPass,
    int? retroIndex,
    RetroPhase? retroPhase,
    List<int>? fills,
    bool? fimClosed,
  }) {
    return SalaSessionState(
      stage: stage ?? this.stage,
      voice: voice ?? this.voice,
      conviteStep: conviteStep ?? this.conviteStep,
      lineIndex: lineIndex ?? this.lineIndex,
      engaged: engaged ?? this.engaged,
      surfaced: surfaced ?? this.surfaced,
      ping: clearPing ? null : (ping ?? this.ping),
      hand: hand ?? this.hand,
      handAck: handAck ?? this.handAck,
      knots: knots ?? this.knots,
      ensaio: ensaio ?? this.ensaio,
      takes: takes ?? this.takes,
      playPing: playPing ?? this.playPing,
      retroPass: retroPass ?? this.retroPass,
      retroIndex: retroIndex ?? this.retroIndex,
      retroPhase: retroPhase ?? this.retroPhase,
      fills: fills ?? this.fills,
      fimClosed: fimClosed ?? this.fimClosed,
    );
  }
}
