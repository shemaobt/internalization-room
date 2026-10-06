class Coverage {
  final int engaged;
  final int surfaced;
  final int total;
  final int beadsTotal;
  final int beadsFilled;
  final bool beadsTold;

  const Coverage({
    required this.engaged,
    required this.surfaced,
    required this.total,
    this.beadsTotal = 12,
    this.beadsFilled = 0,
    this.beadsTold = false,
  });

  static const empty = Coverage(engaged: 0, surfaced: 0, total: 0);

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
    engaged: json['engaged'] as int? ?? 0,
    surfaced: json['surfaced'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    beadsTotal: json['beads_total'] as int? ?? 12,
    beadsFilled: json['beads_filled'] as int? ?? 0,
    beadsTold: json['beads_filled'] != null,
  );

  Coverage keepingTheBeadsOf(Coverage before) => Coverage(
    engaged: engaged,
    surfaced: surfaced,
    total: total,
    beadsTotal: before.beadsTotal,
    beadsFilled: before.beadsFilled,
    beadsTold: before.beadsTold,
  );
}
