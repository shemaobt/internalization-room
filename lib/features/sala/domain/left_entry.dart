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
}
