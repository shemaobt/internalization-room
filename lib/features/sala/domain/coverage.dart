class Coverage {
  final int engaged;
  final int surfaced;
  final int total;
  final int absenceIndex;
  final int beadsTotal;
  final int beadsFilled;

  const Coverage({
    required this.engaged,
    required this.surfaced,
    required this.total,
    required this.absenceIndex,
    this.beadsTotal = 12,
    this.beadsFilled = 0,
  });

  static const empty = Coverage(
    engaged: 0,
    surfaced: 0,
    total: 0,
    absenceIndex: -1,
  );

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
    engaged: json['engaged'] as int? ?? 0,
    surfaced: json['surfaced'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    absenceIndex: json['absence_index'] as int? ?? -1,
    beadsTotal: json['beads_total'] as int? ?? 12,
    beadsFilled: json['beads_filled'] as int? ?? 0,
  );
}
