/// Where the team cut the Guide off: [at] how far into her line, and [of] how long the
/// line was, when the player knew it.
final class CutPoint {
  final Duration at;
  final Duration? of;

  const CutPoint(this.at, this.of);

  @override
  bool operator ==(Object other) =>
      other is CutPoint && other.at == at && other.of == of;

  @override
  int get hashCode => Object.hash(at, of);
}
