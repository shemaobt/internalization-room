import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/hand_reply.dart';
import 'device_identity.dart';
import 'room_answer.dart';
import 'room_client.dart';
import 'shared_http_client.dart';

const _basePath = '/api/internalization-room';
const _timeout = Duration(seconds: 20);

/// A question carries up to 25 MB of the team's own voice and the room stores it before
/// answering, so it gets the same budget as the other routes that move audio — not the
/// one meant for reading a row back.
const _uploadTimeout = Duration(seconds: 90);

class HandInboxRepository {
  final http.Client client;
  late final http.Client _client = KeepsTheRequest(client);
  final bool _ownsClient;
  final Future<String> Function() _deviceId;
  late final RoomClient _room = RoomClient(_client);

  HandInboxRepository({
    http.Client? client,
    Future<String> Function()? deviceId,
  }) : client = client ?? http.Client(),
       _ownsClient = client == null,
       _deviceId = deviceId ?? deviceIdentity;

  Stream<String?> get revoked => _room.revoked;

  String? _credential;

  /// What this tablet presents as itself from now on. The hand keeps a client and a
  /// header of its own, so the credential has to arrive here as well as at the room.
  void presents(String? credential) => _credential = credential;

  Future<Map<String, String>> get _headers async => {
    'X-Room-Device': await _deviceId(),
    deviceCredentialHeader: ?_credential,
  };

  Future<RoomAnswer<List<HandReply>>> fetchReplies() => _room.ask(
    () async => _client.get(
      Uri.parse('${Env.backendUrl}$_basePath/questions/replies'),
      headers: await _headers,
    ),
    timeout: _timeout,
    read: readJson(
      (body) => [
        for (final reply in (body['replies'] as List? ?? const []))
          HandReply.fromJson((reply as Map).cast<String, dynamic>()),
      ],
    ),
    asksForTheSession: false,
  );

  /// Whether the desk took it.
  ///
  /// Any 2xx is agreement, so a desk that answers "already heard" is not read as a
  /// refusal. A desk that answers that the reply moved on is one more non-2xx: the mark
  /// is taken back, and the reply the desk now holds arrives with the pull a refusal
  /// asks for (`_markHeard`).
  ///
  /// The mark names the clip that played, not only the question: a facilitator who
  /// re-records while the first clip is still sounding writes a new one under the same
  /// id, and a mark by id alone would stamp that second reply heard when nobody heard it.
  /// A reply the desk served with no address is marked bare, by the question alone, as
  /// every mark was before — the desk answers and addresses a reply in one write, so it
  /// never serves one, and the bare form is a guard rather than a path.
  Future<RoomAnswer<void>> markHeard(
    String replyId, {
    required String audioUrl,
  }) => _room.ask(
    () async => _client.post(
      Uri.parse('${Env.backendUrl}$_basePath/questions/$replyId/heard'),
      headers: {
        ...await _headers,
        if (audioUrl.isNotEmpty) 'Content-Type': 'application/json',
      },
      body: audioUrl.isEmpty ? null : jsonEncode({'audio_url': audioUrl}),
    ),
    timeout: _timeout,
    read: (_) {},
    asksForTheSession: false,
  );

  Future<RoomAnswer<void>> sendQuestion(String sessionId, File audio) async =>
      _room.askStreamed(
        http.MultipartRequest(
            'POST',
            Uri.parse(
              '${Env.backendUrl}$_basePath/questions?session_id=$sessionId',
            ),
          )
          ..headers.addAll(await _headers)
          ..files.add(await http.MultipartFile.fromPath('file', audio.path)),
        timeout: _uploadTimeout,
        read: (_) {},
        asksForTheSession: true,
      );

  void dispose() {
    _room.close();
    if (_ownsClient) client.close();
  }
}

final handInboxRepositoryProvider = Provider<HandInboxRepository>((ref) {
  final repository = HandInboxRepository(
    client: ref.watch(sharedHttpClientProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
