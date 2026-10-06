import '../domain/failure_policy.dart';

export '../domain/refusal_code.dart';

sealed class RoomAnswer<T> {
  const RoomAnswer();
}

final class Answered<T> extends RoomAnswer<T> {
  final T value;

  const Answered(this.value);
}

sealed class RoomFailure extends RoomAnswer<Never> implements Exception {
  const RoomFailure();
}

final class NetworkFailed extends RoomFailure {
  final String reason;

  const NetworkFailed(this.reason);

  @override
  String toString() => 'NetworkFailed: $reason';
}

final class Refused extends RoomFailure {
  final String code;
  final String detail;

  const Refused(this.code, [this.detail = '']);

  @override
  String toString() => 'Refused: $code $detail';
}

final class SessionGone extends RoomFailure {
  const SessionGone();

  @override
  String toString() => 'SessionGone';
}

extension TheResultOfAFailure on RoomFailure {
  RoomResult get result => switch (this) {
    NetworkFailed() => const RoomNetworkFailed(),
    Refused(:final code) => RoomRefused(code),
    SessionGone() => const RoomSessionGone(),
  };
}
