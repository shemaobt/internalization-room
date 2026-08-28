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

  const SegmentView({
    required this.segmentId,
    required this.takeId,
    required this.startsMs,
    required this.endsMs,
    this.passNumber = 1,
  });

  factory SegmentView.fromJson(Map<String, dynamic> json) => SegmentView(
        segmentId: json['segment_id'] as String? ?? '',
        takeId: json['take_id'] as String? ?? '',
        startsMs: json['starts_ms'] as int? ?? 0,
        endsMs: json['ends_ms'] as int? ?? 0,
        passNumber: json['pass_number'] as int? ?? 1,
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
        segments: [
          for (final raw in (json['segments'] as List? ?? const []))
            if (raw is Map)
              SegmentView.fromJson(raw.cast<String, dynamic>()),
        ],
        checked: json['checked'] as bool? ?? false,
        findingSegmentId: json['finding_segment_id'] as String?,
      );

  bool get nothingTold => segments.isEmpty;
}

class SessionSnapshot {
  final String sessionId;
  final String pericope;
  final String status;
  final Coverage? coverage;
  final bool done;
  final BackTranslationProgress backTranslation;

  const SessionSnapshot({
    required this.sessionId,
    required this.pericope,
    required this.status,
    required this.coverage,
    required this.done,
    this.backTranslation = const BackTranslationProgress(),
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
      );

  bool get needsPerson => status == 'needs_person';
}
