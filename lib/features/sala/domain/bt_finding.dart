enum BtFindingKind {
  missing,
  addition,
  meaningChange,
  wrongRelation,
  reorderedEvent,
  preservationViolation,
  insufficientEvidence,
  unclear,
}

const _wireNames = {
  'missing': BtFindingKind.missing,
  'addition': BtFindingKind.addition,
  'meaning_change': BtFindingKind.meaningChange,
  'wrong_relation': BtFindingKind.wrongRelation,
  'reordered_event': BtFindingKind.reorderedEvent,
  'preservation_violation': BtFindingKind.preservationViolation,
  'insufficient_evidence': BtFindingKind.insufficientEvidence,
  'unclear': BtFindingKind.unclear,
};

BtFindingKind? btFindingKindFrom(String? raw) => _wireNames[raw];

extension BtFindingExit on BtFindingKind {
  bool get exitsByReRecording =>
      this == BtFindingKind.addition ||
      this == BtFindingKind.meaningChange ||
      this == BtFindingKind.preservationViolation;
}

class BackTranslationChunk {
  final int chunks;
  final bool captured;
  final int passNumber;
  final bool needsPerson;

  const BackTranslationChunk({
    required this.chunks,
    required this.captured,
    required this.passNumber,
    required this.needsPerson,
  });

  factory BackTranslationChunk.fromJson(Map<String, dynamic> json) =>
      BackTranslationChunk(
        chunks: json['chunks'] as int? ?? 0,
        captured: json['captured'] as bool? ?? false,
        passNumber: json['pass_number'] as int? ?? 1,
        needsPerson: json['needs_person'] as bool? ?? false,
      );
}

class BackTranslationRestart {
  final bool needsPerson;

  const BackTranslationRestart({required this.needsPerson});

  factory BackTranslationRestart.fromJson(Map<String, dynamic> json) =>
      BackTranslationRestart(
        needsPerson: json['needs_person'] as bool? ?? false,
      );
}

class BackTranslationVerdict {
  final String audioUrl;
  final String fixedLine;
  final bool checked;
  final BtFindingKind? findingKind;
  final String? findingSegmentId;

  /// The stretch the team recorded in the mother tongue and never told back, when that is
  /// what stopped the reading.
  ///
  /// Its own address rather than [findingSegmentId], and the two are never both named: a
  /// finding is a stretch the team told and the analyst has a correction about, and this
  /// is a stretch with no telling at all. Reading one from the absence of the other is
  /// the inference that cost a team their morning — with no address the app had one move
  /// left, sending them back to the rehearsal, which threw away every recording of the
  /// passage.
  final String? untoldSegmentId;
  final int findingsRemaining;
  final bool usedFailSafe;

  const BackTranslationVerdict({
    required this.audioUrl,
    required this.fixedLine,
    required this.checked,
    required this.findingKind,
    required this.findingSegmentId,
    this.untoldSegmentId,
    required this.findingsRemaining,
    required this.usedFailSafe,
  });

  factory BackTranslationVerdict.fromJson(Map<String, dynamic> json) =>
      BackTranslationVerdict(
        audioUrl: json['audio_url'] as String? ?? '',
        fixedLine: json['fixed_line'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        findingKind: btFindingKindFrom(json['finding_kind'] as String?),
        findingSegmentId: json['finding_segment_id'] as String?,
        untoldSegmentId: json['untold_segment_id'] as String?,
        findingsRemaining: json['findings_remaining'] as int? ?? 0,
        usedFailSafe: json['used_fail_safe'] as bool? ?? false,
      );
}
