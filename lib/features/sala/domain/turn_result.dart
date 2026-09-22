import 'coverage.dart';

/// One clip of a turn the room chose to tell in more than one breath.
class SpokenSegment {
  final String role;
  final String audioUrl;

  const SpokenSegment({required this.role, required this.audioUrl});

  factory SpokenSegment.fromJson(Map<String, dynamic> json) => SpokenSegment(
    role: json['role'] as String? ?? '',
    audioUrl: json['audio_url'] as String? ?? '',
  );
}

class TurnResult {
  final String sessionId;
  final String audioUrl;
  final String fixedLine;
  final String transcript;
  final bool peerCue;
  final bool usedFailSafe;
  final bool degraded;

  /// Null when the turn carried no coverage at all — which is not the same as a passage
  /// with nothing in it. Reading a missing field as zero emptied the necklace, which is
  /// the only record of progress this team can perceive.
  final Coverage? coverage;
  final bool done;

  final String? turnId;
  final bool classificationPending;

  final String bridgeMode;

  /// The opening cut where the Guide marked it: the whole passage, then the scene and its
  /// invitation. Empty on every other turn, and `audioUrl` always holds the whole thing —
  /// so a turn whose segments are missing is simply spoken in one breath.
  final List<SpokenSegment> segments;

  const TurnResult({
    required this.sessionId,
    required this.audioUrl,
    required this.fixedLine,
    required this.transcript,
    required this.peerCue,
    required this.usedFailSafe,
    required this.degraded,
    required this.coverage,
    required this.done,
    this.turnId,
    this.classificationPending = false,
    this.bridgeMode = '',
    this.segments = const [],
  });

  String _segment(String role) {
    for (final segment in segments) {
      if (segment.role == role) return segment.audioUrl;
    }
    return '';
  }

  String get panoramaUrl => _segment('panorama');

  String get sceneUrl => _segment('scene');

  bool get toldInTwoMovements =>
      panoramaUrl.isNotEmpty && sceneUrl.isNotEmpty && fixedLine.isEmpty;

  factory TurnResult.fromJson(Map<String, dynamic> json) => TurnResult(
    sessionId: json['session_id'] as String,
    audioUrl: json['audio_url'] as String? ?? '',
    fixedLine: json['fixed_line'] as String? ?? '',
    transcript: json['transcript'] as String? ?? '',
    peerCue: json['peer_cue'] as bool? ?? false,
    usedFailSafe: json['used_fail_safe'] as bool? ?? false,
    degraded: json['degraded'] as bool? ?? false,
    coverage: json['coverage'] == null
        ? null
        : Coverage.fromJson((json['coverage'] as Map).cast<String, dynamic>()),
    done: json['done'] as bool? ?? false,
    turnId: json['turn_id'] as String?,
    classificationPending: json['classification_pending'] as bool? ?? false,
    bridgeMode: json['bridge_mode'] as String? ?? '',
    segments: [
      for (final entry in json['segments'] as List<Object?>? ?? const [])
        SpokenSegment.fromJson((entry as Map).cast<String, dynamic>()),
    ],
  );
}
