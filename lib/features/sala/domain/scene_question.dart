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
