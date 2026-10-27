/// The wire's kind of a **Listener's retelling**.
const listenerRetelling = 'retell';

/// The Checagem externa the room opened for the session's approved Version, with the
/// takes of its parts in the order the release packet holds them.
class ExternalCheck {
  final int version;
  final List<String> takes;

  const ExternalCheck({required this.version, this.takes = const []});

  factory ExternalCheck.fromJson(Map<String, dynamic> json) => ExternalCheck(
    version: json['version'] as int,
    takes: [
      for (final part in (json['takes'] as List? ?? const []))
        (part as Map<String, dynamic>)['take_id'] as String,
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
