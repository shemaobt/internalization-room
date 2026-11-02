class BackTranslationChunk {
  final int? frase;
  final String? segmentId;

  const BackTranslationChunk({this.frase, this.segmentId});

  factory BackTranslationChunk.fromJson(Map<String, dynamic> json) =>
      BackTranslationChunk(
        frase: json['frase'] as int?,
        segmentId: json['segment_id'] as String?,
      );
}

enum BtFindingKind {
  addition,
  missing,
  unclear,
  nuance,
  other;

  static BtFindingKind? fromJson(Object? raw) => switch (raw) {
    'addition' || 'silence' => BtFindingKind.addition,
    'missing' => BtFindingKind.missing,
    'unclear' => BtFindingKind.unclear,
    'nuance' => null,
    String() => BtFindingKind.other,
    _ => null,
  };
}

class BtFinding {
  final BtFindingKind? kind;
  final int? frase;
  final String? segmentId;

  const BtFinding({
    required this.kind,
    required this.frase,
    required this.segmentId,
  });

  static BtFinding? namedNuanceFrom(Map<String, dynamic> json) =>
      switch (json['named_nuance']) {
        final Map<String, dynamic> nuance => BtFinding(
          kind: BtFindingKind.nuance,
          frase: nuance['frase'] as int?,
          segmentId: nuance['segment_id'] as String?,
        ),
        _ => null,
      };

  static List<BtFinding> listFrom(Map<String, dynamic> json) => [
    for (final raw in (json['findings'] as List? ?? const []))
      if (raw is Map)
        BtFinding(
          kind: BtFindingKind.fromJson(raw['kind']),
          frase: raw['frase'] as int?,
          segmentId: raw['segment_id'] as String?,
        ),
  ];
}

enum CheckRefusal {
  fraseAwaiting,
  partUnheard,
  stretchUntranslated,
  nothingTranslated,
  notConferida,
  checkUnavailable;

  static CheckRefusal? fromJson(Object? raw) => switch (raw) {
    'FRASE_AWAITING' => CheckRefusal.fraseAwaiting,
    'PART_UNHEARD' => CheckRefusal.partUnheard,
    'STRETCH_UNTRANSLATED' => CheckRefusal.stretchUntranslated,
    'NOTHING_TRANSLATED' => CheckRefusal.nothingTranslated,
    'CHECK_UNAVAILABLE' => CheckRefusal.checkUnavailable,
    _ => null,
  };
}

class UntranslatedPart {
  final String takeId;
  final int? scene;
  final Duration from;

  const UntranslatedPart({
    required this.takeId,
    this.scene,
    this.from = Duration.zero,
  });

  static List<UntranslatedPart> listFrom(Map<String, dynamic> json) => [
    for (final parte in json['untranslated'] as List? ?? const [])
      if (parte is Map)
        UntranslatedPart(
          takeId: parte['take_id'] as String,
          scene: parte['scene'] as int?,
          from: Duration(milliseconds: parte['from_ms'] as int? ?? 0),
        ),
  ];
}

/// The listen door's answer to a report: what the room still counts unheard and, once
/// nothing is, what the room says follows (shema-api ADR 0070).
class ListenedWhole {
  /// Null when the room names nothing at all: an older room.
  final List<String>? unheardTakeIds;
  final bool automaticCheck;
  final String? fixedLine;
  final bool stretchUntranslated;
  final List<UntranslatedPart> untranslated;

  const ListenedWhole({
    this.unheardTakeIds,
    this.automaticCheck = false,
    this.fixedLine,
    this.stretchUntranslated = false,
    this.untranslated = const [],
  });

  factory ListenedWhole.fromJson(Map<String, dynamic> json) => ListenedWhole(
    unheardTakeIds: (json['unheard_take_ids'] as List?)?.cast<String>(),
    automaticCheck: json['automatic_check'] as bool? ?? false,
    fixedLine: json['fixed_line'] as String?,
    stretchUntranslated: json['refusal'] == 'STRETCH_UNTRANSLATED',
    untranslated: UntranslatedPart.listFrom(json),
  );
}

class BackTranslationVerdict {
  final String audioUrl;
  final String fixedLine;
  final bool checked;
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

  /// The parts of the rehearsal the report the team just sent does not cover, named by the
  /// recording each one was kept as.
  ///
  /// Its own field, as the untold stretch above is: the room refuses to read a passage
  /// whose rehearsal was not heard through, and it says so by naming what is missing. An
  /// empty list is a refusal that did not happen, never one this tablet worked out for
  /// itself from a silence.
  final List<String> unheardTakeIds;

  final List<BtFinding> findings;
  final int findingsRemaining;
  final bool usedFailSafe;
  final CheckRefusal? refusal;
  final String? checkAt;
  final BtFinding? namedNuance;
  final List<UntranslatedPart> untranslated;

  const BackTranslationVerdict({
    required this.audioUrl,
    required this.fixedLine,
    required this.checked,
    required this.findingSegmentId,
    this.untoldSegmentId,
    this.unheardTakeIds = const [],
    this.findings = const [],
    required this.findingsRemaining,
    required this.usedFailSafe,
    this.refusal,
    this.checkAt,
    this.namedNuance,
    this.untranslated = const [],
  });

  factory BackTranslationVerdict.fromJson(Map<String, dynamic> json) =>
      BackTranslationVerdict(
        audioUrl: json['audio_url'] as String? ?? '',
        fixedLine: json['fixed_line'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        findingSegmentId: json['finding_segment_id'] as String?,
        untoldSegmentId: json['untold_segment_id'] as String?,
        unheardTakeIds: [
          for (final nome in json['unheard_take_ids'] as List? ?? const [])
            nome as String,
        ],
        findings: BtFinding.listFrom(json),
        findingsRemaining: json['findings_remaining'] as int? ?? 0,
        usedFailSafe: json['used_fail_safe'] as bool? ?? false,
        refusal: CheckRefusal.fromJson(json['refusal']),
        checkAt: json['check_at'] as String?,
        namedNuance: BtFinding.namedNuanceFrom(json),
        untranslated: UntranslatedPart.listFrom(json),
      );
}
