/// What the server answers the team's approval with.
///
/// Nothing in the room reads either field yet; the model is here to pin the wire contract,
/// so a server that stopped naming the version would be caught by the repository's own
/// test rather than by a passage that closes without one.
class Release {
  final String releaseId;
  final int version;

  const Release({required this.releaseId, required this.version});

  factory Release.fromJson(Map<String, dynamic> json) => Release(
        releaseId: json['release_id'] as String? ?? '',
        version: json['version'] as int? ?? 0,
      );
}
