import 'bt_finding.dart';
import 'spoken_line.dart';
import '../data/connectivity_service.dart';
import 'coverage.dart';
import 'hand_reply.dart';
import 'kept_take.dart';
import 'passagem.dart';

enum SalaStage { convite, escolha, conversa, ensaio, retro, fim }

enum VoiceState { invite, listening, thinking, speaking, done, needsPerson, offline, blocked }

enum ConviteStep { boasVindas, panorama, entrada }

enum EnsaioStatus { idle, ghostPlaying, recording, recorded }

enum BtPhase { playing, capturing, thinking, findings, conferida }

class Trecho {
  final int index;
  final Duration from;
  final Duration to;

  const Trecho({required this.index, required this.from, required this.to});
}

class PingRange {
  final int from;
  final int to;

  const PingRange(this.from, this.to);

  bool contains(int index) => index >= from && index < to;
}

class SalaSessionState {
  final SalaStage stage;
  final VoiceState voice;
  /// Why the room is out of reach, when it is. Two different faces: a tablet with no
  /// network at all, and a network that is fine with no room answering on it.
  final RoomReach reach;
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
  final SpokenLine? lastSpoken;
  final EnsaioStatus ensaio;
  final int takes;
  final bool playPing;
  final BtPhase btPhase;
  final List<int> btChunkPasses;
  /// Which stretch numbers the room never took, in the order they were told.
  ///
  /// A count could not say this. `btChunkPasses` only grows when a stretch lands, and the
  /// unsent count only grows when one fails — two disjoint sets, so subtracting one from
  /// the other hollowed a bead belonging to a stretch that had arrived while the stretch
  /// actually at risk had no bead at all.
  final List<int> btChunkFailures;
  /// The passages still to be worked, or null when the wheel has not been read.
  ///
  /// Null and empty must stay apart: empty is a finished book, and the room says so out
  /// loud. A failed load answering "empty" told the team the work was over.
  final List<Passagem>? naRoda;
  final int aOferecer;
  final List<Trecho> btTrechos;
  final int? btFindingChunk;
  /// The room is replaying the stretch a finding landed on.
  final bool btTrechoTocando;
  final bool btClipEnded;
  final List<BtFindingKind> btFindings;
  final int btPass;
  final bool fimClosed;
  final int unsentTakes;
  final int unsentChunks;

  const SalaSessionState({
    this.stage = SalaStage.convite,
    this.voice = VoiceState.invite,
    this.reach = RoomReach.fine,
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
    this.lastSpoken,
    this.ensaio = EnsaioStatus.idle,
    this.takes = 0,
    this.playPing = false,
    this.btPhase = BtPhase.playing,
    this.btChunkPasses = const [],
    this.btChunkFailures = const [],
    this.naRoda,
    this.aOferecer = 0,
    this.btTrechos = const [],
    this.btFindingChunk,
    this.btTrechoTocando = false,
    this.btClipEnded = false,
    this.btFindings = const [],
    this.btPass = 1,
    this.fimClosed = false,
    this.unsentTakes = 0,
    this.unsentChunks = 0,
  });

  bool get colarOn =>
      stage != SalaStage.convite && stage != SalaStage.escolha;

  Passagem? get oferecida {
    final roda = naRoda;
    if (roda == null || aOferecer < 0 || aOferecer >= roda.length) return null;
    return roda[aOferecer];
  }

  bool get rodaPorLer => stage == SalaStage.escolha && naRoda == null;

  bool get livroInteiroFeito =>
      stage == SalaStage.escolha && naRoda != null && naRoda!.isEmpty;

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
      stage != SalaStage.ensaio &&
      // In the retro the team's own recording is running under an `invite` circle, and
      // the facilitator's line would have played on top of it, from a second player.
      stage != SalaStage.retro;

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
    RoomReach? reach,
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
    SpokenLine? lastSpoken,
    bool clearLastSpoken = false,
    EnsaioStatus? ensaio,
    int? takes,
    bool? playPing,
    BtPhase? btPhase,
    List<int>? btChunkPasses,
    List<int>? btChunkFailures,
    List<Passagem>? naRoda,
    bool clearRoda = false,
    int? aOferecer,
    List<Trecho>? btTrechos,
    int? btFindingChunk,
    bool clearFindingChunk = false,
    bool? btTrechoTocando,
    bool? btClipEnded,
    List<BtFindingKind>? btFindings,
    int? btPass,
    bool? fimClosed,
    int? unsentTakes,
    int? unsentChunks,
  }) {
    return SalaSessionState(
      stage: stage ?? this.stage,
      voice: voice ?? this.voice,
      reach: reach ?? this.reach,
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
      lastSpoken: clearLastSpoken ? null : (lastSpoken ?? this.lastSpoken),
      ensaio: ensaio ?? this.ensaio,
      takes: takes ?? this.takes,
      playPing: playPing ?? this.playPing,
      btPhase: btPhase ?? this.btPhase,
      btChunkPasses: btChunkPasses ?? this.btChunkPasses,
      btChunkFailures: btChunkFailures ?? this.btChunkFailures,
      naRoda: clearRoda ? null : (naRoda ?? this.naRoda),
      aOferecer: aOferecer ?? this.aOferecer,
      btTrechos: btTrechos ?? this.btTrechos,
      btFindingChunk: clearFindingChunk
          ? null
          : (btFindingChunk ?? this.btFindingChunk),
      btTrechoTocando: btTrechoTocando ?? this.btTrechoTocando,
      btClipEnded: btClipEnded ?? this.btClipEnded,
      btFindings: btFindings ?? this.btFindings,
      btPass: btPass ?? this.btPass,
      fimClosed: fimClosed ?? this.fimClosed,
      unsentTakes: unsentTakes ?? this.unsentTakes,
      unsentChunks: unsentChunks ?? this.unsentChunks,
    );
  }
}
