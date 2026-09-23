import 'coverage.dart';

enum CoverageStatus { settled, failed }

class CoverageEvent {
  final String turnId;
  final CoverageStatus status;
  final Coverage? coverage;

  const CoverageEvent({
    required this.turnId,
    required this.status,
    this.coverage,
  });
}
