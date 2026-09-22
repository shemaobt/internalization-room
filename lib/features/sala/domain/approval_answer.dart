/// What the server answers the team's approval with: the version it minted, or the holes
/// standing in the way of one.
///
/// Both are the same status, and the tablet tells them apart by the field that is there
/// rather than by the one that is missing — a version says a release exists, blockers say
/// which holes stand, and a body that says neither is an answer this tablet does not know.
/// Read the other way round, a server that stopped naming the version closed a passage
/// over nothing.
class ApprovalAnswer {
  /// The row the server kept for this approval. Nothing in the room reads it; it is here to
  /// pin the wire contract, so a server that stopped naming it is caught by the
  /// repository's own test rather than by a passage that closes without one.
  final String? releaseId;

  /// The version the team won by approving, and the whole of what says a release exists.
  final int? version;

  /// The holes standing between this passage and its release, one code each, in the order
  /// the gate raised them — which is not the order the room opens its doors in.
  final List<String> blockers;

  /// Which current parts carry nobody's words, when `untold_part` is among the blockers;
  /// empty otherwise, never a list this tablet worked out for itself from a silence.
  final List<String> untoldTakeIds;

  /// Which parts of the rehearsal the team's report does not cover, when
  /// `playback_did_not_cover_the_clip` is among the blockers.
  final List<String> unheardTakeIds;

  /// The stretch recorded and never told back, when `untold_stretch` is among them.
  final String? untoldSegmentId;

  const ApprovalAnswer({
    this.releaseId,
    this.version,
    this.blockers = const [],
    this.untoldTakeIds = const [],
    this.unheardTakeIds = const [],
    this.untoldSegmentId,
  });

  bool get minted => version != null;

  factory ApprovalAnswer.fromJson(Map<String, dynamic> json) => ApprovalAnswer(
    releaseId: json['release_id'] as String?,
    version: json['version'] as int?,
    blockers: [
      for (final codigo in json['blockers'] as List? ?? const [])
        codigo as String,
    ],
    untoldTakeIds: [
      for (final nome in json['untold_take_ids'] as List? ?? const [])
        nome as String,
    ],
    unheardTakeIds: [
      for (final nome in json['unheard_take_ids'] as List? ?? const [])
        nome as String,
    ],
    untoldSegmentId: json['untold_segment_id'] as String?,
  );
}
