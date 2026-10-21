import 'dart:math';

import 'bt_finding.dart';
import 'channel.dart';
import 'halt.dart';
import 'machine.dart';
import 'spoken_line.dart';
import 'room_reach.dart';
import 'session_snapshot.dart';
import 'coverage.dart';
import 'hand_reply.dart';
import 'kept_take.dart';
import 'left_entry.dart';
import 'moment.dart';
import 'passagem.dart';
import 'pausa.dart';
import 'scene_question.dart';
import 'scene_rehearsal.dart';
import 'station.dart';

enum SalaStage { panorama, escolha, conversa, ensaio, retro, fim, cena }

/// Where the scene rehearsal's screen is.
enum SceneStep { record, translate, placesUnknown, sent }

/// What the scene rehearsal's screen holds: its Step, the rehearsal as the room last
/// answered it, its take as a file on this tablet and the take's measured length, and
/// whether a call this screen made is in the air. On the record step it also holds the
/// scene the team picked, the scene of the rehearsal recorded again, and when the
/// question appeared and when the pick was made. On the translate step it holds
/// whether the team began listening, the pending pausa, her «não entendi», the frase being
/// translated again, and whether «terminei» reached the voice.
final class SceneScreen {
  final SceneStep step;
  final SceneRehearsalRecord? rehearsal;
  final String? take;
  final Duration? length;
  final bool waiting;
  final String? label;
  final SceneKeep? keep;
  final String? picked;
  final String? again;
  final DateTime? askedAt;
  final DateTime? pickedAt;
  final Duration? pausa;
  final bool listened;
  final bool notUnderstood;
  final SceneFrase? translatingAgain;
  final bool wentToTheVoice;

  const SceneScreen({
    this.step = SceneStep.record,
    this.rehearsal,
    this.take,
    this.length,
    this.waiting = false,
    this.label,
    this.keep,
    this.picked,
    this.again,
    this.askedAt,
    this.pickedAt,
    this.pausa,
    this.listened = false,
    this.notUnderstood = false,
    this.translatingAgain,
    this.wentToTheVoice = false,
  });

  SceneScreen copyWith({
    SceneRehearsalRecord? rehearsal,
    bool? waiting,
    String? label,
    bool clearLabel = false,
    SceneKeep? keep,
    bool clearKeep = false,
    String? picked,
    bool clearPicked = false,
    DateTime? askedAt,
    bool clearAskedAt = false,
    DateTime? pickedAt,
    bool clearPickedAt = false,
    Duration? pausa,
    bool clearPausa = false,
    bool? listened,
    bool? notUnderstood,
    SceneFrase? translatingAgain,
    bool clearTranslatingAgain = false,
    bool? wentToTheVoice,
  }) => SceneScreen(
    step: step,
    rehearsal: rehearsal ?? this.rehearsal,
    take: take,
    length: length,
    waiting: waiting ?? this.waiting,
    label: clearLabel ? null : (label ?? this.label),
    keep: clearKeep ? null : (keep ?? this.keep),
    picked: clearPicked ? null : (picked ?? this.picked),
    again: again,
    askedAt: clearAskedAt ? null : (askedAt ?? this.askedAt),
    pickedAt: clearPickedAt ? null : (pickedAt ?? this.pickedAt),
    pausa: clearPausa ? null : (pausa ?? this.pausa),
    listened: listened ?? this.listened,
    notUnderstood: notUnderstood ?? this.notUnderstood,
    translatingAgain: clearTranslatingAgain
        ? null
        : (translatingAgain ?? this.translatingAgain),
    wentToTheVoice: wentToTheVoice ?? this.wentToTheVoice,
  );

  SceneScreen get asWaiting => copyWith(waiting: true);

  /// The screen with nothing asked again: her «não entendi» gone and no frase being
  /// translated again.
  SceneScreen get nothingAskedAgain =>
      copyWith(notUnderstood: false, clearTranslatingAgain: true);

  /// The take as far as a frase may reach: this tablet's length, never past what the
  /// room measured.
  Duration? get takeEnd => switch ((length, rehearsal?.durationMs)) {
    (final Duration length, final int measured)
        when measured < length.inMilliseconds =>
      Duration(milliseconds: measured),
    (final length, _) => length,
  };

  /// Whether another frase fits between where the translation stopped and the take's
  /// end.
  bool get moreToTell => switch (takeEnd) {
    final end? =>
      pauseBounds(rehearsal?.frontier ?? Duration.zero, end) != null,
    null => false,
  };

  /// Whether «terminei» applies: an unsent rehearsal with a translated frase, being
  /// translated, with nothing in the air.
  bool get sendable =>
      (step == SceneStep.translate || step == SceneStep.placesUnknown) &&
      !waiting &&
      (rehearsal?.unsent ?? false) &&
      rehearsal!.translatedFrases > 0;
}

sealed class SceneKeep {
  const SceneKeep();
}

final class Keeping extends SceneKeep {
  const Keeping();
}

final class NotKept extends SceneKeep {
  final String? row;
  final String? take;
  final bool tooLarge;

  const NotKept({this.row, this.take, this.tooLarge = false});
}

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

const emVoltaDaFraseNova = Duration(milliseconds: 1500);

/// Where the telling-back is, step by step.
enum BtPhase { playing, capturing, thinking, findings, conferida }

enum BtRecomeco { armado, pronto }

enum BtAviso { recomecoFalhou, pausaSoNaUltima, pausaPassaDoFim, pausaNaoFica }

enum PassoDaRegravacao {
  ouvindo,
  pronta,
  gravando,
  revendo,
  enviando,
  longaDemais,
}

class RegravacaoDaFrase {
  final int frase;
  final PassoDaRegravacao passo;
  final String? path;

  const RegravacaoDaFrase(this.frase, this.passo, {this.path});
}

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
  final int? frase;

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
    this.frase,
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
  final String? pericope;
  final Coverage coverage;
  final Moment? moment;
  final List<KeptRetelling> keptRetellings;

  final bool peerCue;
  final bool noteMode;
  final List<HandReply> replies;
  final String? playingReplyId;
  final List<KeptTake> keptTakes;
  final SpokenLine? lastSpoken;
  final bool roomSaysItAgain;
  final EnsaioStatus ensaio;
  final bool micTaken;

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

  /// Passages of this book with work waiting in them, by pericope, for the resume lookup.
  final Set<String> comecadas;
  final List<Trecho> btTrechos;
  final List<BtFinding> btFindings;
  final bool btConferindo;
  final bool btVeredito;
  final CheckRefusal? btRecusa;
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
  final bool btPausaAjustavel;
  final bool btPausaSoNaUltima;
  final int btParte;
  final String? btTraducaoPendente;
  final String? btTraducaoEmprestada;
  final Trecho? btTrechoTraduzidoDeNovo;
  final int? btContaEscolhida;
  final int btPass;
  final BtRecomeco? btRecomeco;
  final BtAviso? btAviso;
  final bool btRecomecada;
  final RegravacaoDaFrase? btRegravacao;
  final String? btFraseQueAguarda;
  final int? btFraseGuardada;
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

  /// The Scene the open or pending recording of the Rehearsal is for, from 1; null while
  /// nothing is being recorded there.
  final int? cenaDaGravacao;

  final SceneScreen scene;

  /// This session's scene rehearsals, by number, as the room last answered them.
  final List<SceneRehearsalRecord> sceneRehearsals;

  /// The scene rehearsals whose room may hold a new translation the team has not seen,
  /// each with the frase it was translated over: it stands until a list read lands or a
  /// new translation of that frase is kept.
  final Map<String, String> sceneTranslationsUnseen;

  /// The loudness of a scene take, once it was read off the UI thread; null for a take
  /// with none to read.
  final ({String take, Envelope? envelope})? sceneLoudness;

  /// The passage's scenes as the screen knows them now: the scene rehearsal's open waits
  /// on a fresh ask.
  final SceneList scenes;

  /// The passage's scenes as the room last answered them for this session.
  final List<Scene>? scenesOfThePassage;

  /// The turn «terminei» last sent for a scene rehearsal and no reply has played for:
  /// the next «terminei» on that rehearsal goes under it again.
  final ({String rehearsalId, String turnId})? sceneTurn;

  /// Whether Scene row [scene] does not apply right now (ADR 0040: dimmed means it does
  /// not apply). True for every row but the one a finding sent the team back to record,
  /// while that record-again stands open and nothing has been recorded for it yet. Once
  /// that recording is pending — waiting for the green check — every row applies again,
  /// so this reads false throughout: the one rule the row and its gestures both read,
  /// instead of the row drawing dim where a gesture would still act.
  bool sceneRowIsDimmed(int scene) {
    final marked = _numberAt(parteARegravar);
    return ensaio == EnsaioStatus.idle && marked != null && marked != scene;
  }

  const SalaSessionState({
    this.awaitingTheGuide = false,
    this.leftEntry,
    this.endOfThePassage = false,
    this.reach = RoomReach.fine,
    this.panoramaSaid = false,
    this.pericope,
    this.coverage = Coverage.empty,
    this.moment,
    this.keptRetellings = const [],
    this.peerCue = false,
    this.noteMode = false,
    this.replies = const [],
    this.playingReplyId,
    this.keptTakes = const [],
    this.lastSpoken,
    this.roomSaysItAgain = false,
    this.ensaio = EnsaioStatus.idle,
    this.micTaken = false,
    this.btPhase = BtPhase.playing,
    this.btChunkFailures = const [],
    this.naRoda,
    this.comecadas = const {},
    this.btTrechos = const [],
    this.btFindings = const [],
    this.btConferindo = false,
    this.btVeredito = false,
    this.btRecusa,
    this.btFindingSegmentId,
    this.btClipEnded = false,
    this.btParteFronteira = false,
    this.btFimDasPartesMs = const [],
    this.btParteNoArMs = 0,
    this.btOuvidoMs = 0,
    this.btCursor = Duration.zero,
    this.btCorte = Duration.zero,
    this.btOuvidoAlemDoCursor = false,
    this.btPausaAjustavel = false,
    this.btPausaSoNaUltima = false,
    this.btParte = 0,
    this.btTraducaoPendente,
    this.btTraducaoEmprestada,
    this.btTrechoTraduzidoDeNovo,
    this.btContaEscolhida,
    this.btPass = 1,
    this.btRecomeco,
    this.btAviso,
    this.btRecomecada = false,
    this.btRegravacao,
    this.btFraseQueAguarda,
    this.btFraseGuardada,
    this.unsentTakes = 0,
    this.unsentChunks = 0,
    this.unsentTakeScopes = const {},
    this.machine = const Machine(),
    this.parteARegravar,
    this.cenaDaGravacao,
    this.scene = const SceneScreen(),
    this.sceneRehearsals = const [],
    this.sceneTranslationsUnseen = const {},
    this.sceneLoudness,
    this.scenes = const ScenesAwaited(),
    this.scenesOfThePassage,
    this.sceneTurn,
  });

  bool get colarOn => stage == SalaStage.conversa || stage == SalaStage.fim;

  bool get entriesOpen =>
      stage == SalaStage.escolha &&
      naRoda != null &&
      naRoda!.isNotEmpty &&
      !needsPerson &&
      voice == VoiceState.invite;

  bool isTheEntryLeft(Passagem entry, {required String language}) {
    final left = leftEntry;
    if (left == null || left.language != language) return false;
    return entry.isPanorama == left.panorama && entry.pericope == left.pericope;
  }

  String? get sessionId => machine.session;

  String? get panoramaSessionId => machine.panorama?.session;

  String? thePanoramaSessionOf(String book) {
    final held = machine.panorama?.id;
    final ofTheBook = (naRoda ?? const <Passagem>[]).any(
      (entry) =>
          entry.isPanorama && entry.pericope == held && entry.book == book,
    );
    return ofTheBook ? panoramaSessionId : null;
  }

  bool get rodaPorLer => stage == SalaStage.escolha && naRoda == null;

  /// The panorama's own spoke, when the wheel offers one, never counts as a passage the
  /// room can offer: a wheel holding nothing else is a book the room has nothing to say
  /// about, and the spoke to hear it again is not something to work on.
  bool get livroInteiroFeito =>
      stage == SalaStage.escolha &&
      naRoda != null &&
      naRoda!.every((passagem) => passagem.isPanorama);

  /// The advance disc lights: every Scene has its Part, with nothing recorded and waiting
  /// and no finding's mark standing.
  bool get ensaioDone =>
      ensaio == EnsaioStatus.idle &&
      parteARegravar == null &&
      everySceneHasItsPart;

  /// Whether every Scene has its Part. A passage the room answered with no scenes needs
  /// one part; a scene list still awaited or missing is never covered.
  bool get everySceneHasItsPart {
    final numbers = partNumbers;
    return switch (scenes) {
      ScenesHad(scenes: final had) when had.isNotEmpty => [
        for (var n = 1; n <= had.length; n++) n,
      ].every(numbers.contains),
      ScenesHad() => numbers.isNotEmpty,
      _ => false,
    };
  }

  /// Whether at least one Scene has its Part and another has none.
  bool get someScenesWaitForTheirPart {
    final count = scenes.scenes.length;
    final had = partNumbers.where((n) => n <= count).length;
    return had > 0 && had < count;
  }

  /// Whether a current Part was laid in from a Scene rehearsal.
  bool get joined => partes.any((take) => take.origin != null);

  Set<int> get partNumbers => {
    for (final take in partes) ?KeptScope.numberOf(take.scopeId),
  };

  /// Where in [partes] the part numbered [number] sits; null when there is none.
  int? partIndexOf(int number) {
    final index = partes.indexWhere(
      (take) => KeptScope.numberOf(take.scopeId) == number,
    );
    return index < 0 ? null : index;
  }

  /// The Scene the circle records: the part a finding sent the team back for, else the
  /// first Scene with no part, else none. A passage the room answered with no scenes
  /// takes the lowest number free. With no scene list answered it never goes past the
  /// parts already held: only a number missing below the highest, or the first part.
  int? get sceneForTheCircle {
    final marked = _numberAt(parteARegravar);
    if (marked != null) return marked;
    final numbers = partNumbers;
    final free = KeptScope.firstFree(numbers);
    return switch (scenes) {
      ScenesHad(scenes: final had) when had.isNotEmpty =>
        free <= had.length ? free : null,
      ScenesHad() => free,
      _ => free <= numbers.fold(1, max) ? free : null,
    };
  }

  /// One row per Scene, in passage order; with a passage the room answered with no
  /// scenes, one per Part plus one more. None while the list is awaited or missing.
  List<SceneRow> get sceneRows {
    final List<(int, String?)> numbered = switch (scenes) {
      ScenesHad(scenes: final had) when had.isNotEmpty => [
        for (final (index, scene) in had.indexed) (index + 1, scene.title),
      ],
      ScenesHad() => [
        for (final n in [
          ...partNumbers,
          KeptScope.firstFree(partNumbers),
        ]..sort())
          (n, null),
      ],
      _ => const [],
    };
    final playing = parteDoEnsaioTocando;
    final again = parteARegravar;
    return [
      for (final (number, title) in numbered)
        SceneRow(
          number: number,
          title: title,
          part: switch (partIndexOf(number)) {
            final index? => partes[index],
            null => null,
          },
          unsent: unsentTakeScopes.contains(KeptScope.parte(number)),
          recording: cenaDaGravacao == number && ensaio != EnsaioStatus.idle,
          dimmed: sceneRowIsDimmed(number),
          current: _numberAt(playing ?? again) == number,
        ),
    ];
  }

  /// The number of the part at [index] in [partes]; just past them, the scene of a
  /// recording waiting for the check.
  int? _numberAt(int? index) => switch (index) {
    final at? when at < partes.length => KeptScope.numberOf(partes[at].scopeId),
    final at? when at == partes.length && ensaio == EnsaioStatus.recorded =>
      cenaDaGravacao,
    _ => null,
  };

  bool get canHearAgain =>
      (lastSpoken != null || roomSaysItAgain) &&
      (voice == VoiceState.invite || voice == VoiceState.done) &&
      !needsPerson &&
      !noteMode &&
      stage != SalaStage.ensaio &&
      stage != SalaStage.retro &&
      stage != SalaStage.fim &&
      !sceneRehearsalIsOpen;

  /// Whether the scene rehearsal's screen stands over the Canvas.
  bool get sceneRehearsalIsOpen => station is SceneRehearsal;

  /// Whether «terminei» is in the air: the scene rehearsal waits on the voice.
  /// The loudness of the take on the scene screen, until it is read or for a take with
  /// none: a pausa then stays at the tap.
  Envelope? get sceneEnvelope => switch (sceneLoudness) {
    (take: final take, :final envelope) when take == scene.take => envelope,
    _ => null,
  };

  /// Whether the room may hold a new translation the team has not seen in the rehearsal
  /// on the scene screen.
  bool get sceneTranslationUnseen =>
      sceneTranslationsUnseen.containsKey(scene.rehearsal?.rehearsalId);

  bool get theSceneIsSending =>
      sceneRehearsalIsOpen && (awaitingTheGuide || machine.inFlight != null);

  bool get redMicrophoneIsShown =>
      (voice == VoiceState.invite || voice == VoiceState.done) &&
      !noteMode &&
      station is Canvas &&
      !needsPerson;

  bool get atTheTeamsIdleTurn =>
      (station is Canvas || station is Panorama) &&
      (voice == VoiceState.invite || voice == VoiceState.done) &&
      !needsPerson &&
      !_aLineOfTheRoomPlays &&
      stationSessionId != null;

  String? get stationSessionId => machine.stationSession;

  bool get anArmedKnotLapsed =>
      noteMode &&
      !atTheTeamsIdleTurn &&
      switch (channel) {
        Microphone(owner: MicOwner.question) => false,
        _ => true,
      };

  bool get _aLineOfTheRoomPlays => switch (channel) {
    GuideSpeaking(line: Line(kind: LineKind.reply)) => false,
    GuideSpeaking() => true,
    _ => false,
  };

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

  /// Whether a scene take is opening, recording or being kept.
  bool get sceneTakeUnderWay => channel is Microphone || scene.keep is Keeping;

  /// Whether the record step asks «Qual cena vocês vão ensaiar?» instead of showing the
  /// circle: nothing picked and no take under way.
  bool get sceneQuestionShown =>
      scene.step == SceneStep.record &&
      scenes.asks &&
      scenes.numberOf(scene.picked) == null &&
      !sceneTakeUnderWay;

  /// Whether the chip above the circle names the pick.
  bool get sceneChipShown =>
      scene.step == SceneStep.record &&
      scenes.asks &&
      scenes.numberOf(scene.picked) != null;

  /// Whether a tap on the chip brings the question back.
  bool get sceneChipLive =>
      scene.keep == null && !sceneTakeUnderWay && !scene.waiting;

  /// The scene the question highlights.
  String? get sceneHighlighted =>
      scenes.highlighted(sceneRehearsals, again: scene.again);

  bool get wordlessTelling => machine.wordlessTelling;

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

  Duration? get btTrechoDesde => switch (channel) {
    StretchPlaying(stretch: StretchSound(telling: false, :final from)) => from,
    _ => switch (_paused) {
      Paused(what: StretchSound(telling: false, :final from)) => from,
      _ => null,
    },
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

  /// The Choice offers the way back to the entry left, once the Wheel is read; the scene
  /// rehearsal's screen always offers the way back to the Conversation.
  bool get theWayBackIsOffered =>
      sceneRehearsalIsOpen ||
      (stage == SalaStage.escolha &&
          leftEntry != null &&
          naRoda != null &&
          !needsPerson);

  /// The way back answers the finger only while the Wheel is quiet, and from any Step of
  /// the scene rehearsal, its microphone open included.
  bool get theWayBackIsLive => sceneRehearsalIsOpen
      ? !theSceneIsSending
      : theWayBackIsOffered && voice == VoiceState.invite;

  /// The way out of a Station is hidden while it cannot apply: the voice is busy, or a
  /// microphone other than the raised-hand note's is open, or the person sign stands
  /// (ADR 0107).
  bool get wayOutIsHidden {
    if (needsPerson) return true;
    return switch (voice) {
      VoiceState.thinking || VoiceState.speaking => true,
      _ => switch (channel) {
        Microphone(:final owner) => owner != MicOwner.question,
        _ => false,
      },
    };
  }

  List<KeptRetelling> get partsToReplay {
    final kept = {for (final take in keptRetellings) take.scope: take};
    final parts = [
      for (var part = 1; part <= (moment?.parts ?? 0); part++) kept['S$part'],
    ];
    return parts.contains(null) ? const [] : [...parts.nonNulls];
  }

  bool get keptRetellingsAreAway => wayOutIsHidden || noteMode;

  bool get warning => halt is Warning;

  bool get wheelOffersNothing => naRoda?.isEmpty ?? false;

  bool get canResolveWithPerson => offline;

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
      canFinishBackTranslation &&
      btContadaInteira &&
      btContaEscolhida == null &&
      btFraseQueAguarda == null &&
      btRegravacao == null &&
      btTrechos.any((trecho) => trecho.contado);

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

  bool get thePauseStands =>
      _btNaVez &&
      btCortado &&
      btTraducaoPendente == null &&
      btTrechoTraduzidoDeNovo == null &&
      btContaEscolhida == null;

  bool get canAdjustThePause =>
      btPausaAjustavel &&
      btFraseQueAguarda == null &&
      (thePauseStands ||
          (_btNaVez &&
              btTrechoTraduzidoDeNovo != null &&
              btContaEscolhida == null));

  bool theLastPauseMoves(Trecho frase, {BtPhase? naFase}) =>
      frase.contado &&
      (naFase ?? btPhase) != BtPhase.conferida &&
      _aUltimaDaSuaParte(frase);

  bool anEarlierPauseStays(Trecho frase, {BtPhase? naFase}) =>
      frase.contado &&
      (naFase ?? btPhase) != BtPhase.conferida &&
      !_aUltimaDaSuaParte(frase);

  bool _aUltimaDaSuaParte(Trecho frase) {
    Trecho? ultima;
    for (final trecho in btTrechos) {
      if (trecho.takeId != frase.takeId) continue;
      if (ultima == null || trecho.to >= ultima.to) ultima = trecho;
    }
    return ultima?.segmentId == frase.segmentId;
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
      !wordlessTelling &&
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
  /// slice of one of these and not a part of the rehearsal in its own right. The whole
  /// rehearsal an app before 19 August sent is the rehearsal only while no scene has its
  /// part; from the first one on it is set aside, kept but no longer played or told.
  List<KeptTake> get partes {
    final numbered = [
      for (final take in keptTakes)
        if (KeptScope.isParte(take.scopeId)) take,
    ]..sort((a, b) => _byNumber(a).compareTo(_byNumber(b)));
    if (numbered.isNotEmpty) return numbered;
    return [
      for (final take in keptTakes)
        if (take.scopeId == KeptScope.whole) take,
    ];
  }

  /// The recordings of a whole rehearsal set aside behind the scenes' own parts.
  Set<String> get wholeSetAside => {
    if (keptTakes.any((take) => KeptScope.isParte(take.scopeId)))
      for (final take in keptTakes)
        if (take.scopeId == KeptScope.whole) ?take.takeId,
  };

  static int _byNumber(KeptTake take) => KeptScope.numberOf(take.scopeId) ?? 0;

  bool get canPlayTheRehearsal =>
      (partes.isNotEmpty || ensaio == EnsaioStatus.recorded) &&
      ensaio != EnsaioStatus.recording;

  Trecho? get btFraseTraduzidaDeNovo => switch (btTrechoTraduzidoDeNovo) {
    final Trecho trecho
        when trecho.contado &&
            (btFraseQueAguarda == null ||
                trecho.segmentId != btFraseQueAguarda) =>
      trecho,
    _ => null,
  };

  bool fraseRegravavel(Trecho trecho) =>
      trecho.frase != null &&
      btFraseTraduzidaDeNovo == null &&
      btRegravacao?.passo != PassoDaRegravacao.enviando &&
      (btFraseGuardada == null || btFraseGuardada == trecho.frase) &&
      (btFraseQueAguarda == null || btFraseQueAguarda == trecho.segmentId) &&
      !needsPerson &&
      !offline &&
      trecho.parte >= 0 &&
      trecho.parte < partes.length &&
      partes[trecho.parte].path.endsWith('.wav');

  /// Whether the last listening the clean verdict invites has anything to play.
  ///
  /// A session picked back up over a room that holds no rehearsal of its own carries the
  /// room's stretches and no file at all, and a lit player answering with silence has no
  /// way to explain itself in a room with no written word. It lives here rather than on
  /// the screen so the affordance and the verb it opens read the same fact; the verb keeps
  /// its own guard as well, because it is reachable from more than this one press.
  bool get canListenAtConferida =>
      btPhase == BtPhase.conferida && partes.isNotEmpty;

  bool get canRetellAFrase =>
      stage == SalaStage.retro &&
      partes.isNotEmpty &&
      !needsPerson &&
      !offline &&
      btRegravacao == null &&
      btFraseQueAguarda == null &&
      (btPhase == BtPhase.findings ||
          btPhase == BtPhase.conferida ||
          (btPhase == BtPhase.playing &&
              (btVeredito || btFindings.isNotEmpty)));

  bool get canHearAFrase =>
      stage == SalaStage.retro &&
      partes.isNotEmpty &&
      !needsPerson &&
      !offline &&
      btRegravacao == null &&
      (btPhase == BtPhase.playing ||
          btPhase == BtPhase.findings ||
          btPhase == BtPhase.conferida);

  SalaSessionState copyWith({
    bool? awaitingTheGuide,
    LeftEntry? leftEntry,
    bool clearLeftEntry = false,
    bool? endOfThePassage,
    RoomReach? reach,
    bool? panoramaSaid,
    String? pericope,
    Coverage? coverage,
    Moment? moment,
    bool clearMoment = false,
    List<KeptRetelling>? keptRetellings,
    bool? peerCue,
    bool? noteMode,
    List<HandReply>? replies,
    String? playingReplyId,
    bool clearPlayingReply = false,
    List<KeptTake>? keptTakes,
    SpokenLine? lastSpoken,
    bool clearLastSpoken = false,
    bool? roomSaysItAgain,
    EnsaioStatus? ensaio,
    bool? micTaken,
    BtPhase? btPhase,
    List<int>? btChunkFailures,
    List<Passagem>? naRoda,
    Set<String>? comecadas,
    bool clearRoda = false,
    List<Trecho>? btTrechos,
    List<BtFinding>? btFindings,
    bool? btConferindo,
    bool? btVeredito,
    CheckRefusal? btRecusa,
    bool clearBtRecusa = false,
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
    bool? btPausaAjustavel,
    bool? btPausaSoNaUltima,
    int? btParte,
    String? btTraducaoPendente,
    bool clearTraducaoPendente = false,
    String? btTraducaoEmprestada,
    Trecho? btTrechoTraduzidoDeNovo,
    bool clearTrechoTraduzidoDeNovo = false,
    int? btContaEscolhida,
    bool clearContaEscolhida = false,
    int? btPass,
    BtRecomeco? btRecomeco,
    bool clearRecomeco = false,
    BtAviso? btAviso,
    bool? btRecomecada,
    bool clearAviso = false,
    RegravacaoDaFrase? btRegravacao,
    bool clearBtRegravacao = false,
    String? btFraseQueAguarda,
    bool clearBtFraseQueAguarda = false,
    int? btFraseGuardada,
    bool clearBtFraseGuardada = false,
    int? unsentTakes,
    int? unsentChunks,
    Set<String>? unsentTakeScopes,
    Machine? machine,
    int? parteARegravar,
    bool clearParteARegravar = false,
    int? cenaDaGravacao,
    bool clearCenaDaGravacao = false,
    SceneScreen? scene,
    List<SceneRehearsalRecord>? sceneRehearsals,
    Map<String, String>? sceneTranslationsUnseen,
    ({String take, Envelope? envelope})? sceneLoudness,
    SceneList? scenes,
    List<Scene>? scenesOfThePassage,
    ({String rehearsalId, String turnId})? sceneTurn,
    bool clearSceneTurn = false,
  }) {
    return SalaSessionState(
      awaitingTheGuide: awaitingTheGuide ?? this.awaitingTheGuide,
      leftEntry: clearLeftEntry ? null : (leftEntry ?? this.leftEntry),
      endOfThePassage: endOfThePassage ?? this.endOfThePassage,
      reach: reach ?? this.reach,
      panoramaSaid: panoramaSaid ?? this.panoramaSaid,
      pericope: pericope ?? this.pericope,
      coverage: coverage ?? this.coverage,
      moment: clearMoment ? null : (moment ?? this.moment),
      keptRetellings: keptRetellings ?? this.keptRetellings,
      peerCue: peerCue ?? this.peerCue,
      noteMode: noteMode ?? this.noteMode,
      replies: replies ?? this.replies,
      playingReplyId: clearPlayingReply
          ? null
          : (playingReplyId ?? this.playingReplyId),
      keptTakes: keptTakes ?? this.keptTakes,
      lastSpoken: clearLastSpoken ? null : (lastSpoken ?? this.lastSpoken),
      roomSaysItAgain: roomSaysItAgain ?? this.roomSaysItAgain,
      ensaio: ensaio ?? this.ensaio,
      micTaken: micTaken ?? this.micTaken,
      btPhase: btPhase ?? this.btPhase,
      btChunkFailures: btChunkFailures ?? this.btChunkFailures,
      naRoda: clearRoda ? null : (naRoda ?? this.naRoda),
      comecadas: comecadas ?? this.comecadas,
      btTrechos: btTrechos ?? this.btTrechos,
      btFindings: btFindings ?? this.btFindings,
      btConferindo: btConferindo ?? this.btConferindo,
      btVeredito: btVeredito ?? this.btVeredito,
      btRecusa: clearBtRecusa ? null : (btRecusa ?? this.btRecusa),
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
      btPausaAjustavel: btPausaAjustavel ?? this.btPausaAjustavel,
      btPausaSoNaUltima: btPausaSoNaUltima ?? this.btPausaSoNaUltima,
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
      btRecomeco: clearRecomeco ? null : (btRecomeco ?? this.btRecomeco),
      btAviso: clearAviso ? null : (btAviso ?? this.btAviso),
      btRecomecada: btRecomecada ?? this.btRecomecada,
      btRegravacao: clearBtRegravacao
          ? null
          : (btRegravacao ?? this.btRegravacao),
      btFraseQueAguarda: clearBtFraseQueAguarda
          ? null
          : (btFraseQueAguarda ?? this.btFraseQueAguarda),
      btFraseGuardada: clearBtFraseGuardada
          ? null
          : (btFraseGuardada ?? this.btFraseGuardada),
      unsentTakes: unsentTakes ?? this.unsentTakes,
      unsentChunks: unsentChunks ?? this.unsentChunks,
      unsentTakeScopes: unsentTakeScopes ?? this.unsentTakeScopes,
      machine: machine ?? this.machine,
      parteARegravar: clearParteARegravar
          ? null
          : (parteARegravar ?? this.parteARegravar),
      cenaDaGravacao: clearCenaDaGravacao
          ? null
          : (cenaDaGravacao ?? this.cenaDaGravacao),
      scene: scene ?? this.scene,
      sceneRehearsals: sceneRehearsals ?? this.sceneRehearsals,
      sceneTranslationsUnseen:
          sceneTranslationsUnseen ?? this.sceneTranslationsUnseen,
      sceneLoudness: sceneLoudness ?? this.sceneLoudness,
      scenes: scenes ?? this.scenes,
      scenesOfThePassage: scenesOfThePassage ?? this.scenesOfThePassage,
      sceneTurn: clearSceneTurn ? null : (sceneTurn ?? this.sceneTurn),
    );
  }
}

/// One Scene row of the Rehearsal.
class SceneRow {
  final int number;

  /// The Scene's title as the scenes door answered it; null for a passage with no scenes.
  final String? title;
  final KeptTake? part;
  final bool unsent;
  final bool recording;
  final bool dimmed;

  /// The part in the air, playing or held, or else the part a finding sent the team back
  /// to record again.
  final bool current;

  const SceneRow({
    required this.number,
    required this.title,
    required this.part,
    required this.unsent,
    required this.recording,
    required this.dimmed,
    required this.current,
  });
}
