import 'bt_finding.dart';
import 'channel.dart';
import 'halt.dart';
import 'machine.dart';
import 'spoken_line.dart';
import 'session_snapshot.dart';
import 'coverage.dart';
import 'ensaio_final_plan.dart';
import 'grain.dart';
import 'hand_reply.dart';
import 'kept_take.dart';
import 'left_entry.dart';
import 'moment.dart';
import 'passagem.dart';
import 'pausa.dart';
import 'scene_question.dart';
import 'scene_rehearsal.dart';
import 'station.dart';

enum SalaStage { panorama, escolha, conversa, ensaio, retro, cena, checagem }

enum OrangeDotLook { gone, faint, bright }

/// Where the scene rehearsal's screen is.
enum SceneStep { record, translate, placesUnknown, sent }

enum SceneHeard { partly, toTheEnd }

/// Her line beside the scene rehearsal's controls: «recomeçar a tradução» answered or
/// failed, a moved pause the room refused, one per refusal code, or a «terminei» that
/// could not be sent, or that the room lists as already sent.
enum SceneLine {
  restarted,
  restartFailed,
  pauseOnlyOnTheLast,
  pausePastTheEnd,
  pauseCannotStandThere,
  diskFailed,
  notSent,
  alreadySent,
}

/// Her listener's steps on the Checagem externa.
enum ListenerStep { idle, playing, retell, done }

/// Her failure words the Checagem externa shows under its controls.
enum ListenerLine { openFailed, clipFailed }

/// What the Checagem externa's screen holds: the takes of the approved version's parts,
/// the listener's number and Step, whether the passage stalled, whether a call this
/// screen made is in the air, the failure words shown, when the retelling began, whether
/// X-open was said, which lets the passage play, whether X-retell was said, which opens
/// the circle, and how the listener ended and whether the room acknowledged it.
final class ExternalCheckScreen {
  final List<String> takes;
  final int? listener;
  final ListenerStep step;
  final bool stalled;
  final bool sending;
  final ListenerLine? line;
  final DateTime? recordingSince;
  final bool openSaid;
  final bool retellSaid;
  final bool? completed;
  final bool finishAcknowledged;

  const ExternalCheckScreen({
    this.takes = const [],
    this.listener,
    this.step = ListenerStep.idle,
    this.stalled = false,
    this.sending = false,
    this.line,
    this.recordingSince,
    this.openSaid = false,
    this.retellSaid = false,
    this.completed,
    this.finishAcknowledged = false,
  });

  ExternalCheckScreen copyWith({
    int? listener,
    ListenerStep? step,
    bool? stalled,
    bool? sending,
    ListenerLine? line,
    bool clearLine = false,
    DateTime? recordingSince,
    bool clearRecordingSince = false,
    bool? openSaid,
    bool? retellSaid,
    bool? completed,
    bool? finishAcknowledged,
  }) => ExternalCheckScreen(
    takes: takes,
    listener: listener ?? this.listener,
    step: step ?? this.step,
    stalled: stalled ?? this.stalled,
    sending: sending ?? this.sending,
    line: clearLine ? null : (line ?? this.line),
    recordingSince: clearRecordingSince
        ? null
        : (recordingSince ?? this.recordingSince),
    openSaid: openSaid ?? this.openSaid,
    retellSaid: retellSaid ?? this.retellSaid,
    completed: completed ?? this.completed,
    finishAcknowledged: finishAcknowledged ?? this.finishAcknowledged,
  );
}

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
  final SceneHeard? heard;

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
    this.heard,
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
    SceneHeard? heard,
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
    heard: heard ?? this.heard,
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
  final SendFailure why;

  const NotKept({this.row, this.take, this.why = SendFailure.failed});
}

enum VoiceState { invite, listening, thinking, speaking, done }

enum EnsaioStatus { idle, recording, recorded }

/// «Ouvir tudo», the recording home's listen-only screen: off, playing the parts in order,
/// or played to its end.
enum OuvirTudo { fora, ouvindo, acabou }

/// How far short of a part's end the told ground may stop and still count as its end.
///
/// The last cut of a part is made where the clip stopped, and a position read as a
/// clip finishes can sit a little before the length measured without playing it. This
/// end's choice: the number is the slack the room's gate was read to allow itself when
/// it checks what was heard, not a contract the room promises.
const folgaDoFimDaParte = Duration(milliseconds: 750);

const emVoltaDaFraseNova = Duration(milliseconds: 1500);

/// Where the telling-back is, step by step.
enum BtPhase { playing, capturing, thinking, conferida }

enum BtRecomeco { armado, pronto }

/// The one control armed on the screen, and whether its second tap counts yet.
class ArmedTap {
  final String control;
  final BtRecomeco phase;

  const ArmedTap(this.control, this.phase);
}

enum BtAviso {
  recomecoFalhou,
  pausaSoNaUltima,
  pausaPassaDoFim,
  pausaNaoFica,
  checagemFalhou,
  checagemNaoAbre,
  tocarFalhou,
}

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
  final bool reabre;

  const RegravacaoDaFrase(
    this.frase,
    this.passo, {
    this.path,
    this.reabre = false,
  });

  RegravacaoDaFrase em(PassoDaRegravacao passo, {String? path}) =>
      RegravacaoDaFrase(frase, passo, path: path, reabre: reabre);
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
  /// The answer to telling a stretch back names it, so a stretch told this session has
  /// its name as soon as the room answers. An answer the room kept from before it named
  /// its stretches carries none, and that stretch stays nameless until the room's reading
  /// of the session is read back. A nameless one matches no pointer, which is the answer
  /// a pointer naming nothing should get anyway.
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
  final String? bridgeTakeId;

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
    this.bridgeTakeId,
  });

  Trecho naParte(int parte) => Trecho(
    segmentId: segmentId,
    takeId: takeId,
    retroPath: retroPath,
    parte: parte,
    from: from,
    to: to,
    contado: contado,
    lugarFrom: lugarFrom,
    lugarTo: lugarTo,
    frase: frase,
    bridgeTakeId: bridgeTakeId,
  );
}

class PassageLeft {
  final SalaSessionState canvas;
  final String session;
  final String book;
  final String? pericope;
  final String language;
  final ({int version, int number})? listener;

  const PassageLeft({
    required this.canvas,
    required this.session,
    required this.book,
    this.pericope,
    required this.language,
    this.listener,
  });
}

class SalaSessionState {
  final bool awaitingTheGuide;

  /// Set when the room enters the Choice, cleared when it leaves it. The station the room
  /// stands on before the launch settles is a Menu too, and it is not an arrival.
  final bool arrivedAtTheChoice;

  /// The entry the team last left by the way out, for the Choice to offer the way back.
  final LeftEntry? leftEntry;
  final Passagem? openingEntry;
  final PassageLeft? passageLeft;
  final bool endOfThePassage;

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
  final List<Trecho> btTrechosRegravados;
  final List<String> btNaoOuvidas;
  final int? btParteQueTocou;
  final List<BtFinding> btFindings;
  final bool btConferindo;
  final bool btVeredito;
  final CheckRefusal? btRecusa;
  final List<int> btCenasSemTraducao;
  final String? btFindingSegmentId;

  final bool btClipEnded;
  final bool? btOuvidaInteira;
  final bool btRestoPorOuvir;
  final bool btParteFronteira;

  final List<int> btFimDasPartesMs;
  final int btParteNoArMs;
  final int btOuvidoMs;
  final Duration btCursor;
  final Duration btCorte;

  /// Whether the head has passed [btCursor] since it was last set — the one fact the
  /// capture and the circle's label both read to ask whether anything has
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
  final ArmedTap? armedTap;
  final BtAviso? btAviso;
  final bool btRecomecada;
  final RegravacaoDaFrase? btRegravacao;
  final String? btFraseQueAguarda;
  final String? btFraseGuardada;
  final String? btFraseDevida;

  /// The approval the newest Session read says the draft stands under.
  final ApprovedDraft? btRascunhoAprovado;

  /// The First listen: on a Joined recording, every part heard through before anything
  /// can be told back.
  final bool btSoOuvir;

  /// The Generation an approval is in the air in: from the press until the Saved screen or
  /// the end of the refusal's handling. A newer Generation is not held by it.
  final int? btAprovando;

  /// The Generation an open of the Checagem externa is in the air in: from the tap until
  /// the room answers. A newer Generation is not held by it.
  final int? btAbrindoAChecagem;

  /// The version this press minted, while her approved sentence and P3 stand on the
  /// Back-translation.
  final int? btAprovadoAgora;

  /// The version the Saved screen shows; the Saved screen stands while it is set.
  final int? ensaioSalvo;

  final OuvirTudo ouvirTudo;

  /// The room's own read of whether the passage is checked, kept for the recording home.
  final bool btChecked;
  final int unsentTakes;
  final int unsentChunks;
  final Map<int, UnsentPart> unsentParts;
  final Set<int> heldScenes;

  final Machine machine;
  final DateTime? recorderStartedAt;

  /// The Scene the open or pending recording of the Rehearsal is for, from 1; null while
  /// nothing is being recorded there.
  final int? cenaDaGravacao;

  final SceneScreen scene;

  /// The Checagem externa's listener as the screen shows it; set on arrival, never stored.
  final ExternalCheckScreen externalCheck;

  /// This session's scene rehearsals, by number, as the room last answered them.
  final List<SceneRehearsalRecord> sceneRehearsals;

  /// The scene rehearsals whose room may hold a new translation the team has not seen,
  /// each with the frase it was translated over: it stands until a list read lands or a
  /// new translation of that frase is kept.
  final Map<String, String> sceneTranslationsUnseen;

  final Set<String> sceneFrasesHeld;

  /// The loudness of a scene take, once it was read off the UI thread; null for a take
  /// with none to read.
  final List<({String take, Envelope? envelope})> sceneLoudness;

  final Map<String, ({Duration length, Envelope? envelope})> partLoudness;

  /// The passage's scenes as the screen knows them now: the scene rehearsal's open waits
  /// on a fresh ask.
  final SceneList scenes;

  /// The passage's scenes as the room last answered them for this session.
  final List<Scene>? scenesOfThePassage;

  /// The turn «terminei» last sent for a scene rehearsal and no reply has played for:
  /// the next «terminei» on that rehearsal goes under it again.
  final ({String rehearsalId, String turnId})? sceneTurn;
  final Duration? sceneStoppedAt;

  /// «recomeçar a tradução» on the scene rehearsal armed by its first tap, kept beside the
  /// screen so its timers never replace the screen a call waits on.
  final BtRecomeco? sceneRestart;

  final SceneLine? sceneLine;

  /// What the Ensaio Final plan was last drawn from.
  final EnsaioFinalPlan? ensaioFinalPlan;

  /// The rehearsal the team chose for a scene of the plan, by scene, for one visit of the
  /// plan.
  final Map<String, String> planChoices;

  /// The play a button of the plan last asked for, while it is fetched or sounds.
  final PlanListen? planListening;

  /// How each scene's join ended on this visit of the plan, by part number, and the
  /// scene being joined.
  final Map<int, JoinRow> joinRows;
  final int? joining;

  /// The scene whose Rehearsal sheet is open over the plan, for one visit of the plan.
  final String? planSheet;

  /// Whether the card's Scene label is in the air, or its answer has not yet woken the
  /// next rehearsal on the card for a tap.
  final bool labelling;

  /// Whether the card says her line for a label the room could not keep.
  final bool labelLine;

  /// The scene whose Rehearsal sheet is open over the recording home.
  final String? homeSheet;
  final String? swapping;
  final ({String rehearsalId, bool cannotEnter})? swapLine;
  final bool hearNewScene;

  /// Whether the last plan read found the passage's rehearsals only in the other
  /// language's session.
  final bool rehearsalsElsewhere;

  /// The part numbers whose current part in the room's listing was laid in from a Scene
  /// rehearsal.
  final Set<int> theRoomJoinedParts;
  final List<int> toBringBack;
  final int? bringingBack;
  final ({int cena, bool cannotEnter})? bringBackFailed;

  /// The takes of a whole rehearsal set aside behind the scenes' parts that only the room
  /// holds.
  final Set<String> wholeHeldByTheRoom;

  /// The grain the room says is in force for this session; null until a listing or a
  /// switch said it.
  final Grain? grainInForce;

  /// Whether a switch of the grain is in the air.
  final bool grainSwitching;

  const SalaSessionState({
    this.awaitingTheGuide = false,
    this.arrivedAtTheChoice = false,
    this.leftEntry,
    this.openingEntry,
    this.passageLeft,
    this.endOfThePassage = false,
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
    this.btTrechosRegravados = const [],
    this.btNaoOuvidas = const [],
    this.btParteQueTocou,
    this.btFindings = const [],
    this.btConferindo = false,
    this.btVeredito = false,
    this.btRecusa,
    this.btCenasSemTraducao = const [],
    this.btFindingSegmentId,
    this.btClipEnded = false,
    this.btOuvidaInteira,
    this.btRestoPorOuvir = false,
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
    this.armedTap,
    this.btAviso,
    this.btRecomecada = false,
    this.btRegravacao,
    this.btFraseQueAguarda,
    this.btFraseGuardada,
    this.btFraseDevida,
    this.btRascunhoAprovado,
    this.btSoOuvir = false,
    this.btAprovando,
    this.btAbrindoAChecagem,
    this.btAprovadoAgora,
    this.ensaioSalvo,
    this.ouvirTudo = OuvirTudo.fora,
    this.btChecked = false,
    this.unsentTakes = 0,
    this.unsentChunks = 0,
    this.unsentParts = const {},
    this.heldScenes = const {},
    this.machine = const Machine(),
    this.recorderStartedAt,
    this.cenaDaGravacao,
    this.scene = const SceneScreen(),
    this.externalCheck = const ExternalCheckScreen(),
    this.sceneRehearsals = const [],
    this.sceneTranslationsUnseen = const {},
    this.sceneFrasesHeld = const {},
    this.sceneLoudness = const [],
    this.partLoudness = const {},
    this.scenes = const ScenesAwaited(),
    this.scenesOfThePassage,
    this.sceneTurn,
    this.sceneStoppedAt,
    this.sceneRestart,
    this.sceneLine,
    this.ensaioFinalPlan,
    this.planChoices = const {},
    this.planListening,
    this.joinRows = const {},
    this.joining,
    this.planSheet,
    this.labelling = false,
    this.labelLine = false,
    this.homeSheet,
    this.swapping,
    this.swapLine,
    this.hearNewScene = false,
    this.rehearsalsElsewhere = false,
    this.theRoomJoinedParts = const {},
    this.toBringBack = const [],
    this.bringingBack,
    this.bringBackFailed,
    this.wholeHeldByTheRoom = const {},
    this.grainInForce,
    this.grainSwitching = false,
  });

  bool get colarOn => stage == SalaStage.conversa;

  bool get entriesOpen =>
      stage == SalaStage.escolha &&
      naRoda != null &&
      naRoda!.isNotEmpty &&
      !needsPerson &&
      voice == VoiceState.invite;

  bool isTheEntryLeft(Passagem entry) {
    final left = leftEntry;
    if (left == null) return false;
    return entry.isPanorama == left.panorama &&
        entry.pericope == left.pericope &&
        (left.panorama || entry.book == left.book);
  }

  String? get sessionId => machine.session;

  TakeInTheAir? _theTakeInTheAirOf(String kind) => switch (machine.inTheAir) {
    final take? when take.keep.session == sessionId && take.keep.kind == kind =>
      take,
    _ => null,
  };

  TakeInTheAir? get sceneTakeInTheAir => _theTakeInTheAirOf(sceneTakeKind);

  UnsentPart? _unsentByTheNewestKeptTake(int number) =>
      switch (machine.newestKeptFact(sessionId, scopeOfRow(number))) {
        PartFact.pending => const UnsentPart(fromAnEarlierVisit: false),
        PartFact.stranded => const UnsentPart(
          fromAnEarlierVisit: false,
          failure: SendFailure.gone,
        ),
        PartFact.sent || null => null,
      };

  TakeInTheAir? partInTheAir(int number) =>
      switch (_theTakeInTheAirOf(partTakeKind)) {
        final take? when take.keep.scope == scopeOfRow(number) => take,
        _ => null,
      };

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

  /// The advance disc lights: every Scene has its Part and none waits in the Outbox,
  /// with nothing recorded and waiting.
  bool get ensaioDone =>
      ensaio == EnsaioStatus.idle && everySceneHasItsPart && everyPartIsSent;

  bool get everyPartIsSent => !partes.any(_waitsToGoUp);

  bool _waitsToGoUp(KeptTake take) =>
      take.takeId == null && unsentParts.containsKey(rowOf(take.scopeId));

  /// Whether every Scene has its Part. A passage the room answered with no scenes needs
  /// one part; a scene list still awaited or missing is never covered.
  bool get everySceneHasItsPart {
    if (recordsTheWhole) return partes.isNotEmpty;
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
    final had = {
      for (final take in partes)
        if (!_waitsToGoUp(take)) ?KeptScope.numberOf(take.scopeId),
    }.where((n) => n <= count).length;
    return had > 0 && had < count;
  }

  /// Whether a current Part was laid in from a Scene rehearsal.
  bool get joined => partes.any((take) => take.origin != null);

  bool get offersASentence => joined || partes.any((take) => take.isWav);

  /// Whether a current Part came from a join, part by part: the tablet's take where it
  /// holds one, the room's listing otherwise.
  bool get aPartWasJoined =>
      joined ||
      theRoomJoinedParts.any((number) => !partNumbers.contains(number));

  /// How the orange dot stands on the Conversation: gone while the way out is hidden or a
  /// line of the room sounds; bright from the send-off; faint otherwise.
  OrangeDotLook get orangeDotLook {
    if (wayOutIsHidden || _aLineOfTheRoomPlays) {
      return OrangeDotLook.gone;
    }
    if (endOfThePassage || moment?.at == MomentAt.ensaioFinal) {
      return OrangeDotLook.bright;
    }
    return OrangeDotLook.faint;
  }

  Set<int> get partNumbers => {
    for (final take in partes) ?KeptScope.numberOf(take.scopeId),
  };

  /// The grain in force: the room's, else read off the parts as the room reads it — a
  /// numbered part is scene by scene, only the whole is the whole passage.
  Grain? get grain {
    if (grainInForce case final known?) return known;
    if (partes.isEmpty) return null;
    return partNumbers.isEmpty ? Grain.whole : Grain.scene;
  }

  bool get recordsTheWhole => grain == Grain.whole;

  /// The row a recording of [scopeId] stands on: the whole is the one row while the
  /// passage is recorded whole, row 0 while the room names no grain, and no row otherwise.
  int? rowOf(String scopeId) => recordsTheWhole
      ? (scopeId == KeptScope.whole ? 1 : null)
      : scopeId == KeptScope.whole && grainInForce == null
      ? 0
      : KeptScope.numberOf(scopeId);

  /// Whether the grain in force is known and gives a recording of [scopeId] no row.
  bool showsNoRow(String scopeId) =>
      grainInForce != null && rowOf(scopeId) == null;

  /// The scope a recording on row [number] is kept under: the whole while the passage is
  /// recorded whole and on row 0, where the whole stands while no grain is in force; the
  /// part numbered [number] otherwise.
  String scopeOfRow(int number) => recordsTheWhole || number == 0
      ? KeptScope.whole
      : KeptScope.parte(number);

  /// «gravar a passagem inteira de uma vez» takes the Armed tap only when it would leave
  /// something behind: an approved draft, or a part that came from a join.
  bool get wholeSwitchArms => overAnApprovedDraft || aPartWasJoined;

  /// «Ensaio Final: juntar os ensaios das cenas»: only over an empty whole recording, with
  /// no take on the tablet, in the room or waiting in the Outbox, and only while a plan
  /// read stands with a scene still to join: a usable rehearsal chosen for a scene with
  /// no part and no take held on the tablet. Her `backToJoinOffered` asks the same of the
  /// join queue (ensaioFinal.ts:252-253).
  bool get offersTheWayBackToTheJoin =>
      recordsTheWhole &&
      partes.isEmpty &&
      ensaio == EnsaioStatus.idle &&
      !unsentParts.containsKey(1) &&
      switch ((ensaioFinalPlan, sessionId)) {
        (final PlanRead read, final String sessionId) => stillToJoin(
          read,
          sessionId,
          planChoices,
          held: heldScenes,
        ),
        _ => false,
      };

  /// Where in [partes] the part numbered [number] sits; null when there is none.
  int? partIndexOf(int number) {
    final index = partes.indexWhere((take) => rowOf(take.scopeId) == number);
    return index < 0 ? null : index;
  }

  bool get aTakeFromAnEarlierVisitWaits =>
      sceneRows.any((row) => row.unsent?.fromAnEarlierVisit ?? false);

  /// The one row of the whole while the passage is recorded whole. Otherwise one row per
  /// Scene, in passage order, then one per part beyond the last scene with a take still to
  /// send, in the air, being kept or kept this visit; with a passage the room answered
  /// with no scenes, one per Part plus one more. None while the list is awaited or
  /// missing.
  List<SceneRow> get sceneRows {
    final List<(int, String?, bool)> numbered = switch (scenes) {
      _ when recordsTheWhole => const [(1, null, false)],
      ScenesHad(scenes: final had) when had.isNotEmpty => [
        for (final (index, scene) in had.indexed)
          (index + 1, scene.title, false),
        for (final number in _partsWithASendBeyond(had.length))
          (number, null, true),
      ],
      ScenesHad() => [
        for (final n in [
          ...partNumbers,
          KeptScope.firstFree(partNumbers),
        ]..sort())
          (n, null, false),
      ],
      _ => const [],
    };
    final playing = parteDoEnsaioTocando;
    final saved = machine.savedParts(sessionId);
    return [
      for (final (number, title, beyondTheScenes) in numbered)
        SceneRow(
          number: number,
          title: title,
          beyondTheScenes: beyondTheScenes,
          part: switch (partIndexOf(number)) {
            final index? => partes[index],
            null => null,
          },
          unsent: machine.beingKept(sessionId, scopeOfRow(number))
              ? const UnsentPart(fromAnEarlierVisit: false)
              : unsentParts[number] ?? _unsentByTheNewestKeptTake(number),
          inTheAir: partInTheAir(number),
          saved: saved.contains(scopeOfRow(number)),
          recording: cenaDaGravacao == number && ensaio != EnsaioStatus.idle,
          playing: _numberAt(playing) == number,
        ),
    ];
  }

  List<int> _partsWithASendBeyond(int lastScene) => [
    for (final number in {
      ...unsentParts.keys,
      for (final kept in machine.keptThisVisit.values)
        if (kept.session == sessionId) ?rowOf(kept.scope),
      for (final keep in machine.keeping.keys)
        if (keep.session == sessionId) ?rowOf(keep.scope),
      ?switch (_theTakeInTheAirOf(partTakeKind)) {
        final take? => rowOf(take.keep.scope),
        null => null,
      },
    })
      if (number > lastScene) number,
  ]..sort();

  /// The number of the part at [index] in [partes]; just past them, the scene of a
  /// recording waiting for the check.
  int? _numberAt(int? index) => switch (index) {
    final at? when at < partes.length => rowOf(partes[at].scopeId),
    final at? when at == partes.length && ensaio == EnsaioStatus.recorded =>
      cenaDaGravacao,
    _ => null,
  };

  bool get offersTheVerdictAgain =>
      stage == SalaStage.retro && lastSpoken != null;

  bool get canHearTheVerdictAgain =>
      offersTheVerdictAgain &&
      (voice == VoiceState.invite || voice == VoiceState.done) &&
      !btClipRodando &&
      !btTrechoTocando &&
      !btRetroTocando &&
      btRegravacao == null;

  bool get canHearAgain =>
      (lastSpoken != null || roomSaysItAgain) &&
      (voice == VoiceState.invite || voice == VoiceState.done) &&
      !needsPerson &&
      !noteMode &&
      stage != SalaStage.ensaio &&
      stage != SalaStage.retro &&
      stage != SalaStage.checagem &&
      !sceneRehearsalIsOpen;

  /// Whether the scene rehearsal's screen stands over the Canvas.
  bool get sceneRehearsalIsOpen => station is SceneRehearsal;

  /// Whether the plan holds its gestures: a label is in the air, or a join runs.
  bool get planBusy => labelling || joining != null;

  bool get homeBusy => swapping != null;

  bool get nothingStartsNow =>
      ensaio != EnsaioStatus.idle ||
      _theTakeInTheAirOf(partTakeKind) != null ||
      machine.keeping.keys.any((part) => part.session == sessionId) ||
      joining != null ||
      bringingBack != null ||
      grainSwitching;

  /// Each Scene row's plan row and what it offers on the recording home, by number, from
  /// the scene-rehearsal listing the home last read.
  Map<int, ({PlanRow plan, HomeRow home})> get homeRows {
    final (read, sessionId) = (ensaioFinalPlan, this.sessionId);
    if (read is! PlanRead || sessionId == null || recordsTheWhole) {
      return const {};
    }
    final plans = {
      for (final plan in planRowsOf(read, sessionId, const {}))
        plan.number: plan,
    };
    return {
      for (final row in sceneRows)
        if (plans[row.number] case final plan?)
          row.number: (
            plan: plan,
            home: homeRowOf(
              read,
              plan,
              origin: row.part?.origin,
              held: row.unsent != null,
            ),
          ),
    };
  }

  /// Whether «terminei» is in the air: the scene rehearsal waits on the voice.
  /// The loudness of the take on the scene screen, until it is read or for a take with
  /// none: a pausa then stays at the tap.
  Envelope? get sceneEnvelope => sceneLoudness
      .where((loudness) => loudness.take == scene.take)
      .firstOrNull
      ?.envelope;

  /// The frase being translated again whose pausa the team may move: the last one, on a
  /// take with loudness to read.
  SceneFrase? get sceneFraseOnTheMove =>
      switch ((scene.translatingAgain, scene.rehearsal?.lastFrase)) {
        (final again?, final last?)
            when again.fraseId == last.fraseId && sceneEnvelope != null =>
          again,
        _ => null,
      };

  /// Where a pending pausa may go: past the start of the frase on the move, else past
  /// where the translation stopped, and short of the take's end.
  ({Duration lo, Duration hi})? get scenePausaBounds => switch (scene.takeEnd) {
    final end? => pauseBounds(scenePausaFloor, end),
    null => null,
  };

  Duration get scenePausaFloor =>
      scene.rehearsal?.pausaFloor(sceneFraseOnTheMove) ?? Duration.zero;

  /// Whether the pending pausa shows her adjust row: on a take with loudness to read,
  /// never at the take's own end placed by itself unless the last frase's pausa is on
  /// the move.
  bool get scenePausaAdjusts =>
      scene.pausa != null &&
      sceneEnvelope != null &&
      (sceneFraseOnTheMove != null || scene.pausa != scene.takeEnd);

  /// Whether «recomeçar a tradução» applies: a rehearsal being translated, so never a
  /// sent one, with a translated frase.
  bool get sceneRestartShown =>
      (scene.step == SceneStep.translate ||
          scene.step == SceneStep.placesUnknown) &&
      (scene.rehearsal?.translatedFrases ?? 0) > 0;

  /// Whether the room may hold a new translation the team has not seen in the rehearsal
  /// on the scene screen.
  bool get sceneTranslationUnseen =>
      sceneTranslationsUnseen.containsKey(scene.rehearsal?.rehearsalId);

  bool get sceneFraseHeld =>
      sceneFrasesHeld.contains(scene.rehearsal?.rehearsalId);

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

  bool get aQuestionRecords =>
      noteMode &&
      switch (channel) {
        Microphone(owner: MicOwner.question) => true,
        _ => false,
      };

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

  /// The entry tapped on the Choice whose session has not landed: the team stays on the
  /// Choice until it does.
  Passagem? get theEntryOpening => switch (station) {
    _ when !awaitingTheGuide => null,
    Canvas() when sessionId == null => openingEntry,
    Panorama() when panoramaSessionId == null => openingEntry,
    _ => null,
  };

  SalaStage get stage =>
      theEntryOpening != null ? SalaStage.escolha : station.stage;

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

  /// Whether the listener's circle answers a tap: at the retelling, once X-retell was
  /// said, no line speaks and nothing is being sent. Its own open microphone counts, as
  /// the tap stops it.
  bool get listenerCircleOpen =>
      station is ChecagemExterna &&
      externalCheck.step == ListenerStep.retell &&
      externalCheck.retellSaid &&
      !externalCheck.sending &&
      channel is! GuideSpeaking;

  /// Whether «ouvir de novo» plays the passage again: on a stall, or at the retelling,
  /// while no microphone is open, no line speaks and nothing is being sent.
  bool get listenerMayHearItAgain =>
      station is ChecagemExterna &&
      (externalCheck.step == ListenerStep.retell || externalCheck.stalled) &&
      !externalCheck.sending &&
      channel is! Microphone &&
      channel is! GuideSpeaking;

  /// Whether the listener's microphone is the one open.
  bool get listenerRecording => switch (channel) {
    Microphone(owner: MicOwner.listener) => true,
    _ => false,
  };

  /// The scene the question highlights.
  String? get sceneHighlighted =>
      scenes.highlighted(sceneRehearsals, again: scene.again);

  bool get wordlessTelling => machine.wordlessTelling;

  VoiceState get voice {
    if (halt is Blocking) return VoiceState.invite;
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

  DateTime? get takeRecordingSince => switch (channel) {
    Microphone(owner: MicOwner.conversation)
        when !micTaken && machine.lastMic?.because == null =>
      recorderStartedAt,
    _ => null,
  };

  VoiceState get circleVoice => switch (channel) {
    Microphone(owner: MicOwner.conversation) when takeRecordingSince == null =>
      _resting,
    _ => voice,
  };

  bool get writesTheThinkingNote =>
      circleVoice == VoiceState.thinking && halt is! Blocking;

  VoiceState get _resting {
    if (awaitingTheGuide) return VoiceState.thinking;
    if (endOfThePassage ||
        (stage == SalaStage.retro && btPhase == BtPhase.conferida)) {
      return VoiceState.done;
    }
    return VoiceState.invite;
  }

  bool get btClipRodando => stage == SalaStage.retro && channel is PartPlaying;

  bool get btTrechoTocando => switch (channel) {
    StretchPlaying(stretch: StretchSound(telling: false, :final path)) =>
      path != btRegravacao?.path,
    _ => false,
  };

  bool get btRetroTocando => switch (channel) {
    StretchPlaying(stretch: StretchSound(telling: true)) => true,
    _ => false,
  };

  bool get btFraseGravadaTocando => switch (channel) {
    StretchPlaying(:final stretch) => stretch.path == btRegravacao?.path,
    _ => false,
  };

  Channel get _paused => switch (channel) {
    GuideSpeaking(held: final Paused held) => held,
    _ => channel,
  };

  bool get btTrechoPausada => switch (_paused) {
    Paused(what: StretchSound(telling: false, :final path)) =>
      path != btRegravacao?.path,
    _ => false,
  };

  bool get btClipPausada => switch (_paused) {
    Paused(what: PartSound()) => stage == SalaStage.retro,
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

  /// The part in the air on the Rehearsal, found by its file, so a part leaving before it
  /// does not move it.
  int? get parteDoEnsaioTocando {
    if (stage != SalaStage.ensaio) return null;
    final PartSound som;
    switch (_paused) {
      case PartPlaying(:final part):
        som = part;
      case Paused(what: final PartSound part):
        som = part;
      default:
        return null;
    }
    final aqui = partes.indexWhere((parte) => parte.path == som.path);
    return aqui < 0 ? som.part : aqui;
  }

  bool get needsPerson => halt is Blocking;

  bool get _aPassageWaits => leftEntry != null && machine.waiting != null;

  /// The Choice offers the way back to a passage held at once; to an entry left with no
  /// session, once the Wheel is read. The scene rehearsal's screen always offers the way
  /// back to the Conversation. The person sign hides it.
  bool get theWayBackIsOffered =>
      sceneRehearsalIsOpen ||
      (stage == SalaStage.escolha &&
          leftEntry != null &&
          !needsPerson &&
          (_aPassageWaits || naRoda != null));

  /// The way back to a passage held answers the finger always; to any other entry, only
  /// while the Wheel is quiet. From any Step of the scene rehearsal it answers with its
  /// microphone open and «terminei» in the air included.
  bool get theWayBackIsLive => sceneRehearsalIsOpen
      ? !scene.wentToTheVoice
      : theWayBackIsOffered && (_aPassageWaits || voice == VoiceState.invite);

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

  bool get canFinishBackTranslation =>
      stage == SalaStage.retro &&
      (btPhase == BtPhase.playing || btPhase == BtPhase.conferida) &&
      (btOuvidaInteira ?? btClipEnded) &&
      !btSoOuvir &&
      aBackTranslationGestureActs;

  bool get _btNaVez =>
      stage == SalaStage.retro && btPhase == BtPhase.playing && !needsPerson;

  bool get btCortado => btCorte > btCursor;

  /// Whether nothing has been heard since the cursor: the guard the capture and the
  /// circle's label share.
  bool get nothingHeardSinceCursor => !btOuvidoAlemDoCursor;

  int? get _btInicioDaParteMs {
    if (btParte == 0) return 0;
    if (btParte > btFimDasPartesMs.length) return null;
    return btFimDasPartesMs[btParte - 1];
  }

  int numeroDaParte(int parte) => switch (partes.elementAtOrNull(parte)) {
    final take? => KeptScope.numberOf(take.scopeId) ?? parte + 1,
    null => parte + 1,
  };

  Duration? btTamanhoDaParte(int parte) {
    if (parte >= btFimDasPartesMs.length) return null;
    final inicio = parte == 0 ? 0 : btFimDasPartesMs[parte - 1];
    return Duration(milliseconds: btFimDasPartesMs[parte] - inicio);
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

  bool get _btOuvidaCoberta =>
      (btOuvidaInteira ?? (btClipEnded && _btParteContada)) && !btRestoPorOuvir;

  bool get btContadaInteira =>
      _btOuvidaCoberta &&
      (btTraducaoPendente == null || btTraducaoPendenteEmprestada);

  bool get canAdvanceToTheVerdict =>
      canFinishBackTranslation &&
      btContadaInteira &&
      btFraseQueAguarda == null &&
      btRegravacao == null &&
      channel is! GuideSpeaking &&
      !awaitingTheGuide &&
      (!joined ||
          partes.indexed.every(
            (parte) => btTrechos.any(
              (trecho) => trecho.contado && trecho.parte == parte.$1,
            ),
          )) &&
      btTrechos.any((trecho) => trecho.contado);

  bool get _btDebaixoDoTerminei =>
      voice == VoiceState.invite && btTrechos.any((trecho) => trecho.contado);

  bool get btAindaFaltaOuvir =>
      _btDebaixoDoTerminei &&
      btRecusa != CheckRefusal.stretchUntranslated &&
      !_btOuvidaCoberta;

  bool get btFaltaTraduzirUmTrecho =>
      _btDebaixoDoTerminei && btRecusa == CheckRefusal.stretchUntranslated;

  bool get btRestoDepoisDoCorte {
    if (!btCortado) return false;
    final parte = _btParteMs;
    return btParte < partes.length - 1 ||
        parte == null ||
        (btCorte + folgaDoFimDaParte).inMilliseconds < parte;
  }

  bool get thePauseStands =>
      _btNaVez &&
      btCortado &&
      btTraducaoPendente == null &&
      btTrechoTraduzidoDeNovo == null &&
      btContaEscolhida == null;

  bool get thePauseCanMove =>
      btPausaAjustavel &&
      btFraseQueAguarda == null &&
      (btCortado || btTrechoTraduzidoDeNovo != null);

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
  /// part; from the first one on it is set aside, kept but no longer played or told. While
  /// the room records the passage whole, only the whole is (ADR 0134).
  List<KeptTake> get partes => _partesDe(keptTakes, grainInForce);

  static List<KeptTake> _partesDe(
    List<KeptTake> keptTakes,
    Grain? grainInForce,
  ) {
    final wholes = [
      for (final take in keptTakes)
        if (take.scopeId == KeptScope.whole) take,
    ];
    if (grainInForce == Grain.whole) return wholes;
    final numbered = [
      for (final take in keptTakes)
        if (KeptScope.isParte(take.scopeId)) take,
    ]..sort((a, b) => _byNumber(a).compareTo(_byNumber(b)));
    if (numbered.isNotEmpty || grainInForce == Grain.scene) return numbered;
    return wholes;
  }

  List<Trecho> _nasSuasPartes(
    List<Trecho> trechos,
    List<KeptTake>? keptTakes,
    Grain? grainInForce,
  ) {
    if (keptTakes == null) return trechos;
    final agora = _partesDe(keptTakes, grainInForce ?? this.grainInForce);
    final onde = [
      for (final era in partes)
        agora.indexWhere((parte) => parte.scopeId == era.scopeId),
    ];
    final ficam = [
      for (final trecho in trechos)
        if (trecho.parte < 0 || trecho.parte >= onde.length)
          trecho
        else if (onde[trecho.parte] >= 0)
          trecho.naParte(onde[trecho.parte]),
    ];
    if (ficam.length != trechos.length) return ficam;
    for (final (i, trecho) in ficam.indexed) {
      if (trecho.parte != trechos[i].parte) return ficam;
    }
    return trechos;
  }

  /// The recordings of a whole rehearsal set aside behind the scenes' own parts; none
  /// while the room records the passage whole.
  Set<String> get wholeSetAside => grainInForce == Grain.whole
      ? const {}
      : {
          ...wholeHeldByTheRoom,
          if (keptTakes.any((take) => KeptScope.isParte(take.scopeId)))
            for (final take in keptTakes)
              if (take.scopeId == KeptScope.whole) ?take.takeId,
        };

  static int _byNumber(KeptTake take) => KeptScope.numberOf(take.scopeId) ?? 0;

  bool get canOuvirTudo =>
      partes.isNotEmpty && ensaio == EnsaioStatus.idle && !needsPerson;

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

  bool regravadaTraduzivelDeNovo(Trecho regravada) {
    final takeId = switch (regravada.parte) {
      final at when at >= 0 && at < partes.length => partes[at].takeId,
      _ => null,
    };
    return takeId != null &&
        !btTrechos.any(
          (trecho) =>
              trecho.takeId == takeId &&
              trecho.from < regravada.lugarTo &&
              regravada.lugarFrom < trecho.to,
        );
  }

  bool fraseRegravavel(Trecho trecho) =>
      !btSoOuvir &&
      aBackTranslationGestureActs &&
      trecho.frase != null &&
      trecho.segmentId != null &&
      btFraseTraduzidaDeNovo == null &&
      btRegravacao?.passo != PassoDaRegravacao.enviando &&
      btFraseDevida == null &&
      (btFraseGuardada == null || btFraseGuardada == trecho.segmentId) &&
      (btFraseQueAguarda == null || btFraseQueAguarda == trecho.segmentId) &&
      !needsPerson &&
      trecho.parte >= 0 &&
      trecho.parte < partes.length &&
      partes[trecho.parte].isWav;

  bool get overAnApprovedDraft => btRascunhoAprovado != null;

  bool get microphoneOpen => channel is Microphone;

  /// The approval drawn on the checked telling-back, in place of the approve button and the
  /// Warning mark: only while nothing of this session waits in the Outbox (ADR 0106, 0150).
  ApprovedDraft? get approvedDraftDrawn =>
      stage == SalaStage.retro &&
          btPhase == BtPhase.conferida &&
          nothingWaitsInTheOutbox &&
          btFraseGuardada == null
      ? btRascunhoAprovado
      : null;

  /// Whether the last listening the clean verdict invites has anything to play.
  ///
  /// A session picked back up over a room that holds no rehearsal of its own carries the
  /// room's stretches and no file at all, and a lit player answering with silence has no
  /// way to explain itself in a room with no written word. It lives here rather than on
  /// the screen so the affordance and the verb it opens read the same fact; the verb keeps
  /// its own guard as well, because it is reachable from more than this one press.
  bool get canListenAtConferida =>
      btPhase == BtPhase.conferida &&
      partes.isNotEmpty &&
      aBackTranslationGestureActs;

  /// Whether a gesture on the Back-translation acts: never while an approval or an open of
  /// the Checagem externa is in the air, so nothing the team presses meanwhile moves what
  /// the answer lands on.
  bool get aBackTranslationGestureActs =>
      btAprovando != machine.generation &&
      btAbrindoAChecagem != machine.generation &&
      !aFraseDevidaEmBusca;

  bool get aFraseDevidaEmBusca =>
      btFraseDevida != null &&
      btRegravacao?.passo == PassoDaRegravacao.enviando;

  /// Whether an approval may still be won over what the room holds: no approved version,
  /// or a forced one, which a conferida telling approves again as the next (ADR 0150).
  bool get approvalStillOpen => btRascunhoAprovado?.forced ?? true;

  ApprovedDraft? get approvedOnTheTell =>
      stage == SalaStage.retro &&
          !btSoOuvir &&
          nothingWaitsInTheOutbox &&
          btFraseGuardada == null
      ? btRascunhoAprovado
      : null;

  bool get approveOnTheCheck =>
      stage == SalaStage.retro &&
      !btSoOuvir &&
      (btChecked || btPhase == BtPhase.conferida) &&
      (approvedOnTheTell == null || approvalStillOpen);

  bool get approveActsOnTheCheck =>
      approveOnTheCheck &&
      canApprove &&
      (btPhase == BtPhase.playing || btPhase == BtPhase.conferida) &&
      channel is! GuideSpeaking;

  /// Whether the recording home offers the approval: the room calls the passage checked
  /// and the approval is still open, and nothing is being recorded or sent.
  bool get approveOffered =>
      stage == SalaStage.ensaio &&
      ensaio == EnsaioStatus.idle &&
      btChecked &&
      approvalStillOpen &&
      ensaioSalvo == null &&
      nothingWaitsInTheOutbox &&
      aBackTranslationGestureActs;

  /// The approval drawn on the recording home: in place of the approve button, or under it
  /// while the approval is still open (ADR 0150).
  ApprovedDraft? get approvedOnTheHome =>
      stage == SalaStage.ensaio &&
          ensaio == EnsaioStatus.idle &&
          nothingWaitsInTheOutbox
      ? btRascunhoAprovado
      : null;

  bool get nothingWaitsInTheOutbox => unsentTakes == 0 && unsentChunks == 0;

  /// Whether the approve button acts: never while a sentence's re-record is open.
  bool get canApprove => aBackTranslationGestureActs && btRegravacao == null;

  bool get canGoBackToRecordAPart =>
      btRegravacao == null &&
      aBackTranslationGestureActs &&
      switch (channel) {
        GuideSpeaking(line: Line(fixedLine: null)) => false,
        GuideSpeaking() => true,
        _ => btPhase == BtPhase.playing || btPhase == BtPhase.conferida,
      };

  bool get canRetellAFrase =>
      stage == SalaStage.retro &&
      !btSoOuvir &&
      partes.isNotEmpty &&
      !needsPerson &&
      aBackTranslationGestureActs &&
      btRegravacao == null &&
      btFraseQueAguarda == null &&
      (btPhase == BtPhase.conferida || btPhase == BtPhase.playing);

  bool get wholeSwitchActsOnTheCheck =>
      joined &&
      !btSoOuvir &&
      (btPhase == BtPhase.playing || btPhase == BtPhase.conferida) &&
      channel is! Playing &&
      channel is! GuideSpeaking &&
      btRegravacao == null &&
      aBackTranslationGestureActs &&
      !needsPerson;

  bool get canHearAFrase =>
      stage == SalaStage.retro &&
      !btSoOuvir &&
      partes.isNotEmpty &&
      !needsPerson &&
      aBackTranslationGestureActs &&
      btRegravacao == null &&
      (btPhase == BtPhase.playing || btPhase == BtPhase.conferida);

  bool get theFraseListIsIdle =>
      (btPhase == BtPhase.playing || btPhase == BtPhase.conferida) &&
      channel is! GuideSpeaking;

  SalaSessionState copyWith({
    bool? awaitingTheGuide,
    bool? arrivedAtTheChoice,
    LeftEntry? leftEntry,
    bool clearLeftEntry = false,
    Passagem? openingEntry,
    bool clearOpeningEntry = false,
    PassageLeft? passageLeft,
    bool clearPassageLeft = false,
    bool? endOfThePassage,
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
    List<Trecho>? btTrechosRegravados,
    List<String>? btNaoOuvidas,
    int? btParteQueTocou,
    bool clearBtParteQueTocou = false,
    List<BtFinding>? btFindings,
    bool? btConferindo,
    bool? btVeredito,
    CheckRefusal? btRecusa,
    List<int>? btCenasSemTraducao,
    bool clearBtRecusa = false,
    String? btFindingSegmentId,
    bool clearFindingSegment = false,
    bool? btClipEnded,
    bool? btOuvidaInteira,
    bool? btRestoPorOuvir,
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
    ArmedTap? armedTap,
    bool clearArmedTap = false,
    BtAviso? btAviso,
    bool? btRecomecada,
    bool clearAviso = false,
    RegravacaoDaFrase? btRegravacao,
    bool clearBtRegravacao = false,
    String? btFraseQueAguarda,
    bool clearBtFraseQueAguarda = false,
    String? btFraseGuardada,
    bool clearBtFraseGuardada = false,
    String? btFraseDevida,
    bool clearBtFraseDevida = false,
    ApprovedDraft? btRascunhoAprovado,
    bool clearBtRascunhoAprovado = false,
    bool? btSoOuvir,
    int? btAprovando,
    int? btAbrindoAChecagem,
    bool clearBtAprovando = false,
    bool clearBtAbrindoAChecagem = false,
    int? btAprovadoAgora,
    bool clearBtAprovadoAgora = false,
    int? ensaioSalvo,
    bool clearEnsaioSalvo = false,
    OuvirTudo? ouvirTudo,
    bool? btChecked,
    int? unsentTakes,
    int? unsentChunks,
    Map<int, UnsentPart>? unsentParts,
    Set<int>? heldScenes,
    Machine? machine,
    DateTime? recorderStartedAt,
    bool clearRecorderStartedAt = false,
    int? cenaDaGravacao,
    bool clearCenaDaGravacao = false,
    SceneScreen? scene,
    ExternalCheckScreen? externalCheck,
    List<SceneRehearsalRecord>? sceneRehearsals,
    Map<String, String>? sceneTranslationsUnseen,
    Set<String>? sceneFrasesHeld,
    List<({String take, Envelope? envelope})>? sceneLoudness,
    Map<String, ({Duration length, Envelope? envelope})>? partLoudness,
    SceneList? scenes,
    List<Scene>? scenesOfThePassage,
    ({String rehearsalId, String turnId})? sceneTurn,
    bool clearSceneTurn = false,
    Duration? sceneStoppedAt,
    bool clearSceneStoppedAt = false,
    BtRecomeco? sceneRestart,
    bool clearSceneRestart = false,
    SceneLine? sceneLine,
    bool clearSceneLine = false,
    EnsaioFinalPlan? ensaioFinalPlan,
    Map<String, String>? planChoices,
    PlanListen? planListening,
    bool clearPlanListening = false,
    Map<int, JoinRow>? joinRows,
    int? joining,
    bool clearJoining = false,
    String? planSheet,
    bool clearPlanSheet = false,
    bool? labelling,
    bool? labelLine,
    String? homeSheet,
    bool clearHomeSheet = false,
    String? swapping,
    bool clearSwapping = false,
    ({String rehearsalId, bool cannotEnter})? swapLine,
    bool clearSwapLine = false,
    bool? hearNewScene,
    bool? rehearsalsElsewhere,
    Set<int>? theRoomJoinedParts,
    Grain? grainInForce,
    bool clearGrainInForce = false,
    bool? grainSwitching,
    List<int>? toBringBack,
    int? bringingBack,
    bool clearBringingBack = false,
    ({int cena, bool cannotEnter})? bringBackFailed,
    bool clearBringBackFailed = false,
    Set<String>? wholeHeldByTheRoom,
  }) {
    return SalaSessionState(
      awaitingTheGuide: awaitingTheGuide ?? this.awaitingTheGuide,
      arrivedAtTheChoice: arrivedAtTheChoice ?? this.arrivedAtTheChoice,
      leftEntry: clearLeftEntry ? null : (leftEntry ?? this.leftEntry),
      openingEntry: clearOpeningEntry
          ? null
          : (openingEntry ?? this.openingEntry),
      passageLeft: clearPassageLeft ? null : (passageLeft ?? this.passageLeft),
      endOfThePassage: endOfThePassage ?? this.endOfThePassage,
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
      btTrechos:
          btTrechos ?? _nasSuasPartes(this.btTrechos, keptTakes, grainInForce),
      btTrechosRegravados:
          btTrechosRegravados ??
          _nasSuasPartes(this.btTrechosRegravados, keptTakes, grainInForce),
      btNaoOuvidas: btNaoOuvidas ?? this.btNaoOuvidas,
      btParteQueTocou: clearBtParteQueTocou
          ? null
          : (btParteQueTocou ?? this.btParteQueTocou),
      btFindings: btFindings ?? this.btFindings,
      btConferindo: btConferindo ?? this.btConferindo,
      btVeredito: btVeredito ?? this.btVeredito,
      btRecusa: clearBtRecusa ? null : (btRecusa ?? this.btRecusa),
      btCenasSemTraducao: btCenasSemTraducao ?? this.btCenasSemTraducao,
      btFindingSegmentId: clearFindingSegment
          ? null
          : (btFindingSegmentId ?? this.btFindingSegmentId),
      btClipEnded: btClipEnded ?? this.btClipEnded,
      btOuvidaInteira: btOuvidaInteira ?? this.btOuvidaInteira,
      btRestoPorOuvir: btRestoPorOuvir ?? this.btRestoPorOuvir,
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
      armedTap: clearArmedTap ? null : (armedTap ?? this.armedTap),
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
      btFraseDevida: clearBtFraseDevida
          ? null
          : (btFraseDevida ?? this.btFraseDevida),
      btRascunhoAprovado: clearBtRascunhoAprovado
          ? null
          : (btRascunhoAprovado ?? this.btRascunhoAprovado),
      btSoOuvir: btSoOuvir ?? this.btSoOuvir,
      btAprovando: clearBtAprovando ? null : (btAprovando ?? this.btAprovando),
      btAbrindoAChecagem: clearBtAbrindoAChecagem
          ? null
          : (btAbrindoAChecagem ?? this.btAbrindoAChecagem),
      btAprovadoAgora: clearBtAprovadoAgora
          ? null
          : (btAprovadoAgora ?? this.btAprovadoAgora),
      ensaioSalvo: clearEnsaioSalvo ? null : (ensaioSalvo ?? this.ensaioSalvo),
      ouvirTudo: ouvirTudo ?? this.ouvirTudo,
      btChecked: btChecked ?? this.btChecked,
      unsentTakes: unsentTakes ?? this.unsentTakes,
      unsentChunks: unsentChunks ?? this.unsentChunks,
      unsentParts: unsentParts ?? this.unsentParts,
      heldScenes: heldScenes ?? this.heldScenes,
      machine: machine ?? this.machine,
      recorderStartedAt: clearRecorderStartedAt
          ? null
          : (recorderStartedAt ?? this.recorderStartedAt),
      cenaDaGravacao: clearCenaDaGravacao
          ? null
          : (cenaDaGravacao ?? this.cenaDaGravacao),
      scene: scene ?? this.scene,
      externalCheck: externalCheck ?? this.externalCheck,
      sceneRehearsals: sceneRehearsals ?? this.sceneRehearsals,
      sceneTranslationsUnseen:
          sceneTranslationsUnseen ?? this.sceneTranslationsUnseen,
      sceneFrasesHeld: sceneFrasesHeld ?? this.sceneFrasesHeld,
      sceneLoudness: sceneLoudness ?? this.sceneLoudness,
      partLoudness: partLoudness ?? this.partLoudness,
      scenes: scenes ?? this.scenes,
      scenesOfThePassage: scenesOfThePassage ?? this.scenesOfThePassage,
      sceneTurn: clearSceneTurn ? null : (sceneTurn ?? this.sceneTurn),
      sceneStoppedAt: clearSceneStoppedAt
          ? null
          : (sceneStoppedAt ?? this.sceneStoppedAt),
      sceneRestart: clearSceneRestart
          ? null
          : (sceneRestart ?? this.sceneRestart),
      sceneLine: clearSceneLine ? null : (sceneLine ?? this.sceneLine),
      ensaioFinalPlan: ensaioFinalPlan ?? this.ensaioFinalPlan,
      planChoices: planChoices ?? this.planChoices,
      planListening: clearPlanListening
          ? null
          : (planListening ?? this.planListening),
      joinRows: joinRows ?? this.joinRows,
      joining: clearJoining ? null : (joining ?? this.joining),
      planSheet: clearPlanSheet ? null : (planSheet ?? this.planSheet),
      labelling: labelling ?? this.labelling,
      labelLine: labelLine ?? this.labelLine,
      homeSheet: clearHomeSheet ? null : (homeSheet ?? this.homeSheet),
      swapping: clearSwapping ? null : (swapping ?? this.swapping),
      swapLine: clearSwapLine ? null : (swapLine ?? this.swapLine),
      hearNewScene: hearNewScene ?? this.hearNewScene,
      rehearsalsElsewhere: rehearsalsElsewhere ?? this.rehearsalsElsewhere,
      theRoomJoinedParts: theRoomJoinedParts ?? this.theRoomJoinedParts,
      grainInForce: clearGrainInForce
          ? null
          : (grainInForce ?? this.grainInForce),
      grainSwitching: grainSwitching ?? this.grainSwitching,
      toBringBack: toBringBack ?? this.toBringBack,
      bringingBack: clearBringingBack
          ? null
          : (bringingBack ?? this.bringingBack),
      bringBackFailed: clearBringBackFailed
          ? null
          : (bringBackFailed ?? this.bringBackFailed),
      wholeHeldByTheRoom: wholeHeldByTheRoom ?? this.wholeHeldByTheRoom,
    );
  }
}

/// One Scene row of the Rehearsal.
class SceneRow {
  final int number;

  /// The Scene's title as the scenes door answered it; null for a passage with no scenes.
  final String? title;

  /// A part beyond the passage's last scene: its row tells the send and records nothing.
  final bool beyondTheScenes;
  final KeptTake? part;
  final UnsentPart? unsent;
  final TakeInTheAir? inTheAir;
  final bool saved;
  final bool recording;

  /// The part in the air, playing or held.
  final bool playing;

  const SceneRow({
    required this.number,
    required this.title,
    required this.beyondTheScenes,
    required this.part,
    required this.unsent,
    required this.inTheAir,
    required this.saved,
    required this.recording,
    required this.playing,
  });

  /// Whether «Ouvir» would play the take that is gone: the room's own part, which carries
  /// the room's id, still plays.
  bool get playsTheGoneTake =>
      unsent?.failure == SendFailure.gone && part?.takeId == null;
}
