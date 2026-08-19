import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/bt_finding.dart';
import '../domain/passagem.dart';
import '../domain/session_snapshot.dart';
import '../domain/turn_result.dart';
import 'device_identity.dart';

const _basePath = '/api/internalization-room';
const _turnTimeout = Duration(seconds: 90);
const _stateTimeout = Duration(seconds: 20);

class RoomUnavailable implements Exception {
  final String reason;

  const RoomUnavailable(this.reason);

  @override
  String toString() => 'RoomUnavailable: $reason';
}

/// The room was reached and did not answer in time.
///
/// Not the same as not reaching it, and it used to be: both arrived as `RoomUnavailable`
/// and the room told the team the internet was gone. A server thinking too long is a
/// server that is there — waiting and touching again is the answer, not a cloud with a
/// line through it.
class RoomSlow implements Exception {
  const RoomSlow();

  @override
  String toString() => 'RoomSlow';
}

class RoomBroke implements Exception {
  final String reason;

  const RoomBroke(this.reason);

  @override
  String toString() => 'RoomBroke: $reason';
}

class RoomRefused implements Exception {
  const RoomRefused();
}

class SessionGone implements Exception {
  const SessionGone();
}

class RoomRepository {
  final http.Client _client;

  RoomRepository({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Room-Key': Env.roomKey,
      };

  Uri _uri(String path) => Uri.parse('${Env.backendUrl}$_basePath$path');

  Future<SessionSnapshot> createSession({
    String? pericope,
    String? afterSession,
    String? bridgeMode,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions'),
        headers: _headers,
        body: jsonEncode({
          'pericope': ?pericope,
          'after_session': ?afterSession,
          'bridge_mode': ?bridgeMode,
        }),
      ),
      _stateTimeout,
    );
    return _read(response, SessionSnapshot.fromJson);
  }

  /// The passages of a book, each with the line that names it aloud.
  ///
  /// This gets the turn budget, not the state one: the route walks every passage of the
  /// book and synthesizes a line for each, so it is generative work wearing the shape of
  /// a read. Twenty seconds turned a room that was still working into "the internet is
  /// gone" — spoken, to a team that cannot read the difference.
  Future<List<Passagem>> passagesOf(String book) async {
    final response = await _send(
      () => _client.get(_uri('/books/$book/passages'), headers: _headers),
      _turnTimeout,
    );
    return _read(response, passagensFromJson);
  }

  Future<SessionSnapshot> fetchState(String sessionId) async {
    final response = await _send(
      () => _client.get(_uri('/sessions/$sessionId'), headers: _headers),
      _stateTimeout,
    );
    return _read(response, SessionSnapshot.fromJson);
  }

  Future<TurnResult> openSession(String sessionId) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/turns'),
        headers: {'X-Room-Key': Env.roomKey},
      ),
      _turnTimeout,
    );
    return _read(response, TurnResult.fromJson);
  }

  Future<TurnResult> sendTurn(String sessionId, File audio) async {
    final request = http.MultipartRequest('POST', _uri('/sessions/$sessionId/turns'))
      ..headers['X-Room-Key'] = Env.roomKey
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    return _read(await _sendMultipart(request), TurnResult.fromJson);
  }

  Future<BackTranslationChunk> sendChunk(
    String sessionId,
    File audio, {
    Duration? from,
    Duration? to,
    bool retelling = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/sessions/$sessionId/back-translation/chunks'),
    )
      ..headers['X-Room-Key'] = Env.roomKey
      ..headers['X-Room-Device'] = await deviceIdentity()
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (from != null) request.fields['starts_ms'] = '${from.inMilliseconds}';
    if (to != null) request.fields['ends_ms'] = '${to.inMilliseconds}';
    if (retelling) request.fields['retelling'] = 'true';
    return _read(await _sendMultipart(request), BackTranslationChunk.fromJson);
  }

  Future<void> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/sessions/$sessionId/takes'))
      ..headers['X-Room-Key'] = Env.roomKey
      ..headers['X-Room-Device'] = await deviceIdentity()
      ..fields['kind'] = kind
      ..fields['scope'] = scope
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (passNumber != null) request.fields['pass_number'] = '$passNumber';
    if (chunkIndex != null) request.fields['chunk_index'] = '$chunkIndex';
    _read(await _sendMultipart(request), (json) => json);
  }

  Future<BackTranslationRestart> restartBackTranslation(String sessionId) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/back-translation/restart'),
        headers: _headers,
      ),
      _stateTimeout,
    );
    return _read(response, BackTranslationRestart.fromJson);
  }

  Future<void> askForAPerson(String sessionId) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/needs-person'),
        headers: _headers,
      ),
      _stateTimeout,
    );
    _read(response, (json) => json);
  }

  Future<BackTranslationVerdict> finishBackTranslation(
    String sessionId, {
    int? clipDurationMs,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/back-translation/finish'),
        headers: _headers,
        body: clipDurationMs == null || clipDurationMs <= 0
            ? null
            : jsonEncode({
                'played_ranges': [
                  [0, clipDurationMs],
                ],
                'clip_duration_ms': clipDurationMs,
              }),
      ),
      _turnTimeout,
    );
    return _read(response, BackTranslationVerdict.fromJson);
  }

  Future<Uint8List> fetchClip(String url) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('${Env.backendUrl}$url'),
        headers: {'X-Room-Key': Env.roomKey},
      ),
      _turnTimeout,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RoomRefused();
    }
    if (response.statusCode != 200) {
      throw RoomBroke('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) => _send(
        () async => http.Response.fromStream(await _client.send(request)),
        _turnTimeout,
      );

  Future<http.Response> _send(
    Future<http.Response> Function() call,
    Duration timeout,
  ) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const RoomSlow();
    } on Exception catch (error) {
      throw RoomUnavailable('$error');
    }
  }

  T _read<T>(http.Response response, T Function(Map<String, dynamic>) build) {
    final body = _decode(response);
    try {
      return build(body);
    } on TypeError catch (error) {
      throw RoomBroke('resposta sem os campos esperados: $error');
    } on FormatException catch (error) {
      throw RoomBroke('resposta ilegível: $error');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RoomRefused();
    }
    if (response.statusCode == 404) {
      throw const SessionGone();
    }
    if (response.statusCode != 200) {
      throw RoomBroke('HTTP ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Exception catch (error) {
      throw RoomBroke('resposta ilegível: $error');
    } on TypeError catch (error) {
      throw RoomBroke('resposta em formato inesperado: $error');
    }
  }

  void dispose() => _client.close();
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final repository = RoomRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
