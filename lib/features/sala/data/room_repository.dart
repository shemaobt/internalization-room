import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../domain/approval_answer.dart';
import '../domain/bt_finding.dart';
import '../domain/coverage.dart';
import '../domain/coverage_event.dart';
import '../domain/device_link.dart';
import '../domain/escuta_das_partes.dart';
import '../domain/passagem.dart';
import '../domain/session_snapshot.dart';
import '../domain/turn_result.dart';
import 'device_identity.dart';
import 'room_answer.dart';
import 'room_client.dart';
import 'shared_http_client.dart';

const _basePath = '/api/internalization-room';

/// The client's rung of the turn ladder: above the turn route's 300 s server bound
/// (ENG-817), below the busy-state watchdog in session_notifier.dart (330 s).
const _turnTimeout = Duration(seconds: 310);
const _defaultStateTimeout = Duration(seconds: 20);

class RoomRepository {
  static const turnTimeout = _turnTimeout;

  final http.Client _client;
  final bool _ownsClient;
  final Future<String> Function() _deviceId;
  final Duration _stateTimeout;
  late final RoomClient _room = RoomClient(_client);

  RoomRepository({
    http.Client? client,
    Future<String> Function()? deviceId,
    this._stateTimeout = _defaultStateTimeout,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _deviceId = deviceId ?? deviceIdentity;

  http.Client get client => _client;

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
  Future<RoomAnswer<String>> collectTheCredential(String deviceId) => _room.ask(
    () =>
        _client.post(_uri('/devices/$deviceId/credential'), headers: _headers),
    timeout: _stateTimeout,
    read: readJson((json) => json['credential'] as String),
    asksForTheSession: false,
    atThisDoor: const {
      409: Refused(RefusalCode.credentialNotYet),
      403: Refused(RefusalCode.credentialTaken),
    },
  );

  Future<RoomAnswer<ClaimCode>> askForACode(String? deviceId) => _room.ask(
    () => _client.post(
      _uri('/devices/code'),
      headers: _headers,
      body: jsonEncode({'device_id': ?deviceId}),
    ),
    timeout: _stateTimeout,
    read: readJson(ClaimCode.fromJson),
    asksForTheSession: false,
  );

  Future<RoomAnswer<TeamLink?>> readTheLink(String deviceId) => _room.ask(
    () => _client.get(_uri('/devices/$deviceId/link'), headers: _headers),
    timeout: _stateTimeout,
    read: readJson(TeamLink.fromJson),
    asksForTheSession: false,
    atThisDoor: const {204: Answered(null)},
  );

  Future<RoomAnswer<SessionSnapshot>> createSession({
    String? pericope,
    String? afterSession,
    required String language,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions'),
      headers: _headers,
      body: jsonEncode({
        'pericope': ?pericope,
        'after_session': ?afterSession,
        'language': language,
      }),
    ),
    timeout: _stateTimeout,
    read: readJson(SessionSnapshot.fromJson),
    asksForTheSession: afterSession != null,
    atThisDoor: const {400: Refused(RefusalCode.passageCannotOpen)},
  );

  /// The passages of a book, each with the line that names it aloud.
  ///
  /// This gets the turn budget, not the state one: the route walks every passage of the
  /// book and synthesizes a line for each, so it is generative work wearing the shape of
  /// a read. Twenty seconds turned a room that was still working into "the internet is
  /// gone" — spoken, to a team that cannot read the difference.
  Future<RoomAnswer<List<Passagem>>> passagesOf(
    String book, {
    required String language,
  }) => _room.ask(
    () => _client.get(
      _uri('/books/$book/passages?language=$language'),
      headers: _headers,
    ),
    timeout: _turnTimeout,
    read: readJson(passagensFromJson),
    asksForTheSession: false,
  );

  Future<RoomAnswer<SessionSnapshot>> fetchState(String sessionId) => _room.ask(
    () => _client.get(_uri('/sessions/$sessionId'), headers: _headers),
    timeout: _stateTimeout,
    read: readJson(SessionSnapshot.fromJson),
    asksForTheSession: true,
  );

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
      final http.StreamedResponse response;
      try {
        response = await _room.open(
          http.Request('GET', _uri('/sessions/$sessionId/coverage'))
            ..headers.addAll(_headers),
          asksForTheSession: true,
        );
      } on RoomFailure catch (failure) {
        if (!cancelled) controller.addError(failure);
        await controller.close();
        return;
      }
      if (cancelled) {
        unawaited(response.stream.listen(null).cancel());
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
                final parsed = _parseCoverageEvent(eventName, data.toString());
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
            onError: (Object error) {
              if (!cancelled) controller.addError(NetworkFailed('$error'));
              controller.close();
            },
          );
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
      return CoverageEvent(
        turnId: turnId,
        status: status,
        coverage: json['coverage'] == null
            ? null
            : Coverage.fromJson(
                (json['coverage'] as Map).cast<String, dynamic>(),
              ),
      );
    } on FormatException {
      return null;
    }
  }

  Future<RoomAnswer<TurnResult>> openSession(
    String sessionId, {
    String? turnId,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/turns'),
      headers: _whoWeAre,
      body: turnId == null ? null : {'turn_id': turnId},
    ),
    timeout: _turnTimeout,
    read: readJson(TurnResult.fromJson),
    asksForTheSession: true,
  );

  /// One voiced take, under the id it keeps across every resend. The id is not optional:
  /// a take sent without one is a new turn to the room each time it goes, and a resend
  /// of it is answered twice.
  Future<RoomAnswer<TurnResult>> sendTurn(
    String sessionId,
    File audio, {
    required String turnId,
    String? clientTiming,
    Duration? timeout,
  }) async {
    final request =
        http.MultipartRequest('POST', _uri('/sessions/$sessionId/turns'))
          ..headers.addAll(_whoWeAre)
          ..fields['turn_id'] = turnId
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (clientTiming != null) request.fields['client_timing'] = clientTiming;
    return _room.askStreamed(
      request,
      timeout: timeout ?? _turnTimeout,
      read: readJson(TurnResult.fromJson),
      asksForTheSession: true,
    );
  }

  /// One stretch told back: which rehearsal recording it explains, and the slice of
  /// **that file** it covers. The three travel together — a slice with no file to be a
  /// slice of is the global ruler under another name.
  Future<RoomAnswer<BackTranslationChunk>> sendChunk(
    String sessionId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
    required String idempotencyKey,
  }) async => _room.askStreamed(
    http.MultipartRequest(
        'POST',
        _uri('/sessions/$sessionId/back-translation/chunks'),
      )
      ..headers.addAll(_whoWeAre)
      ..headers['Idempotency-Key'] = idempotencyKey
      ..headers['X-Room-Device'] = await _deviceId()
      ..fields['take_id'] = takeId
      ..fields['starts_ms'] = '${from.inMilliseconds}'
      ..fields['ends_ms'] = '${to.inMilliseconds}'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path)),
    timeout: _turnTimeout,
    read: readJson(BackTranslationChunk.fromJson),
    asksForTheSession: true,
  );

  /// Store one take and answer with the name the room gave it.
  ///
  /// The answer used to be thrown away. A told-back stretch names the recording it came
  /// from, and this is the only place that name is ever said.
  Future<RoomAnswer<String>> sendTake(
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
    return _room.askStreamed(
      request,
      timeout: _turnTimeout,
      read: readJson((json) => json['take_id'] as String),
      asksForTheSession: true,
    );
  }

  /// Every recording the room is holding for this session.
  ///
  /// Asked for the one thing the stretches cannot say: which part of the rehearsal a
  /// recording answers for. A stretch names the recording it slices and nothing else, so
  /// a tablet picking a session back up over a recording it does not hold learns from
  /// here which of its own parts that stretch belongs to.
  Future<RoomAnswer<List<TakeView>>> takesOf(String sessionId) => _room.ask(
    () => _client.get(_uri('/sessions/$sessionId/takes'), headers: _headers),
    timeout: _stateTimeout,
    read: readJson(TakeView.listFrom),
    asksForTheSession: true,
  );

  /// Where the audio of one take is, for [fetchClip] to go and get.
  ///
  /// The door a tablet holding a session's stretches and none of its files fetches the
  /// room's own parts back through, on a resume (ADR 0023). The route answers a signed
  /// redirect, which the client follows on its own.
  static String takeAudioUrl(String sessionId, String takeId) =>
      '$_basePath/sessions/$sessionId/takes/$takeId/audio';

  /// A new version of one stretch: the explanation redone over the same slice.
  ///
  /// The audio is required. A replacement with none was the mother tongue of one stretch
  /// recorded again, and that is not a unit this room records.
  Future<RoomAnswer<TellingAgain>> replaceSegment(
    String sessionId,
    String segmentId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
    required String idempotencyKey,
  }) async => _room.askStreamed(
    http.MultipartRequest(
        'POST',
        _uri('/sessions/$sessionId/segments/$segmentId/replace'),
      )
      ..headers.addAll(_whoWeAre)
      ..headers['Idempotency-Key'] = idempotencyKey
      ..headers['X-Room-Device'] = await _deviceId()
      ..fields['take_id'] = takeId
      ..fields['starts_ms'] = '${from.inMilliseconds}'
      ..fields['ends_ms'] = '${to.inMilliseconds}'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path)),
    timeout: _turnTimeout,
    read: readJson(TellingAgain.fromJson),
    asksForTheSession: false,
  );

  /// The team's approval of its own final draft.
  ///
  /// The room packages the rows it already holds and hashes them, so nothing travels with
  /// the press. A second approval of unchanged content comes back as the release already
  /// there, which is the same answer.
  Future<RoomAnswer<ApprovalAnswer>> approveRelease(String sessionId) =>
      _room.ask(
        () async => _client.post(
          _uri('/sessions/$sessionId/release'),
          headers: {..._headers, 'X-Room-Device': await _deviceId()},
        ),
        timeout: _stateTimeout,
        read: readJson(ApprovalAnswer.fromJson),
        asksForTheSession: true,
      );

  Future<RoomAnswer<void>> askForAPerson(String sessionId) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/needs-person'),
      headers: _headers,
    ),
    timeout: _stateTimeout,
    read: readJson((_) {}),
    asksForTheSession: true,
  );

  Future<RoomAnswer<void>> personArrived(String sessionId) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/person-arrived'),
      headers: _headers,
    ),
    timeout: _stateTimeout,
    read: readJson((_) {}),
    asksForTheSession: true,
  );

  /// The device-scoped ask, for a halt that has no session to ask through.
  Future<RoomAnswer<void>> askForAPersonWithoutASession(String deviceId) =>
      _room.ask(
        () => _client.post(
          _uri('/devices/$deviceId/needs-person'),
          headers: _headers,
        ),
        timeout: _stateTimeout,
        read: readJson((_) {}),
        asksForTheSession: false,
        atThisDoor: const {
          404: Refused(RefusalCode.nobodyToReach),
          409: Refused(RefusalCode.nobodyToReach),
        },
      );

  Future<RoomAnswer<BackTranslationVerdict>> finishBackTranslation(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) => _room.ask(
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
    timeout: _turnTimeout,
    read: readJson(BackTranslationVerdict.fromJson),
    asksForTheSession: true,
  );

  Future<RoomAnswer<Uint8List>> fetchClip(String url) => _room.ask(
    () => _client.get(Uri.parse('${Env.backendUrl}$url'), headers: _whoWeAre),
    timeout: _turnTimeout,
    read: (response) => response.bodyBytes,
    asksForTheSession: false,
  );

  Future<http.StreamedResponse> openClip(
    String url, {
    int? from,
    String? ifRange,
  }) {
    final request = http.Request('GET', Uri.parse('${Env.backendUrl}$url'))
      ..headers.addAll(_whoWeAre);
    if (from != null) request.headers['Range'] = 'bytes=$from-';
    if (ifRange != null) request.headers['If-Range'] = ifRange;
    return _room.open(request, timeout: _turnTimeout, asksForTheSession: false);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final repository = RoomRepository(
    client: ref.watch(sharedHttpClientProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
