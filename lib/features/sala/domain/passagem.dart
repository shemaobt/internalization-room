class Passagem {
  final String pericope;
  final String audioUrl;
  final int beads;
  final int absenceIndex;

  const Passagem({
    required this.pericope,
    required this.audioUrl,
    this.beads = 0,
    this.absenceIndex = -1,
  });

  factory Passagem.fromJson(Map<String, dynamic> json) => Passagem(
        pericope: json['pericope'] as String? ?? '',
        audioUrl: json['audio_url'] as String? ?? '',
        beads: json['beads'] as int? ?? 0,
        absenceIndex: json['absence_index'] as int? ?? -1,
      );
}

List<Passagem> passagensFromJson(Map<String, dynamic> json) => [
      for (final entry in json['passages'] as List<Object?>? ?? const [])
        Passagem.fromJson(entry as Map<String, dynamic>),
    ];
