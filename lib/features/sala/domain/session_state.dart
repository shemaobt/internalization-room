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

  /// Whether the beads are on the cord yet.
  ///
  /// The room opens in two movements — the whole passage, then the scene — and the
  /// necklace belongs to the second. Showing it during the first put a full string of
  /// beads over a passage that had not been opened yet. False only while the opening's
  /// first movement is being spoken; true everywhere else, so no other stage can be
  /// caught without it.
  final bool contasEnfiadas;
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
  /// Passages of this book with work waiting in them, by pericope. The ruler draws these
  /// taller, because going back to one is a different act from starting one.
  final Set<String> comecadas;
  final int aOferecer;
  final List<Trecho> btTrechos;
  final int? btFindingChunk;
  /// The room is replaying the stretch a finding landed on.
  final bool btTrechoTocando;
  final bool btClipEnded;
  final bool btParteFronteira;

  /// Whether the rehearsal is running right now.
  ///
  /// Listening and cutting used to be the same tap on the circle, so the room could only
  /// infer what the team had heard. They are two gestures now, and this is the one the
  /// listening gesture owns.
  final bool btClipRodando;
  final List<BtFindingKind> btFindings;
  final int btPass;
  final bool fimClosed;
  final int unsentTakes;
  final int unsentChunks;
  final Set<String> unsentTakeScopes;

  const SalaSessionState({
    this.stage = SalaStage.convite,
    this.voice = VoiceState.invite,
    this.reach = RoomReach.fine,
    this.conviteStep = ConviteStep.boasVindas,
    this.sessionId,
    this.coverage = Coverage.empty,
    this.contasEnfiadas = true,
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
    this.comecadas = const {},
    this.aOferecer = 0,
    this.btTrechos = const [],
    this.btFindingChunk,
    this.btTrechoTocando = false,
    this.btClipEnded = false,
    this.btParteFronteira = false,
    this.btClipRodando = false,
    this.btFindings = const [],
    this.btPass = 1,
    this.fimClosed = false,
    this.unsentTakes = 0,
    this.unsentChunks = 0,
    this.unsentTakeScopes = const {},
  });

  bool get colarOn =>
      stage != SalaStage.convite &&
      stage != SalaStage.escolha &&
      stage != SalaStage.retro;

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

  /// Whether the way out of the rehearsal belongs on the screen at all.
  ///
  /// Apart from whether it can be touched this instant. Gating the widget's existence on
  /// readiness takes its hit box with it, so a finger already travelling toward it during
  /// a ghost play lands on nothing.
  bool get ensaioHasATake => takes >= 1;

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

  /// The same, minus the readiness — see [ensaioHasATake]. Hearing the book overview
  /// again is offered at exactly the same moment as this button, and used to delete it
  /// for the minute or two the overview takes.
  bool get entradaOffered =>
      stage == SalaStage.convite && conviteStep == ConviteStep.entrada;

  bool get hasUnheardReply => replies.any((reply) => !reply.heard);

  HandReply? get oldestUnheardReply {
    for (final reply in replies) {
      if (!reply.heard) return reply;
    }
    return null;
  }

  bool get needsPerson => voice == VoiceState.needsPerson;

  /// Whether a long press would do anything at all.
  ///
  /// `resolveWithPerson` no-ops on a healthy room, and Flutter gives the long press the
  /// arena over the tap — so wiring it unconditionally makes every held press dead. On
  /// the rehearsal circle that meant a finger held down never opened the microphone.
  bool get canResolveWithPerson => needsPerson || offline;

  bool get offline => voice == VoiceState.offline;

  bool get canFinishBackTranslation =>
      stage == SalaStage.retro && btPhase == BtPhase.playing && btClipEnded;

  List<KeptTake> get partes => keptTakes;

  bool get canGhostPlay => partes.isNotEmpty && ensaio == EnsaioStatus.idle;

  SalaSessionState copyWith({
    SalaStage? stage,
    VoiceState? voice,
    RoomReach? reach,
    ConviteStep? conviteStep,
    String? sessionId,
    bool clearSession = false,
    Coverage? coverage,
    bool? contasEnfiadas,
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
    Set<String>? comecadas,
    bool clearRoda = false,
    int? aOferecer,
    List<Trecho>? btTrechos,
    int? btFindingChunk,
    bool clearFindingChunk = false,
    bool? btTrechoTocando,
    bool? btClipEnded,
    bool? btParteFronteira,
    bool? btClipRodando,
    List<BtFindingKind>? btFindings,
    int? btPass,
    bool? fimClosed,
    int? unsentTakes,
    int? unsentChunks,
    Set<String>? unsentTakeScopes,
  }) {
    return SalaSessionState(
      stage: stage ?? this.stage,
      voice: voice ?? this.voice,
      reach: reach ?? this.reach,
      conviteStep: conviteStep ?? this.conviteStep,
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      coverage: coverage ?? this.coverage,
      contasEnfiadas: contasEnfiadas ?? this.contasEnfiadas,
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
      comecadas: comecadas ?? this.comecadas,
      aOferecer: aOferecer ?? this.aOferecer,
      btTrechos: btTrechos ?? this.btTrechos,
      btFindingChunk: clearFindingChunk
          ? null
          : (btFindingChunk ?? this.btFindingChunk),
      btTrechoTocando: btTrechoTocando ?? this.btTrechoTocando,
      btClipEnded: btClipEnded ?? this.btClipEnded,
      btParteFronteira: btParteFronteira ?? this.btParteFronteira,
      btClipRodando: btClipRodando ?? this.btClipRodando,
      btFindings: btFindings ?? this.btFindings,
      btPass: btPass ?? this.btPass,
      fimClosed: fimClosed ?? this.fimClosed,
      unsentTakes: unsentTakes ?? this.unsentTakes,
      unsentChunks: unsentChunks ?? this.unsentChunks,
      unsentTakeScopes: unsentTakeScopes ?? this.unsentTakeScopes,
    );
  }
}
