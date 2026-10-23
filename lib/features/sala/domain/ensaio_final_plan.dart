import 'scene_question.dart';
import 'scene_rehearsal.dart';

/// How long the Ensaio Final plan waits on the room before the recording home opens instead,
/// her `PLAN_WAIT_MS`.
const planReadWait = Duration(seconds: 6);

/// How long a join waits on one answer of the room before its row says to try again,
/// her `JOIN_WAIT_MS`.
const joinAnswerWait = Duration(seconds: 70);

/// How long a join keeps resending quietly while the room asks it to wait, her
/// `JOIN_QUIET_MS`.
const joinQuietWait = Duration(seconds: 90);

/// The pause between two quiet resends: the ceiling of hers, since our room names none.
const joinQuietPause = Duration(seconds: 5);

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

  /// The scenes whose part came from a join, by part number, with the rehearsal it came
  /// from; [waiting] are those whose joined part is still in the Outbox.
  final Map<int, String> joined;
  final Map<int, String> waiting;

  const PlanRead({
    required this.rehearsals,
    required this.scenes,
    this.joined = const {},
    this.waiting = const {},
  });

  PlanRead withThePart(int number, String origin, JoinedPart where) {
    bool other(int n) => n != number;
    return PlanRead(
      rehearsals: rehearsals,
      scenes: scenes,
      joined: {
        for (final MapEntry(:key, :value) in joined.entries)
          if (other(key)) key: value,
        if (where == JoinedPart.landed) number: origin,
      },
      waiting: {
        for (final MapEntry(:key, :value) in waiting.entries)
          if (other(key)) key: value,
        if (where == JoinedPart.waiting) number: origin,
      },
    );
  }

  /// The same read with the room's [answered] record in place of the one it names.
  PlanRead withRehearsal(SceneRehearsalRecord answered) => PlanRead(
    rehearsals: [
      for (final rehearsal in rehearsals)
        rehearsal.rehearsalId == answered.rehearsalId ? answered : rehearsal,
    ],
    scenes: scenes,
    joined: joined,
    waiting: waiting,
  );
}

/// Where a scene's join left its part: landed as the part, still in the Outbox, or
/// nowhere.
enum JoinedPart { landed, waiting, nowhere }

/// How one scene's join ended, and where it left the part.
typedef JoinOutcome = ({JoinRow row, JoinedPart part});

/// How one scene's join ended on this visit of the plan.
enum JoinRow { joining, joined, cannotEnter, retry, notThePart }

/// One scene «juntar» joins: its number, and the rehearsal that goes up as its part.
typedef JoinStep = ({int number, SceneRehearsalRecord rehearsal, bool waiting});

/// Why a row of the plan has no rehearsal to join.
enum PlanNote { missing, cannotEnter }

/// One scene's row of the plan: its candidates, this session's rehearsals of the scene
/// with a frase, newest first, and the one chosen to join.
final class PlanRow {
  final int number;
  final Scene scene;
  final List<SceneRehearsalRecord> candidates;
  final SceneRehearsalRecord? chosen;

  /// Whether the scene's part came from a join, and whether it is still on its way.
  final bool joined;
  final bool waiting;

  const PlanRow({
    required this.number,
    required this.scene,
    required this.candidates,
    this.chosen,
    this.joined = false,
    this.waiting = false,
  });

  PlanNote? get note => switch ((candidates, chosen)) {
    _ when joined || waiting => null,
    ([], _) => PlanNote.missing,
    (_, null) => PlanNote.cannotEnter,
    _ => null,
  };

  bool get partial => chosen?.untranslatedStretch ?? false;

  /// «trocar» opens the Rehearsal sheet only where there is another joinable rehearsal
  /// to choose, and never over a joined part.
  bool get canSwap =>
      !joined && !waiting && candidates.where((c) => c.joinable).length > 1;

  /// «usar este» on a [candidate] of the sheet: a joinable one the row does not hold.
  bool offersToUse(SceneRehearsalRecord candidate) =>
      candidate.joinable && candidate.rehearsalId != chosen?.rehearsalId;
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
        read,
      ),
  ];
}

PlanRow _rowOf(
  int number,
  Scene scene,
  List<SceneRehearsalRecord> candidates,
  String? choice,
  PlanRead read,
) {
  final origin = read.joined[number] ?? read.waiting[number];
  if (origin != null) {
    return PlanRow(
      number: number,
      scene: scene,
      candidates: candidates,
      chosen: read.rehearsals.where((r) => r.rehearsalId == origin).firstOrNull,
      joined: read.joined.containsKey(number),
      waiting: !read.joined.containsKey(number),
    );
  }
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

/// Her `canJoin`: some scene has a joinable rehearsal chosen, or is already joined.
bool canJoin(List<PlanRow> rows) =>
    rows.any((row) => row.joined || row.chosen != null);

/// Her `joinQueue`: what «juntar» does, in passage order — the joined part still on its
/// way watched to its landing, and each scene with no part whose chosen rehearsal is
/// Joinable joined.
List<JoinStep> joinQueue(List<PlanRow> rows) => [
  for (final row in rows)
    if (row.chosen case final rehearsal?
        when !row.joined && (row.waiting || rehearsal.joinable))
      (number: row.number, rehearsal: rehearsal, waiting: row.waiting),
];

/// Some scene with no part still has a Joinable rehearsal chosen.
bool stillToJoin(
  PlanRead read,
  String sessionId,
  Map<String, String> choices,
) => joinQueue(
  planRowsOf(read, sessionId, choices),
).any((step) => !step.waiting);

/// What a Scene row of the recording home offers after a join: «trocar o ensaio desta
/// cena» over a joined part, «usar o ensaio desta cena» where no joined part stands, and
/// the rehearsal in use; neither while the row's take is unsent.
typedef HomeRow = ({bool swap, bool useScene, String? inUse});

/// Her `homeRow`, from the row's plan candidates, its part's origin, and whether its take
/// is still unsent.
HomeRow homeRowOf(
  PlanRead read,
  PlanRow? plan, {
  required String? origin,
  required bool held,
}) {
  final joinable = (plan?.candidates ?? const []).where((c) => c.joinable);
  final inUse = read.rehearsals.any((r) => r.rehearsalId == origin)
      ? origin
      : null;
  return (
    swap:
        !held && origin != null && joinable.any((c) => c.rehearsalId != origin),
    useScene: !held && origin == null && joinable.isNotEmpty,
    inUse: inUse,
  );
}

bool offersToSwapIn(HomeRow home, SceneRehearsalRecord rehearsal) =>
    rehearsal.joinable && rehearsal.rehearsalId != home.inUse;

String swapControl(String sceneId, SceneRehearsalRecord rehearsal) =>
    'swap:$sceneId:${rehearsal.n}';
