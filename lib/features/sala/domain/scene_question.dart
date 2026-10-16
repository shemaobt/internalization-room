import 'scene_rehearsal.dart';

/// One scene of the session's passage as the room names it: its id, `S<N>`, and its
/// title in the session's language, for display only.
final class Scene {
  final String sceneId;
  final String title;

  const Scene({required this.sceneId, required this.title});

  static List<Scene> listFrom(Map<String, dynamic> json) => [
    for (final scene in json['scenes'] as List<dynamic>)
      Scene(
        sceneId: scene['scene_id'] as String,
        title: scene['title'] as String,
      ),
  ];
}

/// How long the scene list is waited for: a later list is no list.
const sceneListWait = Duration(seconds: 4);

/// What the screen knows of the passage's scenes.
sealed class SceneList {
  const SceneList();

  List<Scene> get scenes => switch (this) {
    ScenesHad(:final scenes) => scenes,
    _ => const [],
  };

  /// Whether the Scene question is asked at all: two or more scenes.
  bool get asks => scenes.length > 1;

  /// The scene's place in the passage, from 1; null for no id or one the list lacks.
  int? numberOf(String? sceneId) {
    final at = scenes.indexWhere((scene) => scene.sceneId == sceneId);
    return at < 0 ? null : at + 1;
  }

  /// The button the question highlights: the [again] scene, else the first scene with no
  /// rehearsal both sent and labelled with it, else none.
  String? highlighted(List<SceneRehearsalRecord> rehearsals, {String? again}) {
    if (numberOf(again) != null) return again;
    return scenes
        .where(
          (scene) => !rehearsals.any(
            (rehearsal) =>
                rehearsal.scene == scene.sceneId && !rehearsal.unsent,
          ),
        )
        .firstOrNull
        ?.sceneId;
  }

  /// The Scene label of a take started now: the pick when the question is asked, the one
  /// scene silently, or none.
  String? labelFor(String? picked) => switch (scenes) {
    [final only] => only.sceneId,
    _ when numberOf(picked) != null => picked,
    _ => null,
  };
}

/// The ask made at the open, not yet answered.
final class ScenesAwaited extends SceneList {
  const ScenesAwaited();
}

/// No list.
final class ScenesMissing extends SceneList {
  const ScenesMissing();
}

final class ScenesHad extends SceneList {
  @override
  final List<Scene> scenes;

  const ScenesHad(this.scenes);
}
