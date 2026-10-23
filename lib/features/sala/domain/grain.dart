/// How the team records the passage: the whole at once, or scene by scene.
enum Grain {
  whole('whole'),
  scene('scene');

  final String wire;

  const Grain(this.wire);

  static Grain? fromWire(Object? wire) =>
      values.where((grain) => grain.wire == wire).firstOrNull;
}
