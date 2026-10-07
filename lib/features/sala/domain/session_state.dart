import 'channel.dart';
import 'halt.dart';
import 'machine.dart';
import 'spoken_line.dart';
import 'room_reach.dart';
import 'coverage.dart';
import 'hand_reply.dart';
import 'kept_take.dart';
import 'passagem.dart';
import 'station.dart';

enum SalaStage { panorama, escolha, conversa, ensaio, retro, fim }

enum VoiceState {
  invite,
  listening,
  thinking,
  speaking,
  done,
  offline,
  blocked,
}

enum EnsaioStatus { idle, recording, recorded }

/// How far short of a part's end the told ground may stop and still count as its end.
///
/// The last cut of a part is made where the clip stopped, and a position read as a
/// clip finishes can sit a little before the length measured without playing it. This
/// end's choice: the number is the slack the room's gate was read to allow itself when
/// it checks what was heard, not a contract the room promises.
const folgaDoFimDaParte = Duration(milliseconds: 750);

/// Where the telling-back is, step by step.
enum BtPhase { playing, capturing, thinking, findings, conferida }

/// One stretch the team told back: a slice of one rehearsal recording.
///
/// [from] and [to] are relative to [takeId]'s own file, never to the concatenated
/// passage. It was the globalness, not the use of intervals, that made re-recording one
/// stretch shift every stretch after it.
///
/// [parte] is which recording that is, by its place in the rehearsal. The listening ruler
/// reads the whole rehearsal as one line, and it is the offset of the part that carries a
/// local address onto it.
class Trecho {
  /// The room's own name for this stretch, or null while it has not said one.
  ///
  /// Telling a stretch back answers with a count and no name, so a stretch is nameless
  /// until the room's reading of the session is read back. A nameless one matches no
  /// pointer, which is the answer a pointer naming nothing should get anyway.
  final String? segmentId;
  final String takeId;

  /// The tablet's own copy of what the team said in Portuguese about this stretch, when
  /// this tablet is the one that said it. Null on a session picked back up, where the
  /// telling exists on the server and the file does not.
  final String? retroPath;
  final int parte;
  final Duration from;
  final Duration to;

  /// Where this stretch begins in [parte], and where it ends there.
  ///
  /// Its place, which a correction never moves — as against [from] and [to], which say
  /// what plays and which a correction by the long way replaces outright. Told again over
  /// a recording of its own, a stretch of six seconds became a take of twenty-seven, and
  /// with one number for both the cord drew those twenty-seven seconds over its
  /// neighbours and the room counted the part as told that far.
  ///
  /// On a stretch nobody has corrected the two are the same interval, and it is said so
  /// at each of the three places one is built rather than defaulted quietly: a stretch
  /// with no place is not a thing this room has.
  final Duration lugarFrom;
  final Duration lugarTo;

  /// Whether the team has explained this stretch yet. False on a half a division just
  /// made: it is a unit the room counts and nobody has told back.
  final bool contado;

  const Trecho({
    required this.segmentId,
    required this.takeId,
    this.retroPath,
    required this.parte,
    required this.from,
    required this.to,
    this.contado = true,
    required this.lugarFrom,
    required this.lugarTo,
  });
}

class LeftEntry {
  final String? pericope;
  final bool panorama;
  final String? session;
  final bool said;
  final Paused? held;

  const LeftEntry({
    this.pericope,
    this.panorama = false,
    this.session,
    this.said = false,
    this.held,
  });
}

class SalaSessionState {
  final bool awaitingTheGuide;

  /// The entry the team last left by the way out, for the Choice to offer the way back.
  final LeftEntry? leftEntry;
  final bool endOfThePassage;

  /// Why the room is out of reach, when it is. Two different faces: a tablet with no
  /// network at all, and a network that is fine with no room answering on it.
  final RoomReach reach;

  /// Whether the Panorama's line was said on this visit to its Station; from then on the
  /// circle records the team's turn.
  final bool panoramaSaid;
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
  final bool peerCue;
  final bool noteMode;
  final bool handAck;
  final bool questionPending;
  final List<HandReply> replies;
  final String? playingReplyId;
  final List<KeptTake> keptTakes;
  final SpokenLine? lastSpoken;
  final EnsaioStatus ensaio;
  final bool micTaken;
  final int takes;

  final BtPhase btPhase;

  /// Which stretch numbers the room never took, in the order they were told.
  ///
  /// A count could not say this. A stretch is added only when one lands, and the unsent
  /// count only grows when one fails — two disjoint sets, so subtracting one from the
  /// other hollowed a bead belonging to a stretch that had arrived while the stretch
  /// actually at risk had no bead at all.
  final List<int> btChunkFailures;

  /// Every passage the book offers, or null when the wheel has not been read.
  ///
  /// Null and empty must stay apart: empty is a room that answered with no passage at
  /// all, and it says so out loud. A failed load answering "empty" told the team the
  /// work was over.
  final List<Passagem>? naRoda;

  /// Passages of this book with work waiting in them, by pericope. The ruler draws these
  /// taller, because going back to one is a different act from starting one.
  final Set<String> comecadas;
  final Set<String> feitas;
  final int aOferecer;
  final List<Trecho> btTrechos;
  final String? btFindingSegmentId;

  final bool btClipEnded;
  final bool btParteFronteira;

  final List<int> btFimDasPartesMs;
  final int btParteNoArMs;
  final int btOuvidoMs;
  final Duration btCursor;
  final Duration btCorte;

  /// Whether the head has passed [btCursor] since it was last set — the one fact the
  /// capture, the scissors and the circle's label all read to ask whether anything has
  /// been heard since the cursor.
  final bool btOuvidoAlemDoCursor;
  final int btParte;
  final String? btTraducaoPendente;
  final String? btTraducaoEmprestada;
  final Trecho? btTrechoTraduzidoDeNovo;
  final int? btContaEscolhida;
  final int btPass;
  final int unsentTakes;
  final int unsentChunks;
  final Set<String> unsentTakeScopes;

  final Machine machine;

  /// Which part of the rehearsal the team came back to record again, 0-based, or null when
  /// the next recording is a part of its own.
  ///
  /// The rehearsal screen draws it and the record circle names it, so it is a fact of the
  /// session rather than a private count in the notifier: mirrored in two places the two
  /// drifted, and the screen said a new part was being recorded over a gesture that was
  /// replacing one.
  final int? parteARegravar;

  /// Whether the bead at [index] does not apply right now (ADR 0040: dimmed means it does
  /// not apply). True for every part but the one a finding sent the team back to record,
  /// while that record-again stands open and nothing has been recorded for it yet. Once
  /// that recording is pending — waiting for the green check — every bead applies again,
  /// so this reads false throughout: the one rule the row and the tap both read, instead
  /// of the row drawing dim on a bead the tap would still play.
  bool beadIsDimmed(int index) {
    final again = parteARegravar;
    return ensaio == EnsaioStatus.idle &&
        again != null &&
        again < partes.length &&
        index != again;
  }

  const SalaSessionState({
    this.awaitingTheGuide = false,
    this.leftEntry,
    this.endOfThePassage = false,
    this.reach = RoomReach.fine,
    this.panoramaSaid = false,
    this.sessionId,
    this.coverage = Coverage.empty,
    this.contasEnfiadas = true,
    this.peerCue = false,
    this.noteMode = false,
    this.handAck = false,
    this.questionPending = false,
    this.replies = const [],
    this.playingReplyId,
    this.keptTakes = const [],
    this.lastSpoken,
    this.ensaio = EnsaioStatus.idle,
    this.micTaken = false,
    this.takes = 0,
    this.btPhase = BtPhase.playing,
    this.btChunkFailures = const [],
    this.naRoda,
    this.comecadas = const {},
    this.feitas = const {},
    this.aOferecer = 0,
    this.btTrechos = const [],
    this.btFindingSegmentId,
    this.btClipEnded = false,
    this.btParteFronteira = false,
    this.btFimDasPartesMs = const [],
    this.btParteNoArMs = 0,
    this.btOuvidoMs = 0,
    this.btCursor = Duration.zero,
    this.btCorte = Duration.zero,
    this.btOuvidoAlemDoCursor = false,
    this.btParte = 0,
    this.btTraducaoPendente,
    this.btTraducaoEmprestada,
    this.btTrechoTraduzidoDeNovo,
    this.btContaEscolhida,
    this.btPass = 1,
    this.unsentTakes = 0,
    this.unsentChunks = 0,
    this.unsentTakeScopes = const {},
    this.machine = const Machine(),
    this.parteARegravar,
  });

  bool get colarOn => stage == SalaStage.conversa || stage == SalaStage.fim;

  Passagem? get oferecida {
    if (wheelHalted) return null;
    final roda = naRoda;
    if (roda == null || aOferecer < 0 || aOferecer >= roda.length) return null;
    return roda[aOferecer];
  }

  bool get rodaPorLer => stage == SalaStage.escolha && naRoda == null;

  /// The panorama's own spoke, when the wheel offers one, never counts as a passage the
  /// room can offer: a wheel holding nothing else is a book the room has nothing to say
  /// about, and the spoke to hear it again is not something to work on.
  bool get livroInteiroFeito =>
      stage == SalaStage.escolha &&
      naRoda != null &&
      naRoda!.every((passagem) => passagem.isPanorama);

  bool get onFim => stage == SalaStage.fim;

  bool get ensaioDone =>
      takes >= 1 && ensaio == EnsaioStatus.idle && parteARegravar == null;

  bool get canHearAgain =>
      lastSpoken != null &&
      voice == VoiceState.invite &&
      !needsPerson &&
      stage != SalaStage.ensaio &&
      stage != SalaStage.retro;

  bool get hasUnheardReply => replies.any((reply) => reply.offered);

  HandReply? get oldestUnheardReply {
    for (final reply in replies) {
      if (reply.offered) return reply;
    }
    return null;
  }

  Station get station => machine.station;

  SalaStage get stage => station.stage;

  Halt get halt => machine.halt;

  Channel get channel => machine.channel;

  VoiceState get voice {
    if (halt is Blocking) return VoiceState.invite;
    if (unreachable && channel is! Microphone) return VoiceState.offline;
    return switch (channel) {
      Microphone(owner: MicOwner.rehearsal) => _resting,
      Microphone() => VoiceState.listening,
      GuideSpeaking(line: Line(kind: LineKind.guide || LineKind.approved)) =>
        VoiceState.speaking,
      GuideSpeaking(line: Line(kind: LineKind.acknowledgement))
          when machine.queue.any((line) => line.kind == LineKind.guide) =>
        VoiceState.speaking,
      _ => _resting,
    };
  }

  VoiceState get _resting {
    if (awaitingTheGuide) return VoiceState.thinking;
    if (endOfThePassage ||
        stage == SalaStage.fim ||
        (stage == SalaStage.retro && btPhase == BtPhase.conferida)) {
      return VoiceState.done;
    }
    return VoiceState.invite;
  }

  bool get btClipRodando => stage == SalaStage.retro && channel is PartPlaying;

  bool get btTrechoTocando => switch (channel) {
    StretchPlaying(stretch: StretchSound(telling: false)) => true,
    _ => false,
  };

  bool get btRetroTocando => switch (channel) {
    StretchPlaying(stretch: StretchSound(telling: true)) => true,
    _ => false,
  };

  Channel get _paused => switch (channel) {
    GuideSpeaking(held: final Paused held) => held,
    _ => channel,
  };

  bool get btTrechoPausada => switch (_paused) {
    Paused(what: StretchSound(telling: false)) => true,
    _ => false,
  };

  bool get btRetroPausada => switch (_paused) {
    Paused(what: StretchSound(telling: true)) => true,
    _ => false,
  };

  bool get playPing => stage == SalaStage.ensaio && channel is PartPlaying;

  bool get takePaused => switch (_paused) {
    Paused(what: PartSound()) => stage == SalaStage.ensaio,
    _ => false,
  };

  int? get parteDoEnsaioTocando {
    if (stage != SalaStage.ensaio) return null;
    return switch (_paused) {
      PartPlaying(:final part) => part.part,
      Paused(what: final PartSound part) => part.part,
      _ => null,
    };
  }

  bool get needsPerson => halt is Blocking;

  /// The way out of a Station is hidden while it cannot apply: the voice is busy, or a
  /// microphone other than the raised-hand note's is open, or a person is called, except
  /// at the Back-translation's resting screen (ADR 0019).
  bool get wayOutIsHidden {
    if (needsPerson) {
      return !(stage == SalaStage.retro && btPhase == BtPhase.conferida);
    }
    return switch (voice) {
      VoiceState.thinking || VoiceState.speaking => true,
      _ => switch (channel) {
        Microphone(:final owner) => owner != MicOwner.question,
        _ => false,
      },
    };
  }

  bool get warning => halt is Warning;

  bool get wheelHalted => switch (halt) {
    Blocking(kept: TheWheel()) => true,
    _ => false,
  };

  bool get canResolveWithPerson => needsPerson || offline;

  bool get offline => voice == VoiceState.offline;

  bool get unreachable => !machine.reachable;

  bool get canFinishBackTranslation =>
      stage == SalaStage.retro && btPhase == BtPhase.playing && btClipEnded;

  bool get _btNaVez =>
      stage == SalaStage.retro &&
      btPhase == BtPhase.playing &&
      !needsPerson &&
      !offline;

  bool get btCortado => btCorte > btCursor;

  /// Whether nothing has been heard since the cursor: the guard the capture, the
  /// scissors and the circle's label all share.
  bool get nothingHeardSinceCursor => !btOuvidoAlemDoCursor;

  int? get _btInicioDaParteMs {
    if (btParte == 0) return 0;
    if (btParte > btFimDasPartesMs.length) return null;
    return btFimDasPartesMs[btParte - 1];
  }

  int? get _btParteMs {
    final inicio = _btInicioDaParteMs;
    if (inicio == null || btParte >= btFimDasPartesMs.length) return null;
    return btFimDasPartesMs[btParte] - inicio;
  }

  bool get _btParteContada {
    final parte = _btParteMs;
    if (parte == null) return btClipEnded;
    return (btCursor + folgaDoFimDaParte).inMilliseconds >= parte;
  }

  bool get btContadaInteira =>
      btClipEnded && _btParteContada && btTraducaoPendente == null;

  bool get canAdvanceToTheVerdict =>
      canFinishBackTranslation && btContadaInteira && btContaEscolhida == null;

  bool get btRestoDepoisDoCorte {
    if (!btCortado) return false;
    final parte = _btParteMs;
    return btParte < partes.length - 1 ||
        parte == null ||
        (btCorte + folgaDoFimDaParte).inMilliseconds < parte;
  }

  bool get canCut {
    if (!_btNaVez || btTraducaoPendente != null) return false;
    if (btTrechoTraduzidoDeNovo != null || btContaEscolhida != null) {
      return false;
    }
    if (btTrechoTocando || btTrechoPausada) {
      return btCortado && !btClipEnded && !btParteFronteira;
    }
    if (btClipRodando) return true;
    if (btClipEnded || btParteFronteira) return false;
    final inicio = _btInicioDaParteMs;
    if (inicio == null) return false;
    final cabeca = btOuvidoMs - inicio;
    final limite = btCortado ? btCorte.inMilliseconds : _btParteMs;
    return cabeca > btCursor.inMilliseconds &&
        (limite == null || cabeca < limite);
  }

  bool get btTraducaoPendenteEmprestada =>
      btTraducaoPendente != null && btTraducaoPendente == btTraducaoEmprestada;

  bool get canConfirmTranslation =>
      _btNaVez &&
      btTraducaoPendente != null &&
      !btTraducaoPendenteEmprestada &&
      btContaEscolhida == null;

  bool get canListenToThePendingStretch =>
      _btNaVez &&
      (btClipRodando ||
          btContaEscolhida != null ||
          btTrechoTocando ||
          btTrechoPausada ||
          btCortado ||
          btParteFronteira ||
          !btClipEnded);

  /// The stretch the finding points at, when the pointer names one the room told back.
  ///
  /// The server does not check the pointer against the stretches this tablet knows, so a
  /// stale name reaches the app and matches nothing. Every side that acts on the finding
  /// reads this: the screen drew the rule a second time, and the day the two copies
  /// disagreed the dead button was back.
  Trecho? get btFindingTrecho => trechoChamado(btFindingSegmentId);

  /// The stretch a pointer of the room's names, when this tablet holds one by that name.
  ///
  /// One copy of the rule for every pointer the room can send. The findings pointer had
  /// it inline, and the answer that names a stretch nobody told needs the same question
  /// answered the same way — a second reading of it is the second copy that put a dead
  /// button back on the screen the day the two disagreed.
  Trecho? trechoChamado(String? named) {
    if (named == null) return null;
    for (final trecho in btTrechos) {
      if (trecho.segmentId == named) {
        return trecho.to > trecho.from ? trecho : null;
      }
    }
    return null;
  }

  /// The rehearsal's own recordings, in order — never a correction's own take, which is a
  /// slice of one of these and not a part of the rehearsal in its own right.
  List<KeptTake> get partes => [
    for (final take in keptTakes)
      if (KeptScope.isParte(take.scopeId)) take,
  ];

  bool get canPlayTheRehearsal =>
      (partes.isNotEmpty || ensaio == EnsaioStatus.recorded) &&
      ensaio != EnsaioStatus.recording;

  /// Whether the last listening the clean verdict invites has anything to play.
  ///
  /// A session picked back up over a room that holds no rehearsal of its own carries the
  /// room's stretches and no file at all, and a lit player answering with silence has no
  /// way to explain itself in a room with no written word. It lives here rather than on
  /// the screen so the affordance and the verb it opens read the same fact; the verb keeps
  /// its own guard as well, because it is reachable from more than this one press.
  bool get canListenAtConferida =>
      btPhase == BtPhase.conferida && partes.isNotEmpty;

  SalaSessionState copyWith({
    bool? awaitingTheGuide,
    LeftEntry? leftEntry,
    bool clearLeftEntry = false,
    bool? endOfThePassage,
    RoomReach? reach,
    bool? panoramaSaid,
    String? sessionId,
    bool clearSession = false,
    Coverage? coverage,
    bool? contasEnfiadas,
    bool? peerCue,
    bool? noteMode,
    bool? handAck,
    bool? questionPending,
    List<HandReply>? replies,
    String? playingReplyId,
    bool clearPlayingReply = false,
    List<KeptTake>? keptTakes,
    SpokenLine? lastSpoken,
    bool clearLastSpoken = false,
    EnsaioStatus? ensaio,
    bool? micTaken,
    int? takes,
    BtPhase? btPhase,
    List<int>? btChunkFailures,
    List<Passagem>? naRoda,
    Set<String>? comecadas,
    Set<String>? feitas,
    bool clearRoda = false,
    int? aOferecer,
    List<Trecho>? btTrechos,
    String? btFindingSegmentId,
    bool clearFindingSegment = false,
    bool? btClipEnded,
    bool? btParteFronteira,
    List<int>? btFimDasPartesMs,
    int? btParteNoArMs,
    int? btOuvidoMs,
    Duration? btCursor,
    Duration? btCorte,
    bool? btOuvidoAlemDoCursor,
    int? btParte,
    String? btTraducaoPendente,
    bool clearTraducaoPendente = false,
    String? btTraducaoEmprestada,
    Trecho? btTrechoTraduzidoDeNovo,
    bool clearTrechoTraduzidoDeNovo = false,
    int? btContaEscolhida,
    bool clearContaEscolhida = false,
    int? btPass,
    int? unsentTakes,
    int? unsentChunks,
    Set<String>? unsentTakeScopes,
    Machine? machine,
    int? parteARegravar,
    bool clearParteARegravar = false,
  }) {
    return SalaSessionState(
      awaitingTheGuide: awaitingTheGuide ?? this.awaitingTheGuide,
      leftEntry: clearLeftEntry ? null : (leftEntry ?? this.leftEntry),
      endOfThePassage: endOfThePassage ?? this.endOfThePassage,
      reach: reach ?? this.reach,
      panoramaSaid: panoramaSaid ?? this.panoramaSaid,
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      coverage: coverage ?? this.coverage,
      contasEnfiadas: contasEnfiadas ?? this.contasEnfiadas,
      peerCue: peerCue ?? this.peerCue,
      noteMode: noteMode ?? this.noteMode,
      handAck: handAck ?? this.handAck,
      questionPending: questionPending ?? this.questionPending,
      replies: replies ?? this.replies,
      playingReplyId: clearPlayingReply
          ? null
          : (playingReplyId ?? this.playingReplyId),
      keptTakes: keptTakes ?? this.keptTakes,
      lastSpoken: clearLastSpoken ? null : (lastSpoken ?? this.lastSpoken),
      ensaio: ensaio ?? this.ensaio,
      micTaken: micTaken ?? this.micTaken,
      takes: takes ?? this.takes,
      btPhase: btPhase ?? this.btPhase,
      btChunkFailures: btChunkFailures ?? this.btChunkFailures,
      naRoda: clearRoda ? null : (naRoda ?? this.naRoda),
      comecadas: comecadas ?? this.comecadas,
      feitas: feitas ?? this.feitas,
      aOferecer: aOferecer ?? this.aOferecer,
      btTrechos: btTrechos ?? this.btTrechos,
      btFindingSegmentId: clearFindingSegment
          ? null
          : (btFindingSegmentId ?? this.btFindingSegmentId),
      btClipEnded: btClipEnded ?? this.btClipEnded,
      btParteFronteira: btParteFronteira ?? this.btParteFronteira,
      btFimDasPartesMs: btFimDasPartesMs ?? this.btFimDasPartesMs,
      btParteNoArMs: btParteNoArMs ?? this.btParteNoArMs,
      btOuvidoMs: btOuvidoMs ?? this.btOuvidoMs,
      btCursor: btCursor ?? this.btCursor,
      btCorte: btCorte ?? this.btCorte,
      btOuvidoAlemDoCursor: btOuvidoAlemDoCursor ?? this.btOuvidoAlemDoCursor,
      btParte: btParte ?? this.btParte,
      btTraducaoPendente: clearTraducaoPendente
          ? null
          : (btTraducaoPendente ?? this.btTraducaoPendente),
      btTraducaoEmprestada: clearTraducaoPendente
          ? null
          : (btTraducaoEmprestada ?? this.btTraducaoEmprestada),
      btTrechoTraduzidoDeNovo: clearTrechoTraduzidoDeNovo
          ? null
          : (btTrechoTraduzidoDeNovo ?? this.btTrechoTraduzidoDeNovo),
      btContaEscolhida: clearContaEscolhida
          ? null
          : (btContaEscolhida ?? this.btContaEscolhida),
      btPass: btPass ?? this.btPass,
      unsentTakes: unsentTakes ?? this.unsentTakes,
      unsentChunks: unsentChunks ?? this.unsentChunks,
      unsentTakeScopes: unsentTakeScopes ?? this.unsentTakeScopes,
      machine: machine ?? this.machine,
      parteARegravar: clearParteARegravar
          ? null
          : (parteARegravar ?? this.parteARegravar),
    );
  }
}
