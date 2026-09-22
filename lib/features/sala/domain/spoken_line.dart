class SpokenLine {
  final String url;
  final String fixedLine;

  /// The movement that came before this one, when the room opened in two.
  ///
  /// A short tap replays the scene, which is what a team asks for when it wants the part
  /// again. The whole opening — the passage's shape and then the scene — is still there
  /// under a long press, so nothing said once becomes unreachable.
  final String panoramaUrl;

  const SpokenLine({this.url = '', this.fixedLine = '', this.panoramaUrl = ''});

  bool get exists => url.isNotEmpty || fixedLine.isNotEmpty;

  bool get toldInTwoMovements => panoramaUrl.isNotEmpty && url.isNotEmpty;
}
