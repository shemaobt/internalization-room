import 'coverage.dart';

class TurnResult {
  final String sessionId;
  final String audioUrl;
  final String fixedLine;
  final String transcript;
  final bool peerCue;
  final bool usedFailSafe;
  final Coverage coverage;
  final bool done;

  const TurnResult({
    required this.sessionId,
    required this.audioUrl,
    required this.fixedLine,
    required this.transcript,
    required this.peerCue,
    required this.usedFailSafe,
    required this.coverage,
    required this.done,
  });

  factory TurnResult.fromJson(Map<String, dynamic> json) => TurnResult(
        sessionId: json['session_id'] as String,
        audioUrl: json['audio_url'] as String? ?? '',
        fixedLine: json['fixed_line'] as String? ?? '',
        transcript: json['transcript'] as String? ?? '',
        peerCue: json['peer_cue'] as bool? ?? false,
        usedFailSafe: json['used_fail_safe'] as bool? ?? false,
        coverage: Coverage.fromJson(
          (json['coverage'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        done: json['done'] as bool? ?? false,
      );
}
