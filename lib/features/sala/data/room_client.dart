import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';

import 'package:http/http.dart' as http;

import 'room_answer.dart';

T Function(http.Response) readJson<T>(T Function(Map<String, dynamic>) build) =>
    (response) => build(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );

class RoomClient {
  final http.Client _http;

  const RoomClient(this._http);

  static int _minted = 0;

  static String mintAKey() =>
      '${clock.now().microsecondsSinceEpoch}-${_minted++}-${Random().nextInt(1 << 32)}';

  Future<RoomAnswer<T>> ask<T>(
    Future<http.Response> Function() send, {
    required Duration timeout,
    required T Function(http.Response) read,
    bool asksForTheSession = true,
    Map<int, RoomAnswer<T>> atThisDoor = const {},
  }) async {
    final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      return const NetworkFailed('timeout');
    } on Exception catch (error) {
      return NetworkFailed('$error');
    }
    final atTheDoor = atThisDoor[response.statusCode];
    if (atTheDoor != null) return atTheDoor;
    final failure = classify(
      response.statusCode,
      response.bodyBytes,
      asksForTheSession: asksForTheSession,
    );
    if (failure != null) return failure;
    try {
      return Answered(read(response));
    } on FormatException catch (error) {
      return Refused(RefusalCode.unreadable, '$error');
    } on TypeError catch (error) {
      return Refused(RefusalCode.unreadable, '$error');
    }
  }

  Future<RoomAnswer<T>> askStreamed<T>(
    http.BaseRequest request, {
    required Duration timeout,
    required T Function(http.Response) read,
    bool asksForTheSession = true,
  }) => ask(
    () async => http.Response.fromStream(await _http.send(request)),
    timeout: timeout,
    read: read,
    asksForTheSession: asksForTheSession,
  );

  Future<http.StreamedResponse> open(
    http.BaseRequest request, {
    Duration? timeout,
    required bool asksForTheSession,
  }) async {
    final http.StreamedResponse response;
    try {
      final sent = _http.send(request);
      response = await (timeout == null ? sent : sent.timeout(timeout));
    } on TimeoutException {
      throw const NetworkFailed('timeout');
    } on Exception catch (error) {
      throw NetworkFailed('$error');
    }
    final failure = classify(
      response.statusCode,
      const [],
      asksForTheSession: asksForTheSession,
    );
    if (failure != null) {
      unawaited(response.stream.listen(null).cancel());
      throw failure;
    }
    return response;
  }

  static RoomFailure? classify(
    int status,
    List<int> body, {
    required bool asksForTheSession,
  }) {
    if (status >= 200 && status < 300) return null;
    if (status == 429 || status >= 500) return NetworkFailed('HTTP $status');
    if (status == 404 && asksForTheSession) return const SessionGone();
    if (status == 401) return const Refused(RefusalCode.unauthorized);
    final (:code, :detail) = _named(body);
    if (status == 403) {
      return Refused(
        code == RefusalCode.deviceRevoked
            ? RefusalCode.deviceRevoked
            : RefusalCode.forbidden,
        detail,
      );
    }
    return Refused(
      code ??
          switch (status) {
            404 => RefusalCode.notFound,
            _ => 'HTTP_$status',
          },
      detail,
    );
  }

  static ({String? code, String detail}) _named(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      if (json is Map<String, dynamic>) {
        final code = json['code'];
        final detail = json['detail'];
        return (
          code: code is String ? code : null,
          detail: detail is String ? detail : '',
        );
      }
    } on FormatException {
      return (code: null, detail: '');
    }
    return (code: null, detail: '');
  }
}
