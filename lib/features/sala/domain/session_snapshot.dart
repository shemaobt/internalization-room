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
  final int passNumber;

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
    this.passNumber = 1,
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
        passNumber: json['pass_number'] as int? ?? 1,
        told: json['told'] as bool? ?? true,
      );
}

/// What the room answers when a stretch is told again.
///
/// [captured] is false when the room made nothing out of the recording, and then the
/// stretch is left exactly as it was: swapping an explanation for an empty one over a
/// transcriber outage would lose the team's work to somebody else's failure.
class TellingAgain {
  final List<SegmentView> segments;
  final bool captured;

  const TellingAgain({this.segments = const [], this.captured = true});

  factory TellingAgain.fromJson(Map<String, dynamic> json) => TellingAgain(
        segments: SegmentView.listFrom(json),
        captured: json['captured'] as bool? ?? true,
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

  const SessionSnapshot({
    required this.sessionId,
    required this.pericope,
    required this.status,
    required this.coverage,
    required this.done,
    this.backTranslation = const BackTranslationProgress(),
    this.halt = HaltKind.unnamed,
  });

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) => SessionSnapshot(
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
      );

  /// A halt the server calls a warning asks for a person to come and watch and refuses
  /// the team nothing; reading it as a stop closed the room over a note.
  bool get needsPerson =>
      status == 'needs_person' && halt != HaltKind.warning;
}
