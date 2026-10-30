import 'session_snapshot.dart';

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
  /// the gate raised them — which is not the order the room reads them in.
  final List<String> blockers;

  const ApprovalAnswer({
    this.releaseId,
    this.version,
    this.blockers = const [],
  });

  bool get minted => version != null;

  /// This answer to a press over [standing]. A room that answers a press over a forced
  /// version with that same version kept it because a blocker still stands, and names
  /// none: a body that says neither, not a new approval (ADR 0150).
  ApprovalAnswer over(ApprovedDraft? standing) =>
      standing != null && standing.forced && version == standing.version
      ? const ApprovalAnswer()
      : this;

  factory ApprovalAnswer.fromJson(Map<String, dynamic> json) => ApprovalAnswer(
    releaseId: json['release_id'] as String?,
    version: json['version'] as int?,
    blockers: [
      for (final codigo in json['blockers'] as List? ?? const [])
        codigo as String,
    ],
  );
}
