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
import '../domain/cut_point.dart';
import '../domain/device_link.dart';
import '../domain/escuta_das_partes.dart';
import '../domain/passagem.dart';
import '../domain/scene_rehearsal.dart';
import '../domain/scene_question.dart';
import '../domain/session_snapshot.dart';
import '../domain/turn_result.dart';
import 'device_identity.dart';
import 'room_answer.dart';
import 'room_client.dart';
import 'shared_http_client.dart';

const _basePath = '/api/internalization-room';

/// A turn gives up at the turn route's 300 s server bound (ENG-817) plus a 5 s margin,
/// below the busy-state watchdog in session_notifier.dart (330 s), and is then looked at
/// once.
const _turnTimeout = Duration(seconds: 305);

/// Every other call that can run long waits 310 s.
const _longCallTimeout = Duration(seconds: 310);
const _defaultStateTimeout = Duration(seconds: 20);

/// Her `SCENES_WAIT_MS`: a scene list later than this is no list.
const _scenesTimeout = sceneListWait;

class RoomRepository {
  static const turnTimeout = _turnTimeout;

  final http.Client client;
  late final http.Client _client = KeepsTheRequest(client);
  final bool _ownsClient;
  final Future<String> Function() _deviceId;
  final Duration _stateTimeout;
  late final RoomClient _room = RoomClient(_client);

  RoomRepository({
    http.Client? client,
    Future<String> Function()? deviceId,
    this._stateTimeout = _defaultStateTimeout,
  }) : client = client ?? http.Client(),
       _ownsClient = client == null,
       _deviceId = deviceId ?? deviceIdentity;

  Stream<String?> get revoked => _room.revoked;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    ..._whoWeAre,
  };

  /// Who this tablet is, on every request it makes.
  ///
  /// One builder rather than nine here and five written out by hand at the call sites:
  /// a header each site spells for itself is a header the next site forgets, and the
  /// omission only ever shows against a real server.
  Map<String, String> get _whoWeAre => {deviceCredentialHeader: ?_credential};

  /// The claim doors open to anyone: a tablet that belongs to no team yet has nothing to
  /// present, and the code is only worth what a facilitator spends on it.
  static const _claimHeaders = {'Content-Type': 'application/json'};

  String? _credential;

  /// What this tablet presents as itself from now on, or nothing until it has collected
  /// one. The only place the credential enters the repository.
  void presents(String? credential) => _credential = credential;

  Uri _uri(String path) => Uri.parse('${Env.backendUrl}$_basePath$path');

  /// The one and only copy of this tablet's credential, drawn once for the device id the
  /// claim code was minted for.
  Future<RoomAnswer<String>> collectTheCredential(String deviceId) => _room.ask(
    () => _client.post(
      _uri('/devices/$deviceId/credential'),
      headers: _claimHeaders,
    ),
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
      headers: _claimHeaders,
      body: jsonEncode({'device_id': ?deviceId}),
    ),
    timeout: _stateTimeout,
    read: readJson(ClaimCode.fromJson),
    asksForTheSession: false,
  );

  Future<RoomAnswer<TeamLink?>> readTheLink(String deviceId) => _room.ask(
    () => _client.get(_uri('/devices/$deviceId/link'), headers: _claimHeaders),
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
    timeout: _longCallTimeout,
    read: readJson(passagensFromJson),
    asksForTheSession: false,
  );

  Future<RoomAnswer<List<String>>> servedBooks() => _room.ask(
    () => _client.get(_uri('/books'), headers: _headers),
    timeout: _stateTimeout,
    read: readJson(
      (json) => [
        for (final book in json['books'] as List<Object?>) book as String,
      ],
    ),
    asksForTheSession: false,
  );

  Future<RoomAnswer<SessionSnapshot>> fetchState(String sessionId) => _room.ask(
    () => _client.get(
      _uri('/sessions/$sessionId?include_stale=true'),
      headers: _headers,
    ),
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

  /// The one look at a turn this tablet gave up on, without sending it again.
  Future<RoomAnswer<TurnResult>> lookAtTheTurn(
    String sessionId,
    String turnId,
  ) => _room.ask(
    () => _client.get(
      _uri('/sessions/$sessionId/turns/$turnId'),
      headers: _headers,
    ),
    timeout: _stateTimeout,
    read: readJson(TurnResult.fromJson),
    asksForTheSession: false,
    atThisDoor: {202: Refused(RefusalCode.unnamed(202))},
  );

  /// One voiced take, under the id it keeps. The id is not optional: a take sent without
  /// one is a new turn to the room each time it goes, and the one look cannot find it.
  Future<RoomAnswer<TurnResult>> sendTurn(
    String sessionId,
    File audio, {
    required String turnId,
    String? clientTiming,
    CutPoint? cut,
  }) async {
    final request =
        http.MultipartRequest('POST', _uri('/sessions/$sessionId/turns'))
          ..headers.addAll(_whoWeAre)
          ..fields['turn_id'] = turnId
          ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (clientTiming != null) request.fields['client_timing'] = clientTiming;
    if (cut != null) {
      request.fields['interrupted'] = 'true';
      request.fields['interrupted_at_ms'] = '${cut.at.inMilliseconds}';
      final of = cut.of;
      if (of != null) {
        request.fields['interrupted_of_ms'] = '${of.inMilliseconds}';
      }
    }
    return _room.askStreamed(
      request,
      timeout: _turnTimeout,
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
    timeout: _longCallTimeout,
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
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
  }) async {
    final request =
        http.MultipartRequest('POST', _uri('/sessions/$sessionId/takes'))
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..fields['kind'] = kind
          ..fields['scope'] = scope
          ..files.add(await _audioPart(audio));
    if (passNumber != null) request.fields['pass_number'] = '$passNumber';
    if (chunkIndex != null) request.fields['chunk_index'] = '$chunkIndex';
    _announce(request, recordedAt, durationMs, sha256);
    return _room.askStreamed(
      request,
      timeout: _longCallTimeout,
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

  /// The passage's live scene rehearsals, from every session of it, each naming its own.
  Future<RoomAnswer<List<SceneRehearsalRecord>>> sceneRehearsalsOf(
    String sessionId,
  ) => _room.ask(
    () => _client.get(
      _uri('/sessions/$sessionId/scene-rehearsals'),
      headers: _headers,
    ),
    timeout: _stateTimeout,
    read: readJson(SceneRehearsalRecord.listFrom),
    asksForTheSession: true,
  );

  Future<RoomAnswer<List<Scene>>> scenesOf(String sessionId) => _room.ask(
    () => _client.get(_uri('/sessions/$sessionId/scenes'), headers: _headers),
    timeout: _scenesTimeout,
    read: readJson(Scene.listFrom),
    asksForTheSession: true,
  );

  Future<RoomAnswer<SceneRehearsalRecord>> keepSceneRehearsal(
    String sessionId,
    File audio, {
    String? scene,
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/sessions/$sessionId/scene-rehearsals'),
          )
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..files.add(await _audioPart(audio));
    if (scene != null) request.fields['scene'] = scene;
    _announce(request, recordedAt, durationMs, sha256);
    return _room.askStreamed(
      request,
      timeout: _longCallTimeout,
      read: readJson(SceneRehearsalRecord.fromJson),
      asksForTheSession: true,
    );
  }

  static void _announce(
    http.MultipartRequest request,
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
  ) {
    if (recordedAt != null) {
      request.fields['recorded_at'] = recordedAt.toUtc().toIso8601String();
    }
    if (durationMs != null) request.fields['duration_ms'] = '$durationMs';
    if (sha256 != null) request.fields['sha256'] = sha256;
  }

  static Future<http.MultipartFile> _audioPart(File audio) =>
      http.MultipartFile.fromPath(
        'file',
        audio.path,
        contentType: audio.path.endsWith('.wav')
            ? http.MediaType('audio', 'wav')
            : null,
      );

  /// Where the take of one scene rehearsal of this session is, for [fetchClip].
  static String sceneRehearsalAudioUrl(String sessionId, String rehearsalId) =>
      '$_basePath/sessions/$sessionId/scene-rehearsals/$rehearsalId/audio';

  /// Where one frase's translation of a scene rehearsal is, for [fetchClip].
  static String sceneFraseAudioUrl(
    String sessionId,
    String rehearsalId,
    String fraseId,
  ) =>
      '$_basePath/sessions/$sessionId/scene-rehearsals/$rehearsalId/frases/'
      '$fraseId/audio';

  /// «terminei»: the rehearsal goes to the voice by reference as the team's turn
  /// [turnId], closing the attempt its frases follow. It names a rehearsal, whose 404
  /// never ends the session.
  Future<RoomAnswer<TurnResult>> sendTheSceneRehearsal(
    String sessionId,
    String rehearsalId, {
    required String turnId,
    String? closes,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/scene-rehearsals/$rehearsalId/send'),
      headers: _whoWeAre,
      body: {'turn_id': turnId, 'closes': ?closes},
    ),
    timeout: _turnTimeout,
    read: readJson(TurnResult.fromJson),
    asksForTheSession: false,
  );

  /// «recomeçar a tradução» into the [attempt] this tablet minted, closing the one the
  /// current frases follow. It names a rehearsal, whose 404 never ends the session.
  Future<RoomAnswer<SceneRehearsalRecord>> restartTheSceneTranslation(
    String sessionId,
    String rehearsalId, {
    required String attempt,
    String? closes,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/scene-rehearsals/$rehearsalId/restart'),
      headers: _whoWeAre,
      body: {'attempt': attempt, 'closes': ?closes},
    ),
    timeout: _stateTimeout,
    read: readJson(SceneRehearsalRecord.fromJson),
    asksForTheSession: false,
  );

  /// The team's Scene label for an Unlabelled rehearsal, said later. It names a
  /// rehearsal, whose 404 never ends the session.
  Future<RoomAnswer<SceneRehearsalRecord>> labelTheSceneRehearsal(
    String sessionId,
    String rehearsalId, {
    required String scene,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/scene-rehearsals/$rehearsalId/scene'),
      headers: _whoWeAre,
      body: {'scene': scene},
    ),
    timeout: _stateTimeout,
    read: readJson(SceneRehearsalRecord.fromJson),
    asksForTheSession: false,
  );

  /// One frase of a scene rehearsal, told from [startsMs] to [endsMs] of its take,
  /// under the attempt [afterRestart]. It names a rehearsal, whose 404 never ends the
  /// session.
  Future<RoomAnswer<SceneRehearsalRecord>> keepTheSceneFrase(
    String sessionId,
    String rehearsalId,
    File audio, {
    required int startsMs,
    required int endsMs,
    String? afterRestart,
    String? replaces,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/sessions/$sessionId/scene-rehearsals/$rehearsalId/frases'),
          )
          ..headers.addAll(_whoWeAre)
          ..headers['X-Room-Device'] = await _deviceId()
          ..fields['starts_ms'] = '$startsMs'
          ..fields['ends_ms'] = '$endsMs'
          ..files.add(await _audioPart(audio));
    if (afterRestart != null) request.fields['after_restart'] = afterRestart;
    if (replaces != null) request.fields['replaces'] = replaces;
    return _room.askStreamed(
      request,
      timeout: _longCallTimeout,
      read: readJson(SceneRehearsalRecord.fromJson),
      asksForTheSession: false,
    );
  }

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
        _uri(
          '/sessions/$sessionId/segments/$segmentId/replace?include_stale=true',
        ),
      )
      ..headers.addAll(_whoWeAre)
      ..headers['Idempotency-Key'] = idempotencyKey
      ..headers['X-Room-Device'] = await _deviceId()
      ..fields['take_id'] = takeId
      ..fields['starts_ms'] = '${from.inMilliseconds}'
      ..fields['ends_ms'] = '${to.inMilliseconds}'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path)),
    timeout: _longCallTimeout,
    read: readJson(TellingAgain.fromJson),
    asksForTheSession: false,
  );

  Future<RoomAnswer<TellingAgain>> reRecordTheSentence(
    String sessionId,
    String segmentId,
    File audio, {
    required String sentenceId,
  }) async => _room.askStreamed(
    http.MultipartRequest(
        'POST',
        _uri(
          '/sessions/$sessionId/segments/$segmentId/sentence?include_stale=true',
        ),
      )
      ..headers.addAll(_whoWeAre)
      ..headers['X-Room-Device'] = await _deviceId()
      ..fields['sentence_id'] = sentenceId
      ..files.add(await _audioPart(audio)),
    timeout: _longCallTimeout,
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
    timeout: _longCallTimeout,
    read: readJson(BackTranslationVerdict.fromJson),
    asksForTheSession: true,
  );

  Future<RoomAnswer<List<String>?>> reportTheListening(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/back-translation/listened-whole'),
      headers: _headers,
      body: jsonEncode({
        'played_by_take': [for (final parte in playedByTake) parte.toJson()],
      }),
    ),
    timeout: _stateTimeout,
    read: readJson(
      (json) => (json['unheard_take_ids'] as List?)?.cast<String>(),
    ),
    asksForTheSession: false,
  );

  Future<RoomAnswer<void>> reportTheVerdictHeard(String sessionId, String at) =>
      _room.ask(
        () => _client.post(
          _uri('/sessions/$sessionId/back-translation/heard'),
          headers: _headers,
          body: jsonEncode({'at': at}),
        ),
        timeout: _stateTimeout,
        read: readJson((_) {}),
        asksForTheSession: false,
      );

  Future<RoomAnswer<List<SegmentView>>> startTheTranslationOver(
    String sessionId,
  ) => _room.ask(
    () => _client.post(
      _uri('/sessions/$sessionId/back-translation/restart'),
      headers: _whoWeAre,
    ),
    timeout: _stateTimeout,
    read: readJson(SegmentView.listFrom),
    asksForTheSession: true,
  );

  Future<RoomAnswer<String>> fixedLineAddress(
    String line, {
    required String language,
  }) => _room.ask(
    () => _client.get(
      _uri('/fixed-lines/$line?language=$language'),
      headers: _headers,
    ),
    timeout: _stateTimeout,
    read: readJson((json) => json['audio_url'] as String),
    asksForTheSession: false,
  );

  Future<RoomAnswer<Uint8List>> fetchClip(String url) => _room.ask(
    () => _client.get(Uri.parse('${Env.backendUrl}$url'), headers: _whoWeAre),
    timeout: _longCallTimeout,
    read: (response) => response.bodyBytes,
    asksForTheSession: false,
  );

  Future<RoomAnswer<Uint8List>> fetchKeptRetelling(String url) => _room.ask(
    () => _client.get(Uri.parse(url)),
    timeout: _longCallTimeout,
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
    return _room.open(
      request,
      timeout: _longCallTimeout,
      asksForTheSession: false,
    );
  }

  void dispose() {
    _room.close();
    if (_ownsClient) client.close();
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final repository = RoomRepository(
    client: ref.watch(sharedHttpClientProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
