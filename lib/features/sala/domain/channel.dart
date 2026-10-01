import 'package:flutter/foundation.dart';

enum MicOwner { conversation, rehearsal, capture, question }

enum MicOutcome { kept, discarded }

enum LineKind {
  guide,
  acknowledgement,
  reply,
  offlineNotice,
  stranded,
  micBlocked,
  approved,
}

final class Source {
  final String key;
  final bool counts;

  const Source._(this.key, {this.counts = true});

  static const guide = Source._('guide');

  const Source.take(String path) : this._('take:$path');

  const Source.segment(String id) : this._('segment:$id');

  const Source.reply(String id) : this._('reply:$id', counts: false);

  const Source.aside(String key) : this._('aside:$key', counts: false);

  @override
  bool operator ==(Object other) =>
      other is Source && other.key == key && other.counts == counts;

  @override
  int get hashCode => Object.hash(key, counts);
}

final class Line {
  final LineKind kind;
  final int id;
  final Source source;

  const Line(this.kind, this.id, {this.source = Source.guide});

  @override
  bool operator ==(Object other) =>
      other is Line &&
      other.kind == kind &&
      other.id == id &&
      other.source == source;

  @override
  int get hashCode => Object.hash(kind, id, source);
}

sealed class Sound {
  final String path;
  final Duration from;
  final Duration? to;

  const Sound(this.path, this.from, this.to);

  Source get source;
}

final class PartSound extends Sound {
  final int part;

  const PartSound(
    this.part,
    String path, {
    Duration from = Duration.zero,
    Duration? to,
  }) : super(path, from, to);

  @override
  Source get source => Source.take(path);

  @override
  bool operator ==(Object other) =>
      other is PartSound &&
      other.part == part &&
      other.path == path &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(part, path, from, to);
}

final class StretchSound extends Sound {
  final String segment;
  final bool telling;

  const StretchSound(
    this.segment,
    String path, {
    Duration from = Duration.zero,
    Duration? to,
    this.telling = false,
  }) : super(path, from, to);

  @override
  Source get source => Source.segment(segment);

  @override
  bool operator ==(Object other) =>
      other is StretchSound &&
      other.segment == segment &&
      other.path == path &&
      other.from == from &&
      other.to == to &&
      other.telling == telling;

  @override
  int get hashCode => Object.hash(segment, path, from, to, telling);
}

sealed class Channel {
  const Channel();
}

final class Silence extends Channel {
  const Silence();

  @override
  bool operator ==(Object other) => other is Silence;

  @override
  int get hashCode => 0;
}

final class Microphone extends Channel {
  final MicOwner owner;
  final Paused? held;

  const Microphone(this.owner, {this.held});

  @override
  bool operator ==(Object other) =>
      other is Microphone && other.owner == owner && other.held == held;

  @override
  int get hashCode => Object.hash(owner, held);
}

final class GuideSpeaking extends Channel {
  final Line line;
  final Paused? held;

  const GuideSpeaking(this.line, {this.held});

  @override
  bool operator ==(Object other) =>
      other is GuideSpeaking && other.line == line && other.held == held;

  @override
  int get hashCode => Object.hash(line, held);
}

sealed class Playing extends Channel {
  final bool opened;
  final List<Sound> next;
  final Paused? held;

  const Playing({this.opened = false, this.next = const [], this.held});

  Sound get sound;

  Duration? get head => opened ? null : sound.from;
}

final class PartPlaying extends Playing {
  final PartSound part;

  const PartPlaying(this.part, {super.opened, super.next, super.held});

  @override
  Sound get sound => part;

  @override
  bool operator ==(Object other) =>
      other is PartPlaying &&
      other.part == part &&
      other.opened == opened &&
      other.held == held &&
      listEquals(other.next, next);

  @override
  int get hashCode => Object.hash(part, opened, held, Object.hashAll(next));
}

final class StretchPlaying extends Playing {
  final StretchSound stretch;

  const StretchPlaying(this.stretch, {super.opened, super.next, super.held});

  @override
  Sound get sound => stretch;

  @override
  Duration? get head => opened ? null : Duration.zero;

  @override
  bool operator ==(Object other) =>
      other is StretchPlaying &&
      other.stretch == stretch &&
      other.opened == opened &&
      other.held == held &&
      listEquals(other.next, next);

  @override
  int get hashCode => Object.hash(stretch, opened, held, Object.hashAll(next));
}

final class Paused extends Channel {
  final Sound what;
  final List<Sound> next;
  final bool started;
  final bool opened;
  final Paused? held;

  const Paused(
    this.what, {
    this.next = const [],
    this.started = true,
    this.opened = true,
    this.held,
  });

  Duration? get head => started && opened ? null : what.from;

  @override
  bool operator ==(Object other) =>
      other is Paused &&
      other.what == what &&
      other.started == started &&
      other.opened == opened &&
      other.held == held &&
      listEquals(other.next, next);

  @override
  int get hashCode =>
      Object.hash(what, started, opened, held, Object.hashAll(next));
}
