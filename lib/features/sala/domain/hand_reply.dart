const _failuresBeforeSetAside = 2;

class HandReply {
  final String id;
  final String audioUrl;
  final bool heard;
  final int failures;

  const HandReply({
    required this.id,
    required this.audioUrl,
    this.heard = false,
    this.failures = 0,
  });

  factory HandReply.fromJson(Map<String, dynamic> json) => HandReply(
    id: json['question_id'] as String,
    audioUrl: json['audio_url'] as String? ?? '',
  );

  bool get offered => !heard && failures < _failuresBeforeSetAside;

  HandReply asHeard() =>
      HandReply(id: id, audioUrl: audioUrl, heard: true, failures: failures);

  HandReply asUnheard() =>
      HandReply(id: id, audioUrl: audioUrl, failures: failures);

  HandReply asFailed() =>
      HandReply(id: id, audioUrl: audioUrl, failures: failures + 1);
}
