enum PassagemKind { passage, panorama }

class Passagem {
  final String pericope;
  final String audioUrl;
  final int beads;
  final PassagemKind kind;
  final bool approved;
  final String book;
  final String reference;

  const Passagem({
    required this.pericope,
    required this.audioUrl,
    this.beads = 0,
    this.kind = PassagemKind.passage,
    this.approved = false,
    this.book = '',
    this.reference = '',
  });

  /// The book's own entry, first in its book's block when the room lists one — never a passage,
  /// so nothing that counts passages may count this.
  bool get isPanorama => kind == PassagemKind.panorama;

  factory Passagem.fromJson(Map<String, dynamic> json, {String book = ''}) =>
      Passagem(
        pericope: json['pericope'] as String? ?? '',
        audioUrl: json['audio_url'] as String? ?? '',
        beads: json['beads'] as int? ?? 0,
        kind: json['kind'] == 'panorama'
            ? PassagemKind.panorama
            : PassagemKind.passage,
        approved: json['approved'] as bool? ?? false,
        book: book,
        reference: json['reference'] as String? ?? '',
      );
}

List<Passagem> passagensFromJson(Map<String, dynamic> json) {
  final book = json['book'] as String? ?? '';
  return [
    for (final entry in json['passages'] as List<Object?>? ?? const [])
      Passagem.fromJson(entry as Map<String, dynamic>, book: book),
  ];
}
