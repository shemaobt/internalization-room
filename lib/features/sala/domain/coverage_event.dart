enum CoverageStatus { settled, failed }

class CoverageEvent {
  final String turnId;
  final CoverageStatus status;

  const CoverageEvent({required this.turnId, required this.status});
}
