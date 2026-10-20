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

  /// Whether this frase has a place inside [take], the length of the recording this
  /// tablet holds.
  bool placedIn(Duration? take) => switch ((startsMs, endsMs, take)) {
    (final int starts, final int ends, final Duration take) =>
      starts >= 0 && ends > starts && ends <= take.inMilliseconds,
    _ => false,
  };

  /// How long this frase is in [take], or nought for one with no place in it.
  int spanIn(Duration? take) => placedIn(take) ? endsMs! - startsMs! : 0;
}

/// A scene rehearsal as the room keeps it for any tablet of the team, with no words.
final class SceneRehearsalRecord {
  final String rehearsalId;
  final String sessionId;
  final int n;
  final String? scene;
  final DateTime? recordedAt;
  final String? sentAt;
  final String? afterRestart;
  final int? durationMs;
  final List<SceneFrase> frases;

  const SceneRehearsalRecord({
    required this.rehearsalId,
    required this.sessionId,
    required this.n,
    this.scene,
    this.recordedAt,
    this.sentAt,
    this.afterRestart,
    this.durationMs,
    this.frases = const [],
  });

  factory SceneRehearsalRecord.fromJson(Map<String, dynamic> json) =>
      SceneRehearsalRecord(
        rehearsalId: json['rehearsal_id'] as String,
        sessionId: json['session_id'] as String,
        n: json['n'] as int,
        scene: json['scene'] as String?,
        recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? ''),
        sentAt: json['sent_at'] as String?,
        afterRestart: json['after_restart'] as String?,
        durationMs: json['duration_ms'] as int?,
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

  /// This session's rehearsals, by number: the list door names every session of the
  /// passage.
  static List<SceneRehearsalRecord> ofTheSession(
    List<SceneRehearsalRecord> listed,
    String sessionId,
  ) =>
      listed.where((rehearsal) => rehearsal.sessionId == sessionId).toList()
        ..sort((a, b) => a.n.compareTo(b.n));

  /// A list the room answered, laid over the rows [held]: a row is never dropped, and
  /// a sent rehearsal never goes back to unsent, whatever an older answer says.
  static List<SceneRehearsalRecord> listedOver(
    List<SceneRehearsalRecord> held,
    List<SceneRehearsalRecord> listed,
    String sessionId,
  ) {
    final rows = {for (final row in held) row.rehearsalId: row};
    for (final row in ofTheSession(listed, sessionId)) {
      final before = rows[row.rehearsalId];
      if (before == null || before.unsent || !row.unsent) {
        rows[row.rehearsalId] = row;
      }
    }
    return ofTheSession(rows.values.toList(), sessionId);
  }

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

  /// The scene's number, from a label `S<N>`; null for no label or any other shape.
  int? get sceneNumber => switch (RegExp(r'^S(\d+)$').firstMatch(scene ?? '')) {
    final match? => int.tryParse(match.group(1)!),
    null => null,
  };

  int get translatedFrases => _current.length;

  /// The current frases in the order they sit in the take.
  List<SceneFrase> get currentFrases => _current.toList()
    ..sort((a, b) => (a.startsMs ?? 1 << 31).compareTo(b.startsMs ?? 1 << 31));

  Iterable<SceneFrase> get _current =>
      frases.where((frase) => frase.replacedBy == null);

  /// Where the translation stopped: the end of the furthest current frase.
  Duration get frontier => Duration(
    milliseconds: _current.fold(0, (end, frase) => max(end, frase.endsMs ?? 0)),
  );

  /// Whether every current frase has a place inside [take], the length of the
  /// recording this tablet holds.
  bool placesKnownIn(Duration? take) =>
      _current.every((frase) => frase.placedIn(take));
}
