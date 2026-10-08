class SpokenLine {
  final String url;
  final String fixedLine;

  const SpokenLine({this.url = '', this.fixedLine = ''});

  bool get exists => url.isNotEmpty || fixedLine.isNotEmpty;
}
