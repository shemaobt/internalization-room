import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/hand_reply.dart';
import 'device_identity.dart';
import 'room_repository.dart';
import 'shared_http_client.dart';

const _basePath = '/api/internalization-room';
const _timeout = Duration(seconds: 20);

/// A question carries up to 25 MB of the team's own voice and the room stores it before
/// answering, so it gets the same budget as the other routes that move audio — not the
/// one meant for reading a row back.
const _uploadTimeout = Duration(seconds: 90);

class HandInboxRepository {
  final http.Client _client;
  final bool _ownsClient;
  final Future<String> Function() _deviceId;

  HandInboxRepository({
    http.Client? client,
    Future<String> Function()? deviceId,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _deviceId = deviceId ?? deviceIdentity;

  http.Client get client => _client;

  String? _credential;

  /// What this tablet presents as itself from now on. The hand keeps a client and a
  /// header of its own, so the credential has to arrive here as well as at the room.
  void presents(String? credential) => _credential = credential;

  Future<Map<String, String>> get _headers async => {
    'X-Room-Key': Env.roomKey,
    'X-Room-Device': await _deviceId(),
    'X-Device-Credential': ?_credential,
  };

  Future<List<HandReply>?> fetchReplies() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('${Env.backendUrl}$_basePath/questions/replies'),
            headers: await _headers,
          )
          .timeout(_timeout);
    } on Object {
      return null;
    }
    if (response.statusCode != 200) return null;
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return [
        for (final reply in (body['replies'] as List? ?? const []))
          HandReply.fromJson((reply as Map).cast<String, dynamic>()),
      ];
    } on Object {
      return null;
    }
  }

  /// Whether the desk took it.
  ///
  /// Any 2xx is agreement, so a desk that answers "already heard" is not read as a
  /// refusal. A desk that answers that the reply moved on is one more non-2xx: the mark
  /// is taken back and the reply it now holds is offered, as any refusal already is.
  ///
  /// The mark names the clip that played, not only the question: a facilitator who
  /// re-records while the first clip is still sounding writes a new one under the same
  /// id, and a mark by id alone would stamp that second reply heard when nobody heard it.
  /// Without a clip the mark is the bare one it always was.
  Future<bool> markHeard(String replyId, {String? audioUrl}) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${Env.backendUrl}$_basePath/questions/$replyId/heard'),
            headers: {
              ...await _headers,
              if (audioUrl != null) 'Content-Type': 'application/json',
            },
            body: audioUrl == null ? null : jsonEncode({'audio_url': audioUrl}),
          )
          .timeout(_timeout);
    } on Object {
      return false;
    }
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<void> sendQuestion(String sessionId, File audio) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              '${Env.backendUrl}$_basePath/questions?session_id=$sessionId',
            ),
          )
          ..headers.addAll(await _headers)
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    final http.Response response;
    try {
      // The deadline has to cover draining the body too: wrapping only `send` left the
      // read with no limit at all, so a half-answered request hung here for good. And a
      // raw TimeoutException escaping made the caller treat a slow link as a crash.
      response = await Future(() async {
        return http.Response.fromStream(await _client.send(request));
      }).timeout(_uploadTimeout);
    } on Exception catch (error) {
      throw RoomUnavailable('$error');
    }
    if (response.statusCode != 200) {
      throw RoomUnavailable('HTTP ${response.statusCode}');
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

final handInboxRepositoryProvider = Provider<HandInboxRepository>((ref) {
  final repository = HandInboxRepository(
    client: ref.watch(sharedHttpClientProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
