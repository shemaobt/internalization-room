enum BtFindingKind { missing, addition, unclear }

BtFindingKind? btFindingKindFrom(String? raw) {
  for (final kind in BtFindingKind.values) {
    if (kind.name == raw) return kind;
  }
  return null;
}

extension BtFindingExit on BtFindingKind {
  bool get exitsByReRecording => this == BtFindingKind.addition;
}

class BackTranslationChunk {
  final int chunks;
  final bool captured;

  const BackTranslationChunk({required this.chunks, required this.captured});

  factory BackTranslationChunk.fromJson(Map<String, dynamic> json) =>
      BackTranslationChunk(
        chunks: json['chunks'] as int? ?? 0,
        captured: json['captured'] as bool? ?? false,
      );
}

class BackTranslationVerdict {
  final String audioUrl;
  final String fixedLine;
  final bool checked;
  final BtFindingKind? findingKind;
  final int findingsRemaining;
  final bool usedFailSafe;

  const BackTranslationVerdict({
    required this.audioUrl,
    required this.fixedLine,
    required this.checked,
    required this.findingKind,
    required this.findingsRemaining,
    required this.usedFailSafe,
  });

  factory BackTranslationVerdict.fromJson(Map<String, dynamic> json) =>
      BackTranslationVerdict(
        audioUrl: json['audio_url'] as String? ?? '',
        fixedLine: json['fixed_line'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        findingKind: btFindingKindFrom(json['finding_kind'] as String?),
        findingsRemaining: json['findings_remaining'] as int? ?? 0,
        usedFailSafe: json['used_fail_safe'] as bool? ?? false,
      );
}
