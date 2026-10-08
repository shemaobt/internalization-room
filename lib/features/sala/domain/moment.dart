enum MomentAt { familiarization, internalization, articulation, ensaioFinal }

class Moment {
  final MomentAt at;
  final int part;
  final int parts;

  const Moment({required this.at, this.part = 0, required this.parts});

  static Moment? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = switch (json['at']) {
      'familiarization' => MomentAt.familiarization,
      'internalization' => MomentAt.internalization,
      'articulation' => MomentAt.articulation,
      'ensaio_final' => MomentAt.ensaioFinal,
      _ => null,
    };
    if (at == null) return null;
    return Moment(
      at: at,
      part: json['part'] as int? ?? 0,
      parts: json['parts'] as int? ?? 0,
    );
  }
}
