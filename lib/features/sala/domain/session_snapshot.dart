import 'bt_finding.dart';
import 'coverage.dart';
import 'grain.dart';
import 'moment.dart';

/// One stretch the team told back, addressed rather than counted.
///
/// [takeId] with [startsMs]/[endsMs] is the whole address of the audio: which rehearsal
/// recording, and which slice of that file.
class SegmentView {
  final String segmentId;
  final String takeId;
  final int startsMs;
  final int endsMs;

  /// Whether the team has explained this stretch in the bridge language yet.
  ///
  /// A stretch born of a division has no explanation, and the first round does not run
  /// while a final stretch is missing one. The app threw this away, so it could not tell
  /// a stretch waiting to be told from one already told.
  final bool told;
  final int? frase;

  const SegmentView({
    required this.segmentId,
    required this.takeId,
    required this.startsMs,
    required this.endsMs,
    this.told = true,
    this.frase,
  });

  static List<SegmentView> listFrom(Map<String, dynamic> json) =>
      _listed(json, stale: false);

  static List<SegmentView> staleFrom(Map<String, dynamic> json) =>
      _listed(json, stale: true);

  static List<SegmentView> _listed(
    Map<String, dynamic> json, {
    required bool stale,
  }) => [
    for (final raw in (json['segments'] as List? ?? const []))
      if (raw is Map && (raw['stale'] == true) == stale)
        SegmentView.fromJson(raw.cast<String, dynamic>()),
  ];

  factory SegmentView.fromJson(Map<String, dynamic> json) => SegmentView(
    segmentId: json['segment_id'] as String? ?? '',
    takeId: json['take_id'] as String? ?? '',
    startsMs: json['starts_ms'] as int? ?? 0,
    endsMs: json['ends_ms'] as int? ?? 0,
    told: json['told'] as bool? ?? true,
    frase: json['frase'] as int?,
  );
}

/// One recording the room is holding for a session.
///
/// [ordinal] is the number the server holds for the take, which is the part of the
/// rehearsal it answers for. Which part a recording belongs to is the one thing the
/// stretches cannot say, so a tablet holding a stretch addressed to a recording it does
/// not have reads it here.
class TakeView {
  final String takeId;

  /// What the room was given this recording as: `ensaio` for a part of the rehearsal,
  /// `retro` for a stretch told back. A tablet rebuilding the rehearsal reads it, because
  /// a telling-back is not a part of the story and must never be played as one.
  final String kind;
  final String scope;
  final int? ordinal;

  /// Which of its part's recordings the room counted this one as. Absent from a listing
  /// written before the tablet sent it.
  final int? pass;

  /// The Scene rehearsal a joined part was laid in from. Absent from a part recorded as
  /// itself, and from a listing written before the room answered it.
  final String? origin;

  /// When a grain switch set this recording aside. Absent from a current recording, and
  /// from a listing written by a room that never sets one aside.
  final String? setAsideAt;

  const TakeView({
    required this.takeId,
    required this.scope,
    this.kind = '',
    this.ordinal,
    this.pass,
    this.origin,
    this.setAsideAt,
  });

  bool get setAside => setAsideAt != null;

  static List<TakeView> listFrom(Map<String, dynamic> json) => [
    for (final raw in (json['takes'] as List? ?? const []))
      if (raw is Map) TakeView.fromJson(raw.cast<String, dynamic>()),
  ];

  factory TakeView.fromJson(Map<String, dynamic> json) => TakeView(
    takeId: json['take_id'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    scope: json['scope'] as String? ?? '',
    ordinal: json['ordinal'] as int?,
    pass: json['pass_number'] as int?,
    origin: json['origin'] as String?,
    setAsideAt: json['set_aside_at'] as String?,
  );
}

/// The room's listing of a session's recordings, with the grain in force.
final class TakesListing {
  final List<TakeView> takes;
  final Grain? grain;

  const TakesListing({required this.takes, this.grain});

  factory TakesListing.fromJson(Map<String, dynamic> json) => TakesListing(
    takes: TakeView.listFrom(json),
    grain: Grain.fromWire(json['grain']),
  );
}

class KeptRetelling {
  final String scope;
  final int turnNumber;
  final String audioUrl;

  const KeptRetelling({
    required this.scope,
    required this.turnNumber,
    required this.audioUrl,
  });

  static List<KeptRetelling> listFrom(Map<String, dynamic> json) => [
    for (final raw in (json['kept_takes'] as List? ?? const []))
      if (raw is Map) KeptRetelling.fromJson(raw.cast<String, dynamic>()),
  ];

  factory KeptRetelling.fromJson(Map<String, dynamic> json) => KeptRetelling(
    scope: json['scope'] as String? ?? '',
    turnNumber: json['turn_number'] as int? ?? 0,
    audioUrl: json['audio_url'] as String? ?? '',
  );
}

/// What the room answers when a stretch is told again.
class TellingAgain {
  final List<SegmentView> segments;

  /// Whether the room has stopped taking corrections and wants somebody to come.
  ///
  /// It is a warning and never a stop: this is the room saying it has already called for
  /// somebody, and the team is refused nothing (ADR 0032). Absent means no such news: the
  /// field arrives only from a room that knows how to send it, and every other answer has
  /// to go on working.
  final bool needsPerson;

  const TellingAgain({this.segments = const [], this.needsPerson = false});

  factory TellingAgain.fromJson(Map<String, dynamic> json) => TellingAgain(
    segments: SegmentView.listFrom(json),
    needsPerson: json['needs_person'] as bool? ?? false,
  );
}

/// Where a telling-back stopped, as the room remembers it.
///
/// The session id lives only in memory, so every restart used to lose the retro entirely
/// and the team recorded the rehearsal again. All of this was already on the session and
/// travels with every session route; the app simply threw it away.
class BackTranslationProgress {
  final List<SegmentView> segments;
  final bool checked;
  final String? findingSegmentId;
  final List<BtFinding> findings;
  final String? awaitingSegmentId;
  final List<SegmentView> stale;
  final List<int> bringBack;

  const BackTranslationProgress({
    this.segments = const [],
    this.checked = false,
    this.findingSegmentId,
    this.findings = const [],
    this.awaitingSegmentId,
    this.stale = const [],
    this.bringBack = const [],
  });

  factory BackTranslationProgress.fromJson(Map<String, dynamic> json) =>
      BackTranslationProgress(
        segments: SegmentView.listFrom(json),
        checked: json['checked'] as bool? ?? false,
        findingSegmentId: json['finding_segment_id'] as String?,
        findings: BtFinding.listFrom(json),
        awaitingSegmentId: json['awaiting_segment_id'] as String?,
        stale: SegmentView.staleFrom(json),
        bringBack: [
          for (final n in json['bring_back'] as List<dynamic>? ?? const [])
            n as int,
        ],
      );

  bool get nothingTold => segments.isEmpty;
}

/// The approval the team's Draft stands under, while the room says the draft is still the
/// one it approved (ADR 0071 of the API).
class ApprovedDraft {
  final int version;
  final int listeners;

  /// Whether a person forced this version past a blocker. A forced version is the one a
  /// conferida telling approves again, minting the next (ADR 0101 of the API).
  final bool forced;

  const ApprovedDraft({
    required this.version,
    this.listeners = 0,
    this.forced = false,
  });

  static ApprovedDraft? fromJson(Object? raw) => switch (raw) {
    {'version': final int version, 'listeners': final int listeners} =>
      ApprovedDraft(
        version: version,
        listeners: listeners,
        forced: _forcedIn(raw),
      ),
    {'version': final int version} => ApprovedDraft(
      version: version,
      forced: _forcedIn(raw),
    ),
    _ => null,
  };

  static bool _forcedIn(Object? raw) => switch (raw) {
    {'forced': true} => true,
    _ => false,
  };
}

/// Which kind of halt the room is under.
///
/// [unnamed] is a halt a server older than the field raised: it carries no kind, and the
/// room reads it as blocking. Walking past a stop this tablet cannot name would leave the
/// team working inside a room somebody stopped for a reason nobody here can see.
enum HaltKind {
  blocking,
  warning,
  unnamed;

  static HaltKind fromJson(Object? raw) => switch (raw) {
    'blocking' => HaltKind.blocking,
    'warning' => HaltKind.warning,
    _ => HaltKind.unnamed,
  };
}

class SessionSnapshot {
  final String sessionId;
  final String pericope;
  final String status;
  final Coverage? coverage;
  final bool done;
  final BackTranslationProgress backTranslation;

  final HaltKind halt;

  final bool opened;

  final Moment? moment;

  final List<KeptRetelling> keptRetellings;

  final ApprovedDraft? approved;

  const SessionSnapshot({
    required this.sessionId,
    required this.pericope,
    required this.status,
    required this.coverage,
    required this.done,
    this.backTranslation = const BackTranslationProgress(),
    this.halt = HaltKind.unnamed,
    this.opened = false,
    this.moment,
    this.keptRetellings = const [],
    this.approved,
  });

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) =>
      SessionSnapshot(
        sessionId: json['session_id'] as String,
        pericope: json['pericope'] as String? ?? '',
        status: json['status'] as String? ?? '',
        coverage: json['coverage'] == null
            ? null
            : Coverage.fromJson(
                (json['coverage'] as Map).cast<String, dynamic>(),
              ),
        done: json['done'] as bool? ?? false,
        backTranslation: json['back_translation'] == null
            ? const BackTranslationProgress()
            : BackTranslationProgress.fromJson(
                (json['back_translation'] as Map).cast<String, dynamic>(),
              ),
        halt: HaltKind.fromJson(json['halt']),
        opened: json['opened'] as bool? ?? false,
        moment: Moment.fromJson(json['moment']),
        keptRetellings: KeptRetelling.listFrom(json),
        approved: ApprovedDraft.fromJson(json['approved']),
      );

  /// A halt the server calls a warning asks for a person to come and watch and refuses
  /// the team nothing; reading it as a stop closed the room over a note.
  bool get needsPerson => status == 'needs_person' && halt != HaltKind.warning;
}
