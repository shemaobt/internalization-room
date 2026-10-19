class SpokenLine {
  final String url;
  final String fixedLine;
  final String? checkAt;

  const SpokenLine({this.url = '', this.fixedLine = '', this.checkAt});

  bool get exists => url.isNotEmpty || fixedLine.isNotEmpty;
}
