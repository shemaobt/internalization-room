import 'coverage.dart';
import 'session_state.dart';

/// Where a telling-back stopped, as the room remembers it.
///
/// The session id lives only in memory, so every restart used to lose the retro entirely
/// and the team recorded the rehearsal again. All of this was already on the session and
/// travels with every session route; the app simply threw it away.
class BackTranslationProgress {
  final List<Trecho> trechos;

  /// The pass each stretch was told on, in the same order as [trechos].
  final List<int> passes;

  final bool checked;

  const BackTranslationProgress({
    this.trechos = const [],
    this.passes = const [],
    this.checked = false,
  });

  factory BackTranslationProgress.fromJson(Map<String, dynamic> json) {
    final spans = json['spans'] as List? ?? const [];
    return BackTranslationProgress(
      trechos: [
        for (var at = 0; at < spans.length; at++)
          if (spans[at] case final List span when span.length >= 2)
            Trecho(
              index: at + 1,
              from: Duration(milliseconds: span[0] as int),
              to: Duration(milliseconds: span[1] as int),
            ),
      ],
      passes: [
        for (final pass in (json['passes'] as List? ?? const []))
          if (pass is int) pass,
      ],
      checked: json['checked'] as bool? ?? false,
    );
  }

  bool get nothingTold => trechos.isEmpty;
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
