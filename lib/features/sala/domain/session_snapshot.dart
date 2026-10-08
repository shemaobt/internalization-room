import 'coverage.dart';

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

  const SegmentView({
    required this.segmentId,
    required this.takeId,
    required this.startsMs,
    required this.endsMs,
    this.told = true,
  });

  static List<SegmentView> listFrom(Map<String, dynamic> json) => [
    for (final raw in (json['segments'] as List? ?? const []))
      if (raw is Map) SegmentView.fromJson(raw.cast<String, dynamic>()),
  ];

  factory SegmentView.fromJson(Map<String, dynamic> json) => SegmentView(
    segmentId: json['segment_id'] as String? ?? '',
    takeId: json['take_id'] as String? ?? '',
    startsMs: json['starts_ms'] as int? ?? 0,
    endsMs: json['ends_ms'] as int? ?? 0,
    told: json['told'] as bool? ?? true,
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

  const TakeView({
    required this.takeId,
    required this.scope,
    this.kind = '',
    this.ordinal,
    this.pass,
  });

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

  const BackTranslationProgress({
    this.segments = const [],
    this.checked = false,
    this.findingSegmentId,
  });

  factory BackTranslationProgress.fromJson(Map<String, dynamic> json) =>
      BackTranslationProgress(
        segments: SegmentView.listFrom(json),
        checked: json['checked'] as bool? ?? false,
        findingSegmentId: json['finding_segment_id'] as String?,
      );

  bool get nothingTold => segments.isEmpty;
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

  const SessionSnapshot({
    required this.sessionId,
    required this.pericope,
    required this.status,
    required this.coverage,
    required this.done,
    this.backTranslation = const BackTranslationProgress(),
    this.halt = HaltKind.unnamed,
    this.opened = false,
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
      );

  /// A halt the server calls a warning asks for a person to come and watch and refuses
  /// the team nothing; reading it as a stop closed the room over a note.
  bool get needsPerson => status == 'needs_person' && halt != HaltKind.warning;
}
