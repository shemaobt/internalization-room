import 'dart:math';

/// One frase of a scene rehearsal: its place in the take, and what replaced it.
final class SceneFrase {
  final String fraseId;
  final int? startsMs;
  final int? endsMs;
  final String? replacedBy;

  const SceneFrase({
    required this.fraseId,
    this.startsMs,
    this.endsMs,
    this.replacedBy,
  });
}

/// A scene rehearsal as the room keeps it for any tablet of the team, with no words.
final class SceneRehearsalRecord {
  final String rehearsalId;
  final String sessionId;
  final int n;
  final String? sentAt;
  final String? afterRestart;
  final List<SceneFrase> frases;

  const SceneRehearsalRecord({
    required this.rehearsalId,
    required this.sessionId,
    required this.n,
    this.sentAt,
    this.afterRestart,
    this.frases = const [],
  });

  factory SceneRehearsalRecord.fromJson(Map<String, dynamic> json) =>
      SceneRehearsalRecord(
        rehearsalId: json['rehearsal_id'] as String,
        sessionId: json['session_id'] as String,
        n: json['n'] as int,
        sentAt: json['sent_at'] as String?,
        afterRestart: json['after_restart'] as String?,
        frases: [
          for (final frase in json['frases'] as List<dynamic>)
            SceneFrase(
              fraseId: frase['frase_id'] as String,
              startsMs: frase['starts_ms'] as int?,
              endsMs: frase['ends_ms'] as int?,
              replacedBy: frase['replaced_by'] as String?,
            ),
        ],
      );

  static List<SceneRehearsalRecord> listFrom(Map<String, dynamic> json) => [
    for (final rehearsal in json['scene_rehearsals'] as List<dynamic>)
      SceneRehearsalRecord.fromJson(rehearsal as Map<String, dynamic>),
  ];

  /// The newest rehearsal of [sessionId], when it is not yet sent: the one the screen
  /// reopens. An older unsent one under it is abandoned.
  static SceneRehearsalRecord? toReopen(
    List<SceneRehearsalRecord> listed,
    String sessionId,
  ) {
    SceneRehearsalRecord? newest;
    for (final rehearsal in listed) {
      if (rehearsal.sessionId != sessionId) continue;
      if (newest == null || rehearsal.n > newest.n) newest = rehearsal;
    }
    return newest != null && newest.unsent ? newest : null;
  }

  bool get unsent => sentAt == null;

  Iterable<SceneFrase> get _current =>
      frases.where((frase) => frase.replacedBy == null);

  /// Where the translation stopped: the end of the furthest current frase.
  Duration get frontier => Duration(
    milliseconds: _current.fold(0, (end, frase) => max(end, frase.endsMs ?? 0)),
  );

  /// Whether every current frase has a place inside [take], the length of the
  /// recording this tablet holds.
  bool placesKnownIn(Duration? take) => _current.every(
    (frase) => switch ((frase.startsMs, frase.endsMs, take)) {
      (final int starts, final int ends, final Duration take) =>
        starts >= 0 && ends > starts && ends <= take.inMilliseconds,
      _ => false,
    },
  );
}
