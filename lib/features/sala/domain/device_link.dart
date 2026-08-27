class ClaimCode {
  final String deviceId;
  final String code;
  final DateTime? expiresAt;

  const ClaimCode({
    required this.deviceId,
    required this.code,
    this.expiresAt,
  });

  factory ClaimCode.fromJson(Map<String, dynamic> json) => ClaimCode(
        deviceId: json['device_id'] as String,
        code: json['code'] as String,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '')?.toUtc(),
      );

  bool ranOutBy(DateTime now) {
    final end = expiresAt;
    return end != null && !now.toUtc().isBefore(end);
  }
}

class TeamLink {
  final String projectId;
  final String? label;

  const TeamLink({required this.projectId, this.label});

  factory TeamLink.fromJson(Map<String, dynamic> json) => TeamLink(
        projectId: json['project_id'] as String,
        label: json['label'] as String?,
      );
}
