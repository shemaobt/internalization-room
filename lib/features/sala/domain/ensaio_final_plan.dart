import 'scene_question.dart';
import 'scene_rehearsal.dart';

/// How long the Ensaio Final plan waits on the room before the recording home opens instead,
/// her `PLAN_WAIT_MS`.
const planReadWait = Duration(seconds: 6);

/// The room's answer the Ensaio Final plan is drawn from.
sealed class EnsaioFinalPlan {
  const EnsaioFinalPlan();
}

/// «pensando…»: the room has not answered yet.
final class PlanAwaited extends EnsaioFinalPlan {
  const PlanAwaited();
}

/// Every session's scene rehearsals of the passage, each naming its own, and its scenes.
final class PlanRead extends EnsaioFinalPlan {
  final List<SceneRehearsalRecord> rehearsals;
  final List<Scene> scenes;

  const PlanRead({required this.rehearsals, required this.scenes});
}

/// Why a row of the plan has no rehearsal to join.
enum PlanNote { missing, cannotEnter }

/// One scene's row of the plan: its candidates, this session's rehearsals of the scene
/// with a frase, newest first, and the one chosen to join.
final class PlanRow {
  final int number;
  final Scene scene;
  final List<SceneRehearsalRecord> candidates;
  final SceneRehearsalRecord? chosen;

  const PlanRow({
    required this.number,
    required this.scene,
    required this.candidates,
    this.chosen,
  });

  PlanNote? get note => switch ((candidates, chosen)) {
    ([], _) => PlanNote.missing,
    (_, null) => PlanNote.cannotEnter,
    _ => null,
  };

  bool get partial => chosen?.untranslatedStretch ?? false;

  bool get canSwap => candidates.length > 1;

  /// Her `nextChoice`, kept to the joinable: the next joinable candidate after the chosen
  /// one, newest first, round and round.
  SceneRehearsalRecord? get next {
    final joinable = candidates.where((c) => c.joinable).toList();
    if (joinable.isEmpty) return null;
    final at = joinable.indexWhere((c) => c.rehearsalId == chosen?.rehearsalId);
    return joinable[(at + 1) % joinable.length];
  }
}

/// The plan's rows in passage order; [choices] maps a scene to the rehearsal the team
/// chose for it, which stands while it is still a joinable candidate.
List<PlanRow> planRowsOf(
  PlanRead read,
  String sessionId,
  Map<String, String> choices,
) {
  final ours = SceneRehearsalRecord.ofTheSession(read.rehearsals, sessionId);
  return [
    for (final (i, scene) in read.scenes.indexed)
      _rowOf(
        i + 1,
        scene,
        ours
            .where((r) => r.scene == scene.sceneId && r.translatedFrases > 0)
            .toList()
            .reversed
            .toList(),
        choices[scene.sceneId],
      ),
  ];
}

PlanRow _rowOf(
  int number,
  Scene scene,
  List<SceneRehearsalRecord> candidates,
  String? choice,
) {
  final joinable = candidates.where((c) => c.joinable).toList();
  final chosen =
      joinable.where((c) => c.rehearsalId == choice).firstOrNull ??
      _theDefault(joinable);
  return PlanRow(
    number: number,
    scene: scene,
    candidates: candidates,
    chosen: chosen,
  );
}

/// The Default rehearsal: the joinable one the voice received last, ties to the higher
/// number.
SceneRehearsalRecord? _theDefault(List<SceneRehearsalRecord> joinable) {
  final received =
      [
        for (final r in joinable)
          if (DateTime.tryParse(r.sentAt!) case final at?)
            (at: at, rehearsal: r),
      ]..sort(
        (a, b) => switch (b.at.compareTo(a.at)) {
          0 => b.rehearsal.n.compareTo(a.rehearsal.n),
          final order => order,
        },
      );
  return received.firstOrNull?.rehearsal;
}

/// Her `planHasRehearsals`: this session holds a rehearsal with a frase, labelled with a
/// scene of the passage or not.
bool planHoldsARehearsal(PlanRead read, String sessionId) => read.rehearsals
    .any((r) => r.sessionId == sessionId && r.translatedFrases > 0);

/// Nothing of this session holds a frase, and another session of the passage, the other
/// language's, holds a sent rehearsal.
bool rehearsalsElsewhere(List<SceneRehearsalRecord> listed, String sessionId) =>
    !listed.any((r) => r.sessionId == sessionId && r.translatedFrases > 0) &&
    listed.any((r) => r.sessionId != sessionId && !r.unsent);

/// Her `canJoin`: some scene has a joinable rehearsal chosen.
bool canJoin(List<PlanRow> rows) => rows.any((row) => row.chosen != null);
