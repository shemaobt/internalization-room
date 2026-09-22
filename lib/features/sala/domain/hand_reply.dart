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

  HandReply asHeard() => HandReply(id: id, audioUrl: audioUrl, heard: true);
}
