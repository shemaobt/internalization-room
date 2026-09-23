import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/approval_answer.dart';
import '../domain/bt_finding.dart';
import '../domain/coverage_event.dart';
import '../domain/device_link.dart';
import '../domain/escuta_das_partes.dart';
import '../domain/passagem.dart';
import '../domain/session_snapshot.dart';
import '../domain/turn_result.dart';
import 'device_identity.dart';

const _basePath = '/api/internalization-room';

/// The client's rung of the turn ladder: above the turn route's 300 s server bound
/// (ENG-817), below the busy-state watchdog in session_notifier.dart (330 s).
const _turnTimeout = Duration(seconds: 310);
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

/// The row is not claimed yet, or was taken out of service. Temporary: the answer to it
/// is to go on asking whose the tablet is, and to try collecting again next cycle.
class CredentialNotYet implements Exception {
  const CredentialNotYet();

  @override
  String toString() => 'CredentialNotYet';
}

/// The credential was handed out already, and the server keeps only its hash — so there
/// is nothing left to hand out again. Permanent, and what a lost 200 turns into.
class CredentialTaken implements Exception {
  const CredentialTaken();

  @override
  String toString() => 'CredentialTaken';
}

class PassageShut implements Exception {
  const PassageShut();
}

/// The device has no team to reach: nobody claimed it, it was taken out of service, or
/// the id was never minted. Asking again cannot change that, the way a spent credential
/// cannot be handed out twice — final, not retried.
class NobodyToReach implements Exception {
  const NobodyToReach();
}

class RoomRepository {
  static const turnTimeout = _turnTimeout;

  final http.Client _client;
  final Future<String> Function() _deviceId;

  RoomRepository({http.Client? client, Future<String> Function()? deviceId})
    : _client = client ?? http.Client(),
      _deviceId = deviceId ?? deviceIdentity;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    ..._whoWeAre,
  };

  /// Who this tablet is, on every request it makes.
  ///
  /// One builder rather than nine here and five written out by hand at the call sites:
  /// a header each site spells for itself is a header the next site forgets, and the
  /// omission only ever shows against a real server.
  Map<String, String> get _whoWeAre => {
    'X-Room-Key': Env.roomKey,
    'X-Device-Credential': ?_credential,
  };

  String? _credential;

  /// What this tablet presents as itself from now on, or nothing until it has collected
  /// one. The only place the credential enters the repository.
  void presents(String? credential) => _credential = credential;

  Uri _uri(String path) => Uri.parse('${Env.backendUrl}$_basePath$path');

  /// The one and only copy of this tablet's credential, drawn once for the device id the
  /// claim code was minted for.
  Future<String> collectTheCredential(String deviceId) async {
    final response = await _send(
      () => _client.post(
        _uri('/devices/$deviceId/credential'),
        headers: _headers,
      ),
      _stateTimeout,
    );
    if (response.statusCode == 409) throw const CredentialNotYet();
    if (response.statusCode == 403) throw const CredentialTaken();
    return _read(response, (json) => json['credential'] as String);
  }

  Future<ClaimCode> askForACode(String? deviceId) async {
    final response = await _send(
      () => _client.post(
        _uri('/devices/code'),
        headers: _headers,
        body: jsonEncode({'device_id': ?deviceId}),
      ),
      _stateTimeout,
    );
    return _read(response, ClaimCode.fromJson);
  }

  Future<TeamLink?> readTheLink(String deviceId) async {
    final response = await _send(
      () => _client.get(_uri('/devices/$deviceId/link'), headers: _headers),
      _stateTimeout,
    );
    if (response.statusCode == 204) return null;
    return _read(response, TeamLink.fromJson);
  }

  Future<SessionSnapshot> createSession({
    String? pericope,
    String? afterSession,
    required String language,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions'),
        headers: _headers,
        body: jsonEncode({
          'pericope': ?pericope,
          'after_session': ?afterSession,
          'language': language,
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
  Future<List<Passagem>> passagesOf(
    String book, {
    required String language,
  }) async {
    final response = await _send(
      () => _client.get(
        _uri('/books/$book/passages?language=$language'),
        headers: _headers,
      ),
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

  Stream<CoverageEvent> watchCoverage(String sessionId) {
    StreamSubscription<String>? lineSub;
    var cancelled = false;
    final controller = StreamController<CoverageEvent>(
      onCancel: () {
        cancelled = true;
        return lineSub?.cancel();
      },
    );
    unawaited(() async {
      try {
        final response = await _client.send(
          http.Request('GET', _uri('/sessions/$sessionId/coverage'))
            ..headers.addAll(_headers),
        );
        if (cancelled) {
          unawaited(response.stream.listen(null).cancel());
          return;
        }
        if (response.statusCode != 200) {
          unawaited(response.stream.listen(null).cancel());
          if (response.statusCode == 401 || response.statusCode == 403) {
            controller.addError(const RoomRefused());
          } else if (response.statusCode == 404) {
            controller.addError(const SessionGone());
          } else {
            controller.addError(RoomBroke('HTTP ${response.statusCode}'));
          }
          await controller.close();
          return;
        }
        String? eventName;
        final data = StringBuffer();
        lineSub = utf8.decoder
            .bind(response.stream)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (line.isEmpty) {
                  final parsed = _parseCoverageEvent(
                    eventName,
                    data.toString(),
                  );
                  if (parsed != null) controller.add(parsed);
                  eventName = null;
                  data.clear();
                  return;
                }
                if (line.startsWith('event:')) {
                  eventName = line.substring(6).trim();
                } else if (line.startsWith('data:')) {
                  if (data.isNotEmpty) data.write('\n');
                  data.write(line.substring(5).trim());
                }
              },
              onDone: controller.close,
              onError: (Object _) => controller.close(),
            );
      } on Exception {
        await controller.close();
      }
    }());
    return controller.stream;
  }

  CoverageEvent? _parseCoverageEvent(String? eventName, String data) {
    if (eventName != 'coverage' || data.isEmpty) return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final turnId = json['turn_id'] as String?;
      final status = switch (json['status']) {
        'settled' => CoverageStatus.settled,
        'failed' => CoverageStatus.failed,
        _ => null,
      };
      if (turnId == null || status == null) return null;
      return CoverageEvent(turnId: turnId, status: status);
    } on FormatException {
      return null;
    }
  }

  Future<TurnResult> openSession(String sessionId, {String? turnId}) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/turns'),
        headers: _whoWeAre,
        body: turnId == null ? null : {'turn_id': turnId},
      ),
      _turnTimeout,
    );
    return _read(response, TurnResult.fromJson);
  }

  Future<TurnResult> sendTurn(
    String sessionId,
    File audio, {
    String? clientTiming,
  }) async {
    final request =
        http.MultipartRequest('POST', _uri('/sessions/$sessionId/turns'))
          ..headers.addAll(_whoWeAre)
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (clientTiming != null) request.fields['client_timing'] = clientTiming;
    return _read(await _sendMultipart(request), TurnResult.fromJson);
  }

  /// One stretch told back: which rehearsal recording it explains, and the slice of
  /// **that file** it covers. The three travel together — a slice with no file to be a
  /// slice of is the global ruler under another name.
  Future<BackTranslationChunk> sendChunk(
    String sessionId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/sessions/$sessionId/back-translation/chunks'),
          )
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..fields['take_id'] = takeId
          ..fields['starts_ms'] = '${from.inMilliseconds}'
          ..fields['ends_ms'] = '${to.inMilliseconds}'
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    return _read(await _sendMultipart(request), BackTranslationChunk.fromJson);
  }

  /// Store one take and answer with the name the room gave it.
  ///
  /// The answer used to be thrown away. A told-back stretch names the recording it came
  /// from, and this is the only place that name is ever said.
  Future<String> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    final request =
        http.MultipartRequest('POST', _uri('/sessions/$sessionId/takes'))
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..fields['kind'] = kind
          ..fields['scope'] = scope
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (passNumber != null) request.fields['pass_number'] = '$passNumber';
    if (chunkIndex != null) request.fields['chunk_index'] = '$chunkIndex';
    return _read(
      await _sendMultipart(request),
      (json) => json['take_id'] as String,
    );
  }

  /// Every recording the room is holding for this session.
  ///
  /// Asked for the one thing the stretches cannot say: which part of the rehearsal a
  /// recording answers for. A stretch names the recording it slices and nothing else, so
  /// a tablet picking a session back up over a recording it does not hold learns from
  /// here which of its own parts that stretch belongs to.
  Future<List<TakeView>> takesOf(String sessionId) async {
    final response = await _send(
      () => _client.get(_uri('/sessions/$sessionId/takes'), headers: _headers),
      _stateTimeout,
    );
    return _read(response, TakeView.listFrom);
  }

  /// Where the audio of one take is, for [fetchClip] to go and get.
  ///
  /// The door a tablet holding a session's stretches and none of its files fetches the
  /// room's own parts back through, on a resume (ADR 0023). The route answers a signed
  /// redirect, which the client follows on its own.
  static String takeAudioUrl(String sessionId, String takeId) =>
      '$_basePath/sessions/$sessionId/takes/$takeId/audio';

  Future<List<SegmentView>> divideSegment(
    String sessionId,
    String segmentId, {
    required Duration at,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/segments/$segmentId/divide'),
        headers: _headers,
        body: jsonEncode({'at_ms': at.inMilliseconds}),
      ),
      _stateTimeout,
    );
    return _read(response, SegmentView.listFrom);
  }

  /// A new version of one stretch: the explanation redone over the same slice.
  ///
  /// The audio is required. A replacement with none was the mother tongue of one stretch
  /// recorded again, and that is not a unit this room records.
  Future<TellingAgain> replaceSegment(
    String sessionId,
    String segmentId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/sessions/$sessionId/segments/$segmentId/replace'),
          )
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..fields['take_id'] = takeId
          ..fields['starts_ms'] = '${from.inMilliseconds}'
          ..fields['ends_ms'] = '${to.inMilliseconds}';
    request.files.add(await http.MultipartFile.fromPath('file', audio.path));
    return _read(await _sendMultipart(request), TellingAgain.fromJson);
  }

  /// The team's approval of its own final draft.
  ///
  /// The room packages the rows it already holds and hashes them, so nothing travels with
  /// the press. A second approval of unchanged content comes back as the release already
  /// there, which is the same answer.
  Future<ApprovalAnswer> approveRelease(String sessionId) async {
    final response = await _send(
      () async => _client.post(
        _uri('/sessions/$sessionId/release'),
        headers: {..._headers, 'X-Room-Device': await _deviceId()},
      ),
      _stateTimeout,
    );
    return _read(response, ApprovalAnswer.fromJson);
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

  Future<void> personArrived(String sessionId) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/person-arrived'),
        headers: _headers,
      ),
      _stateTimeout,
    );
    _read(response, (json) => json);
  }

  /// The device-scoped ask, for a halt that has no session to ask through: the server
  /// forgot it, or the build never opened one.
  Future<void> askForAPersonWithoutASession(String deviceId) async {
    final response = await _send(
      () => _client.post(
        _uri('/devices/$deviceId/needs-person'),
        headers: _headers,
      ),
      _stateTimeout,
    );
    if (response.statusCode == 404 || response.statusCode == 409) {
      throw const NobodyToReach();
    }
    _read(response, (json) => json);
  }

  Future<BackTranslationVerdict> finishBackTranslation(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/sessions/$sessionId/back-translation/finish'),
        headers: _headers,
        // What was heard, as it was heard, part by part. Declaring nought-to-the-end made
        // the report a restatement of the clip's length, and the gate that reads it could
        // never fail; saying it of the parts glued together left it with no subject, so
        // one part recorded again threw away the listening to all the others.
        body: playedByTake.isEmpty
            ? null
            : jsonEncode({
                'played_by_take': [
                  for (final parte in playedByTake) parte.toJson(),
                ],
              }),
      ),
      _turnTimeout,
    );
    return _read(response, BackTranslationVerdict.fromJson);
  }

  Future<Uint8List> fetchClip(String url) async {
    final response = await _send(
      () => _client.get(Uri.parse('${Env.backendUrl}$url'), headers: _whoWeAre),
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
    if (response.statusCode == 400) {
      throw const PassageShut();
    }
    if (response.statusCode != 200) {
      throw RoomBroke('HTTP ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
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
