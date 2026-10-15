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
  final List<SceneFrase> frases;

  const SceneRehearsalRecord({
    required this.rehearsalId,
    required this.sessionId,
    required this.n,
    this.frases = const [],
  });

  factory SceneRehearsalRecord.fromJson(Map<String, dynamic> json) =>
      SceneRehearsalRecord(
        rehearsalId: json['rehearsal_id'] as String,
        sessionId: json['session_id'] as String,
        n: json['n'] as int,
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

  Iterable<SceneFrase> get _current =>
      frases.where((frase) => frase.replacedBy == null);

  /// Where the translation stopped: the end of the furthest current frase.
  Duration get frontier => Duration(
    milliseconds: _current.fold(0, (end, frase) => max(end, frase.endsMs ?? 0)),
  );
}
