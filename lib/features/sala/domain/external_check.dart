/// The Checagem externa the room opened for the session's approved Version.
class ExternalCheck {
  final int version;

  const ExternalCheck({required this.version});

  factory ExternalCheck.fromJson(Map<String, dynamic> json) =>
      ExternalCheck(version: json['version'] as int);
}
