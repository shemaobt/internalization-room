import 'bt_finding.dart';
import 'spoken_line.dart';
import 'coverage.dart';
import 'hand_reply.dart';
import 'kept_take.dart';

enum SalaStage { convite, conversa, ensaio, retro, fim }

enum VoiceState { invite, listening, thinking, speaking, done, needsPerson, offline }

enum ConviteStep { boasVindas, panorama, entrada }

enum EnsaioStatus { idle, ghostPlaying, recording, recorded }

enum BtPhase { playing, capturing, thinking, findings, conferida }

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
  final String? sessionId;
  final Coverage coverage;
  final PingRange? ping;
  final bool peerCue;
  final bool noteMode;
  final bool handAck;
  final int knots;
  final List<HandReply> replies;
  final String? playingReplyId;
  final List<KeptTake> keptTakes;
  final String? replayingScope;
  final SpokenLine? lastSpoken;
  final EnsaioStatus ensaio;
  final int takes;
  final bool playPing;
  final BtPhase btPhase;
  final List<int> btChunkPasses;
  final bool btClipEnded;
  final List<BtFindingKind> btFindings;
  final int btPass;
  final bool fimClosed;

  const SalaSessionState({
    this.stage = SalaStage.convite,
    this.voice = VoiceState.invite,
    this.conviteStep = ConviteStep.boasVindas,
    this.sessionId,
    this.coverage = Coverage.empty,
    this.ping,
    this.peerCue = false,
    this.noteMode = false,
    this.handAck = false,
    this.knots = 0,
    this.replies = const [],
    this.playingReplyId,
    this.keptTakes = const [],
    this.replayingScope,
    this.lastSpoken,
    this.ensaio = EnsaioStatus.idle,
    this.takes = 0,
    this.playPing = false,
    this.btPhase = BtPhase.playing,
    this.btChunkPasses = const [],
    this.btClipEnded = false,
    this.btFindings = const [],
    this.btPass = 1,
    this.fimClosed = false,
  });

  bool get colarOn => stage != SalaStage.convite;

  bool get onFim => stage == SalaStage.fim;

  bool get conversaDone =>
      stage == SalaStage.conversa && voice == VoiceState.done;

  bool get ensaioDone => takes >= 1 && ensaio == EnsaioStatus.idle;

  bool get awaitingFirstTouch =>
      stage == SalaStage.convite &&
      conviteStep == ConviteStep.boasVindas &&
      voice == VoiceState.invite;

  bool get canHearAgain =>
      lastSpoken != null &&
      voice == VoiceState.invite &&
      stage != SalaStage.ensaio;

  bool get showEntrada =>
      stage == SalaStage.convite &&
      conviteStep == ConviteStep.entrada &&
      voice == VoiceState.invite;

  bool get hasUnheardReply => replies.any((reply) => !reply.heard);

  HandReply? get oldestUnheardReply {
    for (final reply in replies) {
      if (!reply.heard) return reply;
    }
    return null;
  }

  bool get needsPerson => voice == VoiceState.needsPerson;

  bool get offline => voice == VoiceState.offline;

  bool get canFinishBackTranslation =>
      stage == SalaStage.retro && btPhase == BtPhase.playing && btClipEnded;

  KeptTake? get wholeTake {
    for (final take in keptTakes) {
      if (take.scopeId == KeptScope.whole) return take;
    }
    return null;
  }

  bool get canGhostPlay => wholeTake != null && ensaio == EnsaioStatus.idle;

  SalaSessionState copyWith({
    SalaStage? stage,
    VoiceState? voice,
    ConviteStep? conviteStep,
    String? sessionId,
    bool clearSession = false,
    Coverage? coverage,
    PingRange? ping,
    bool clearPing = false,
    bool? peerCue,
    bool? noteMode,
    bool? handAck,
    int? knots,
    List<HandReply>? replies,
    String? playingReplyId,
    bool clearPlayingReply = false,
    List<KeptTake>? keptTakes,
    String? replayingScope,
    bool clearReplayingScope = false,
    SpokenLine? lastSpoken,
    bool clearLastSpoken = false,
    EnsaioStatus? ensaio,
    int? takes,
    bool? playPing,
    BtPhase? btPhase,
    List<int>? btChunkPasses,
    bool? btClipEnded,
    List<BtFindingKind>? btFindings,
    int? btPass,
    bool? fimClosed,
  }) {
    return SalaSessionState(
      stage: stage ?? this.stage,
      voice: voice ?? this.voice,
      conviteStep: conviteStep ?? this.conviteStep,
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      coverage: coverage ?? this.coverage,
      ping: clearPing ? null : (ping ?? this.ping),
      peerCue: peerCue ?? this.peerCue,
      noteMode: noteMode ?? this.noteMode,
      handAck: handAck ?? this.handAck,
      knots: knots ?? this.knots,
      replies: replies ?? this.replies,
      playingReplyId:
          clearPlayingReply ? null : (playingReplyId ?? this.playingReplyId),
      keptTakes: keptTakes ?? this.keptTakes,
      replayingScope: clearReplayingScope
          ? null
          : (replayingScope ?? this.replayingScope),
      lastSpoken: clearLastSpoken ? null : (lastSpoken ?? this.lastSpoken),
      ensaio: ensaio ?? this.ensaio,
      takes: takes ?? this.takes,
      playPing: playPing ?? this.playPing,
      btPhase: btPhase ?? this.btPhase,
      btChunkPasses: btChunkPasses ?? this.btChunkPasses,
      btClipEnded: btClipEnded ?? this.btClipEnded,
      btFindings: btFindings ?? this.btFindings,
      btPass: btPass ?? this.btPass,
      fimClosed: fimClosed ?? this.fimClosed,
    );
  }
}
