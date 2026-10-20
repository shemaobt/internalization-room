import 'channel.dart';

class LeftEntry {
  final String? pericope;
  final String? book;
  final bool panorama;
  final String? session;
  final String? language;
  final bool said;
  final Paused? held;

  const LeftEntry({
    this.pericope,
    this.book,
    this.panorama = false,
    this.session,
    this.language,
    this.said = false,
    this.held,
  });

  @override
  bool operator ==(Object other) =>
      other is LeftEntry &&
      other.pericope == pericope &&
      other.book == book &&
      other.panorama == panorama &&
      other.session == session &&
      other.language == language &&
      other.said == said &&
      other.held == held;

  @override
  int get hashCode =>
      Object.hash(pericope, book, panorama, session, language, said, held);
}
