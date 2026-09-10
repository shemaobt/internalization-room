enum PassagemKind { passage, panorama }

class Passagem {
  final String pericope;
  final String audioUrl;
  final int beads;
  final int absenceIndex;
  final PassagemKind kind;

  const Passagem({
    required this.pericope,
    required this.audioUrl,
    this.beads = 0,
    this.absenceIndex = -1,
    this.kind = PassagemKind.passage,
  });

  /// The book's own spoke, first on the wheel when the room offers one — never a passage,
  /// so nothing that counts passages may count this.
  bool get isPanorama => kind == PassagemKind.panorama;

  factory Passagem.fromJson(Map<String, dynamic> json) => Passagem(
        pericope: json['pericope'] as String? ?? '',
        audioUrl: json['audio_url'] as String? ?? '',
        beads: json['beads'] as int? ?? 0,
        absenceIndex: json['absence_index'] as int? ?? -1,
        kind: json['kind'] == 'panorama'
            ? PassagemKind.panorama
            : PassagemKind.passage,
      );
}

List<Passagem> passagensFromJson(Map<String, dynamic> json) => [
      for (final entry in json['passages'] as List<Object?>? ?? const [])
        Passagem.fromJson(entry as Map<String, dynamic>),
    ];
