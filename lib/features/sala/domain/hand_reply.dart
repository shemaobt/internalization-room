class HandReply {
  final String id;
  final String audioUrl;
  final bool heard;

  const HandReply({
    required this.id,
    required this.audioUrl,
    this.heard = false,
  });

  factory HandReply.fromJson(Map<String, dynamic> json) => HandReply(
    id: json['question_id'] as String,
    audioUrl: json['audio_url'] as String? ?? '',
  );

  bool get offered => !heard;

  HandReply asHeard() => HandReply(id: id, audioUrl: audioUrl, heard: true);

  HandReply asUnheard() => HandReply(id: id, audioUrl: audioUrl);
}
