import 'scene_question.dart';
import 'scene_rehearsal.dart';

/// How long the Ensaio Final plan waits on the room before the recording home opens instead,
/// her `PLAN_WAIT_MS`.
const planReadWait = Duration(seconds: 6);

/// The room's answer the Ensaio Final plan is drawn from.
sealed class EnsaioFinalPlan {
  const EnsaioFinalPlan();
}

/// One tap of a plan row's play: only the newest one is ever heard.
final class PlanListen {
  final String rehearsalId;

  PlanListen(this.rehearsalId);
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

  /// The same read with the room's [answered] record in place of the one it names.
  PlanRead withRehearsal(SceneRehearsalRecord answered) => PlanRead(
    rehearsals: [
      for (final rehearsal in rehearsals)
        rehearsal.rehearsalId == answered.rehearsalId ? answered : rehearsal,
    ],
    scenes: scenes,
  );
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

  /// «trocar» opens the Rehearsal sheet only where there is another joinable rehearsal
  /// to choose.
  bool get canSwap => candidates.where((c) => c.joinable).length > 1;
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
          ..sort((a, b) => b.n.compareTo(a.n)),
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
SceneRehearsalRecord? _theDefault(List<SceneRehearsalRecord> joinable) =>
    (List.of(joinable)..sort(
          (a, b) => switch (b.receivedAt!.compareTo(a.receivedAt!)) {
            0 => b.n.compareTo(a.n),
            final order => order,
          },
        ))
        .firstOrNull;

/// This session's Unlabelled rehearsals, oldest first: each holds a frase and no Scene
/// label of the passage.
List<SceneRehearsalRecord> unlabelledRehearsalsOf(
  PlanRead read,
  String sessionId,
) {
  final scenes = {for (final scene in read.scenes) scene.sceneId};
  return SceneRehearsalRecord.ofTheSession(
    read.rehearsals,
    sessionId,
  ).where((r) => r.translatedFrases > 0 && !scenes.contains(r.scene)).toList();
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
