import 'coverage.dart';

class TurnResult {
  final String sessionId;
  final String audioUrl;
  final String fixedLine;
  final String transcript;
  final bool peerCue;
  final bool usedFailSafe;
  /// Null when the turn carried no coverage at all — which is not the same as a passage
  /// with nothing in it. Reading a missing field as zero emptied the necklace, which is
  /// the only record of progress this team can perceive.
  final Coverage? coverage;
  final bool done;

  final String bridgeMode;

  const TurnResult({
    required this.sessionId,
    required this.audioUrl,
    required this.fixedLine,
    required this.transcript,
    required this.peerCue,
    required this.usedFailSafe,
    required this.coverage,
    required this.done,
    this.bridgeMode = '',
  });

  factory TurnResult.fromJson(Map<String, dynamic> json) => TurnResult(
        sessionId: json['session_id'] as String,
        audioUrl: json['audio_url'] as String? ?? '',
        fixedLine: json['fixed_line'] as String? ?? '',
        transcript: json['transcript'] as String? ?? '',
        peerCue: json['peer_cue'] as bool? ?? false,
        usedFailSafe: json['used_fail_safe'] as bool? ?? false,
        coverage: json['coverage'] == null
            ? null
            : Coverage.fromJson(
                (json['coverage'] as Map).cast<String, dynamic>(),
              ),
        done: json['done'] as bool? ?? false,
        bridgeMode: json['bridge_mode'] as String? ?? '',
      );
}
