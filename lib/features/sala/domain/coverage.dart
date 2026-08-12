class Coverage {
  final int engaged;
  final int surfaced;
  final int total;
  final int absenceIndex;

  const Coverage({
    required this.engaged,
    required this.surfaced,
    required this.total,
    required this.absenceIndex,
  });

  static const empty = Coverage(engaged: 0, surfaced: 0, total: 0, absenceIndex: -1);

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
        engaged: json['engaged'] as int? ?? 0,
        surfaced: json['surfaced'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        absenceIndex: json['absence_index'] as int? ?? -1,
      );

  bool isAbsence(int index) => index == absenceIndex;
}
