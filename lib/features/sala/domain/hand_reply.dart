const _failedPlaysBeforeSetAside = 2;

class HandReply {
  final String id;
  final String audioUrl;
  final bool heard;
  final int failedPlays;

  const HandReply({
    required this.id,
    required this.audioUrl,
    this.heard = false,
    this.failedPlays = 0,
  });

  factory HandReply.fromJson(Map<String, dynamic> json) => HandReply(
    id: json['question_id'] as String,
    audioUrl: json['audio_url'] as String? ?? '',
  );

  bool get offered => !heard && failedPlays < _failedPlaysBeforeSetAside;

  HandReply asHeard() => HandReply(id: id, audioUrl: audioUrl, heard: true);

  HandReply asUnsounded() =>
      HandReply(id: id, audioUrl: audioUrl, failedPlays: failedPlays + 1);
}
