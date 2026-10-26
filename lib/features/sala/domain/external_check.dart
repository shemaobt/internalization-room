/// The wire's kind of a **Listener's retelling**.
const listenerRetelling = 'retell';

/// The wire's kind of a **Listener**'s comment on the whole passage.
const listenerWholeComment = 'whole';

/// The wire's kind of a **Listener**'s comment on one frase.
const listenerFraseComment = 'frase';

/// One frase of the approved Version as the room's open answer lists it. The number is
/// null on a release written before frases were numbered.
class ExternalCheckFrase {
  final int? number;
  final String segmentId;
  final String? takeId;
  final int? startsMs;
  final int? endsMs;

  const ExternalCheckFrase({
    required this.segmentId,
    this.number,
    this.takeId,
    this.startsMs,
    this.endsMs,
  });

  factory ExternalCheckFrase.fromJson(Map<String, dynamic> json) =>
      ExternalCheckFrase(
        number: json['frase'] as int?,
        segmentId: json['segment_id'] as String,
        takeId: json['take_id'] as String?,
        startsMs: json['starts_ms'] as int?,
        endsMs: json['ends_ms'] as int?,
      );
}

/// The Checagem externa the room opened for the session's approved Version, with the
/// takes of its parts in the order the release packet holds them and its frases in the
/// order the room sent them.
class ExternalCheck {
  final int version;
  final List<String> takes;
  final List<ExternalCheckFrase> frases;

  const ExternalCheck({
    required this.version,
    this.takes = const [],
    this.frases = const [],
  });

  factory ExternalCheck.fromJson(Map<String, dynamic> json) => ExternalCheck(
    version: json['version'] as int,
    takes: [
      for (final part in (json['takes'] as List? ?? const []))
        (part as Map<String, dynamic>)['take_id'] as String,
    ],
    frases: [
      for (final frase in (json['frases'] as List? ?? const []))
        ExternalCheckFrase.fromJson(frase as Map<String, dynamic>),
    ],
  );
}

/// What the room holds of one **Outside listener**: whether they were finished and
/// whether their retelling is stored. Nothing of their recordings is read.
class ListenerRecord {
  final bool finished;
  final bool hasRetelling;

  const ListenerRecord({this.finished = false, this.hasRetelling = false});

  factory ListenerRecord.fromJson(Map<String, dynamic> json) => ListenerRecord(
    finished: json['finished_at'] != null,
    hasRetelling: json['retold'] == true,
  );
}
