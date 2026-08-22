class Passagem {
  final String pericope;
  final String audioUrl;

  const Passagem({required this.pericope, required this.audioUrl});

  factory Passagem.fromJson(Map<String, dynamic> json) => Passagem(
        pericope: json['pericope'] as String? ?? '',
        audioUrl: json['audio_url'] as String? ?? '',
      );
}

List<Passagem> passagensFromJson(Map<String, dynamic> json) => [
      for (final entry in json['passages'] as List<Object?>? ?? const [])
        Passagem.fromJson(entry as Map<String, dynamic>),
    ];
