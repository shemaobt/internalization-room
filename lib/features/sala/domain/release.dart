class Release {
  final String releaseId;
  final int version;

  const Release({required this.releaseId, required this.version});

  factory Release.fromJson(Map<String, dynamic> json) => Release(
        releaseId: json['release_id'] as String? ?? '',
        version: json['version'] as int? ?? 0,
      );
}
